package ecs_tests

import "core:mem"
import "core:testing"

import ecs "../ecs"

// >-------------------------------------------------------------------- Helpers

// Things 1 to 7 with gen 0, so tests can name them by idx.
hierarchy_thing :: proc(idx: ecs.Thing_Idx) -> ecs.Thing {
	return ecs.thing_make(idx)
}

// Builds two trees, in pre-order:
// 1, 2, 4, 5, 3
// 6, 7
hierarchy_build :: proc(pool: ^ecs.Hierarchy_Pool) {
	h := hierarchy_thing
	ecs.hierarchy_pool_attach(pool, h(2), h(1))
	ecs.hierarchy_pool_attach(pool, h(3), h(1))
	ecs.hierarchy_pool_attach(pool, h(4), h(2))
	ecs.hierarchy_pool_attach(pool, h(5), h(2))
	ecs.hierarchy_pool_attach(pool, h(7), h(6))
}

// Chains things 1 to `count` with `count` as the root, so thing 1 sits at depth `count - 1`.
// Attaching above the root keeps every cycle check O(1).
hierarchy_build_chain :: proc(pool: ^ecs.Hierarchy_Pool, count: int) {
	for idx in 1 ..< count {
		ecs.hierarchy_pool_attach(
			pool,
			hierarchy_thing(ecs.Thing_Idx(idx)),
			hierarchy_thing(ecs.Thing_Idx(idx + 1)),
		)
	}
}

hierarchy_expect_order :: proc(
	t: ^testing.T,
	pool: ^ecs.Hierarchy_Pool,
	idxs: []ecs.Thing_Idx,
	loc := #caller_location,
) {
	order := ecs.hierarchy_pool_order(pool)
	if !testing.expect_value(t, len(order), len(idxs), loc) do return

	for thing, i in order do testing.expect_value(t, thing.idx, idxs[i], loc)
}

hierarchy_expect_depths :: proc(
	t: ^testing.T,
	pool: ^ecs.Hierarchy_Pool,
	depths: []ecs.Hierarchy_Depth,
	loc := #caller_location,
) {
	got := ecs.hierarchy_pool_depths(pool)
	if !testing.expect_value(t, len(got), len(depths), loc) do return

	for depth, i in got do testing.expect_value(t, depth, depths[i], loc)
}

hierarchy_expect_children :: proc(
	t: ^testing.T,
	pool: ^ecs.Hierarchy_Pool,
	parent: ecs.Thing,
	idxs: []ecs.Thing_Idx,
	loc := #caller_location,
) {
	it := ecs.hierarchy_pool_iter_children(pool, parent)
	hierarchy_expect_iter(t, &it, idxs, loc)
}

hierarchy_expect_roots :: proc(
	t: ^testing.T,
	pool: ^ecs.Hierarchy_Pool,
	idxs: []ecs.Thing_Idx,
	loc := #caller_location,
) {
	it := ecs.hierarchy_pool_iter_roots(pool)
	hierarchy_expect_iter(t, &it, idxs, loc)
}

hierarchy_expect_iter :: proc(
	t: ^testing.T,
	it: ^ecs.Hierarchy_Children_Iter,
	idxs: []ecs.Thing_Idx,
	loc := #caller_location,
) {
	i := 0
	for thing in ecs.hierarchy_children_iter_next(it) {
		if i < len(idxs) do testing.expect_value(t, thing.idx, idxs[i], loc)
		i += 1
	}
	testing.expect_value(t, i, len(idxs), loc)
}

// >------------------------------------------------------------------ Lifecycle

@(test)
hierarchy_pool_init_creates_empty_pool :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	testing.expect_value(t, ecs.hierarchy_pool_capacity(&pool), ecs.HIERARCHY_POOL_MIN_CAPACITY)
	testing.expect_value(t, ecs.hierarchy_pool_count(&pool), 0)
	testing.expect(t, !ecs.hierarchy_pool_is_dirty(&pool))
	testing.expect_value(t, len(ecs.hierarchy_pool_order(&pool)), 0)

	ecs.hierarchy_pool_rebuild(&pool)
	testing.expect_value(t, len(ecs.hierarchy_pool_order(&pool)), 0)
}

@(test)
hierarchy_pool_destroy_frees_with_init_allocator :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY, mem.tracking_allocator(&track))
	testing.expect(t, len(track.allocation_map) > 0)

	ecs.hierarchy_pool_destroy(&pool)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
	testing.expect(t, pool.nodes == nil)
}

@(test)
hierarchy_pool_reset_empties_pool :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	h := hierarchy_thing
	hierarchy_build(&pool)
	ecs.hierarchy_pool_rebuild(&pool)
	ecs.hierarchy_pool_reset(&pool)

	testing.expect_value(t, ecs.hierarchy_pool_count(&pool), 0)
	testing.expect(t, !ecs.hierarchy_pool_is_dirty(&pool))
	testing.expect_value(t, len(ecs.hierarchy_pool_order(&pool)), 0)
	testing.expect(t, !ecs.hierarchy_pool_contains(&pool, h(1)))
	testing.expect(t, ecs.hierarchy_pool_subtree(&pool, h(1)) == nil)
	hierarchy_expect_roots(t, &pool, {})

	// Usable again after reset.
	ecs.hierarchy_pool_attach(&pool, h(1), h(2))
	ecs.hierarchy_pool_rebuild(&pool)
	hierarchy_expect_order(t, &pool, {2, 1})
}

// >--------------------------------------------------------------------- Attach

@(test)
hierarchy_pool_attach_links_things :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	h := hierarchy_thing
	hierarchy_build(&pool)

	testing.expect_value(t, ecs.hierarchy_pool_count(&pool), 7)
	testing.expect(t, ecs.hierarchy_pool_is_dirty(&pool))
	for idx in 1 ..= 7 do testing.expect(t, ecs.hierarchy_pool_contains(&pool, h(ecs.Thing_Idx(idx))))
	testing.expect(t, !ecs.hierarchy_pool_contains(&pool, h(8)))

	testing.expect_value(t, ecs.hierarchy_pool_parent(&pool, h(1)), ecs.THING_NIL)
	testing.expect_value(t, ecs.hierarchy_pool_parent(&pool, h(2)), h(1))
	testing.expect_value(t, ecs.hierarchy_pool_parent(&pool, h(5)), h(2))
	testing.expect_value(t, ecs.hierarchy_pool_first_child(&pool, h(1)), h(2))
	testing.expect_value(t, ecs.hierarchy_pool_first_child(&pool, h(3)), ecs.THING_NIL)
	testing.expect_value(t, ecs.hierarchy_pool_next_sibling(&pool, h(2)), h(3))
	testing.expect_value(t, ecs.hierarchy_pool_next_sibling(&pool, h(3)), ecs.THING_NIL)
	testing.expect_value(t, ecs.hierarchy_pool_next_sibling(&pool, h(1)), h(6))
	testing.expect_value(t, ecs.hierarchy_pool_next_sibling(&pool, h(6)), ecs.THING_NIL)

	hierarchy_expect_roots(t, &pool, {1, 6})
	hierarchy_expect_children(t, &pool, h(1), {2, 3})
	hierarchy_expect_children(t, &pool, h(2), {4, 5})
	hierarchy_expect_children(t, &pool, h(4), {})
}

@(test)
hierarchy_pool_attach_moves_subtree :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	h := hierarchy_thing
	hierarchy_build(&pool)
	ecs.hierarchy_pool_attach(&pool, h(2), h(7))
	ecs.hierarchy_pool_rebuild(&pool)

	testing.expect_value(t, ecs.hierarchy_pool_count(&pool), 7)
	hierarchy_expect_children(t, &pool, h(1), {3})
	hierarchy_expect_children(t, &pool, h(7), {2})
	hierarchy_expect_order(t, &pool, {1, 3, 6, 7, 2, 4, 5})
	hierarchy_expect_depths(t, &pool, {0, 1, 0, 1, 2, 3, 3})
}

@(test)
hierarchy_pool_attach_root_under_other_tree :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	h := hierarchy_thing
	hierarchy_build(&pool)
	ecs.hierarchy_pool_attach(&pool, h(1), h(7))
	ecs.hierarchy_pool_rebuild(&pool)

	hierarchy_expect_roots(t, &pool, {6})
	hierarchy_expect_order(t, &pool, {6, 7, 1, 2, 4, 5, 3})
	hierarchy_expect_depths(t, &pool, {0, 1, 2, 3, 4, 4, 3})
}

@(test)
hierarchy_pool_attach_to_same_parent_keeps_place :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	h := hierarchy_thing
	hierarchy_build(&pool)
	ecs.hierarchy_pool_rebuild(&pool)

	ecs.hierarchy_pool_attach(&pool, h(2), h(1))

	testing.expect(t, !ecs.hierarchy_pool_is_dirty(&pool))
	hierarchy_expect_children(t, &pool, h(1), {2, 3})
}

// >--------------------------------------------------------------------- Detach

@(test)
hierarchy_pool_detach_unlinks_any_sibling :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	h := hierarchy_thing
	for idx in 2 ..= 5 do ecs.hierarchy_pool_attach(&pool, h(ecs.Thing_Idx(idx)), h(1))

	// Middle, first, last, then only child.
	testing.expect(t, ecs.hierarchy_pool_detach(&pool, h(3)))
	hierarchy_expect_children(t, &pool, h(1), {2, 4, 5})

	testing.expect(t, ecs.hierarchy_pool_detach(&pool, h(2)))
	hierarchy_expect_children(t, &pool, h(1), {4, 5})
	testing.expect_value(t, ecs.hierarchy_pool_first_child(&pool, h(1)), h(4))

	testing.expect(t, ecs.hierarchy_pool_detach(&pool, h(5)))
	hierarchy_expect_children(t, &pool, h(1), {4})
	testing.expect_value(t, ecs.hierarchy_pool_next_sibling(&pool, h(4)), ecs.THING_NIL)

	testing.expect(t, ecs.hierarchy_pool_detach(&pool, h(4)))
	hierarchy_expect_children(t, &pool, h(1), {})
	testing.expect_value(t, ecs.hierarchy_pool_first_child(&pool, h(1)), ecs.THING_NIL)

	// Detached things stay in the hierarchy as roots, in detach order.
	testing.expect_value(t, ecs.hierarchy_pool_count(&pool), 5)
	hierarchy_expect_roots(t, &pool, {1, 3, 2, 5, 4})
	for idx in 2 ..= 5 do testing.expect_value(t, ecs.hierarchy_pool_parent(&pool, h(ecs.Thing_Idx(idx))), ecs.THING_NIL)
}

@(test)
hierarchy_pool_detach_keeps_subtree :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	h := hierarchy_thing
	hierarchy_build(&pool)
	testing.expect(t, ecs.hierarchy_pool_detach(&pool, h(2)))
	ecs.hierarchy_pool_rebuild(&pool)

	hierarchy_expect_roots(t, &pool, {1, 6, 2})
	hierarchy_expect_order(t, &pool, {1, 3, 6, 7, 2, 4, 5})
	hierarchy_expect_depths(t, &pool, {0, 1, 0, 1, 0, 1, 1})
}

@(test)
hierarchy_pool_detach_root_or_missing_returns_false :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	h := hierarchy_thing
	hierarchy_build(&pool)
	ecs.hierarchy_pool_rebuild(&pool)

	testing.expect(t, !ecs.hierarchy_pool_detach(&pool, h(1)))
	testing.expect(t, !ecs.hierarchy_pool_detach(&pool, h(9)))
	testing.expect(t, !ecs.hierarchy_pool_is_dirty(&pool))
	hierarchy_expect_roots(t, &pool, {1, 6})
}

// >--------------------------------------------------------------------- Remove

@(test)
hierarchy_pool_remove_makes_children_roots :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	h := hierarchy_thing
	hierarchy_build(&pool)
	ecs.hierarchy_pool_attach(&pool, h(8), h(4))
	ecs.hierarchy_pool_rebuild(&pool)

	testing.expect(t, ecs.hierarchy_pool_remove(&pool, h(2)))
	ecs.hierarchy_pool_rebuild(&pool)

	testing.expect_value(t, ecs.hierarchy_pool_count(&pool), 7)
	testing.expect(t, !ecs.hierarchy_pool_contains(&pool, h(2)))
	testing.expect_value(t, ecs.hierarchy_pool_parent(&pool, h(2)), ecs.THING_NIL)
	testing.expect_value(t, ecs.hierarchy_pool_first_child(&pool, h(2)), ecs.THING_NIL)
	testing.expect(t, ecs.hierarchy_pool_subtree(&pool, h(2)) == nil)

	hierarchy_expect_roots(t, &pool, {1, 6, 4, 5})
	hierarchy_expect_children(t, &pool, h(1), {3})
	hierarchy_expect_order(t, &pool, {1, 3, 6, 7, 4, 8, 5})
	hierarchy_expect_depths(t, &pool, {0, 1, 0, 1, 0, 1, 0})
}

@(test)
hierarchy_pool_remove_root_and_leaf :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	h := hierarchy_thing
	hierarchy_build(&pool)

	testing.expect(t, ecs.hierarchy_pool_remove(&pool, h(1)))
	testing.expect(t, ecs.hierarchy_pool_remove(&pool, h(7)))
	ecs.hierarchy_pool_rebuild(&pool)

	testing.expect_value(t, ecs.hierarchy_pool_count(&pool), 5)
	hierarchy_expect_roots(t, &pool, {6, 2, 3})
	hierarchy_expect_children(t, &pool, h(6), {})
	hierarchy_expect_order(t, &pool, {6, 2, 4, 5, 3})
}

@(test)
hierarchy_pool_remove_missing_returns_false :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	h := hierarchy_thing
	hierarchy_build(&pool)
	ecs.hierarchy_pool_rebuild(&pool)

	testing.expect(t, !ecs.hierarchy_pool_remove(&pool, h(9)))
	testing.expect(t, !ecs.hierarchy_pool_is_dirty(&pool))
	testing.expect_value(t, ecs.hierarchy_pool_count(&pool), 7)
}

// >-------------------------------------------------------------------- Rebuild

@(test)
hierarchy_pool_rebuild_flattens_in_pre_order :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	hierarchy_build(&pool)
	ecs.hierarchy_pool_rebuild(&pool)

	testing.expect(t, !ecs.hierarchy_pool_is_dirty(&pool))
	hierarchy_expect_order(t, &pool, {1, 2, 4, 5, 3, 6, 7})
	hierarchy_expect_depths(t, &pool, {0, 1, 2, 2, 1, 0, 1})

	expected_ends := []ecs.Hierarchy_Pos{5, 4, 3, 4, 5, 7, 7}
	ends := ecs.hierarchy_pool_ends(&pool)
	if testing.expect_value(t, len(ends), len(expected_ends)) {
		for end, i in ends do testing.expect_value(t, end, expected_ends[i])
	}
}

@(test)
hierarchy_pool_order_is_stale_until_rebuild :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	h := hierarchy_thing
	hierarchy_build(&pool)
	ecs.hierarchy_pool_rebuild(&pool)

	ecs.hierarchy_pool_attach(&pool, h(8), h(3))
	ecs.hierarchy_pool_remove(&pool, h(7))

	testing.expect(t, ecs.hierarchy_pool_is_dirty(&pool))
	hierarchy_expect_order(t, &pool, {1, 2, 4, 5, 3, 6, 7})
	testing.expect_value(t, len(ecs.hierarchy_pool_subtree(&pool, h(7))), 1)

	ecs.hierarchy_pool_rebuild(&pool)

	testing.expect(t, !ecs.hierarchy_pool_is_dirty(&pool))
	hierarchy_expect_order(t, &pool, {1, 2, 4, 5, 3, 8, 6})
	testing.expect(t, ecs.hierarchy_pool_subtree(&pool, h(7)) == nil)
}

@(test)
hierarchy_pool_rebuild_forgets_things_past_shrunk_order :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	h := hierarchy_thing
	hierarchy_build(&pool)
	ecs.hierarchy_pool_rebuild(&pool)

	// 6 and 7 sat at the end of the order, which the next rebuild doesn't reach anymore.
	ecs.hierarchy_pool_remove(&pool, h(7))
	ecs.hierarchy_pool_remove(&pool, h(6))
	ecs.hierarchy_pool_rebuild(&pool)

	hierarchy_expect_order(t, &pool, {1, 2, 4, 5, 3})
	testing.expect(t, ecs.hierarchy_pool_subtree(&pool, h(6)) == nil)
	testing.expect(t, ecs.hierarchy_pool_subtree(&pool, h(7)) == nil)
	testing.expect(t, !ecs.hierarchy_pool_is_ancestor(&pool, h(6), h(7)))
}

@(test)
hierarchy_pool_rebuild_reaches_max_depth :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, 1 << 17)
	defer ecs.hierarchy_pool_destroy(&pool)

	hierarchy_build_chain(&pool, ecs.HIERARCHY_MAX_DEPTH + 1)
	ecs.hierarchy_pool_rebuild(&pool)

	depths := ecs.hierarchy_pool_depths(&pool)
	if testing.expect_value(t, len(depths), ecs.HIERARCHY_MAX_DEPTH + 1) {
		testing.expect_value(t, int(depths[len(depths) - 1]), ecs.HIERARCHY_MAX_DEPTH)
	}
}

@(test)
hierarchy_pool_order_keeps_gens :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	parent := ecs.thing_make(1, 3)
	child := ecs.thing_make(2, 4095)
	ecs.hierarchy_pool_attach(&pool, child, parent)
	ecs.hierarchy_pool_rebuild(&pool)

	order := ecs.hierarchy_pool_order(&pool)
	if testing.expect_value(t, len(order), 2) {
		testing.expect_value(t, order[0], parent)
		testing.expect_value(t, order[1], child)
	}
	testing.expect_value(t, ecs.hierarchy_pool_parent(&pool, child), parent)
	testing.expect_value(t, ecs.hierarchy_pool_first_child(&pool, parent), child)

	// The same idx with another gen isn't the thing in the hierarchy.
	stale := ecs.thing_make(2, 0)
	testing.expect(t, !ecs.hierarchy_pool_contains(&pool, stale))
	testing.expect(t, ecs.hierarchy_pool_subtree(&pool, stale) == nil)
	testing.expect(t, !ecs.hierarchy_pool_is_ancestor(&pool, parent, stale))
}

@(test)
hierarchy_pool_subtree_is_contiguous :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	h := hierarchy_thing
	hierarchy_build(&pool)
	ecs.hierarchy_pool_rebuild(&pool)

	Case :: struct {
		thing: ecs.Thing_Idx,
		idxs:  []ecs.Thing_Idx,
	}

	cases := []Case{{1, {1, 2, 4, 5, 3}}, {2, {2, 4, 5}}, {5, {5}}, {6, {6, 7}}, {7, {7}}}

	for c in cases {
		subtree := ecs.hierarchy_pool_subtree(&pool, h(c.thing))
		if !testing.expect_value(t, len(subtree), len(c.idxs)) do continue
		for thing, i in subtree do testing.expect_value(t, thing.idx, c.idxs[i])
	}

	testing.expect(t, ecs.hierarchy_pool_subtree(&pool, h(9)) == nil)
}

@(test)
hierarchy_pool_is_ancestor_checks_strict_ancestry :: proc(t: ^testing.T) {
	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	h := hierarchy_thing
	hierarchy_build(&pool)
	ecs.hierarchy_pool_rebuild(&pool)

	testing.expect(t, ecs.hierarchy_pool_is_ancestor(&pool, h(1), h(2)))
	testing.expect(t, ecs.hierarchy_pool_is_ancestor(&pool, h(1), h(5)))
	testing.expect(t, ecs.hierarchy_pool_is_ancestor(&pool, h(1), h(3)))
	testing.expect(t, ecs.hierarchy_pool_is_ancestor(&pool, h(6), h(7)))

	testing.expect(t, !ecs.hierarchy_pool_is_ancestor(&pool, h(2), h(2)))
	testing.expect(t, !ecs.hierarchy_pool_is_ancestor(&pool, h(5), h(1)))
	testing.expect(t, !ecs.hierarchy_pool_is_ancestor(&pool, h(2), h(3)))
	testing.expect(t, !ecs.hierarchy_pool_is_ancestor(&pool, h(4), h(5)))
	testing.expect(t, !ecs.hierarchy_pool_is_ancestor(&pool, h(1), h(7)))
	testing.expect(t, !ecs.hierarchy_pool_is_ancestor(&pool, h(1), h(9)))
}

// >-------------------------------------------------------------------- Asserts

@(test)
hierarchy_pool_attach_to_self_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pool from the stack instead of the heap.
	backing: [8 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY, mem.arena_allocator(&arena))
	hierarchy_build(&pool)

	testing.expect_assert_message(t, "Hierarchy thing 2 can't be attached to itself.")
	ecs.hierarchy_pool_attach(&pool, hierarchy_thing(2), hierarchy_thing(2))
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_pool_attach_to_descendant_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pool from the stack instead of the heap.
	backing: [8 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY, mem.arena_allocator(&arena))
	hierarchy_build(&pool)

	testing.expect_assert_message(t, "Hierarchy thing 1 can't be attached to its descendant 4.")
	ecs.hierarchy_pool_attach(&pool, hierarchy_thing(1), hierarchy_thing(4))
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_pool_stale_thing_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pool from the stack instead of the heap.
	backing: [8 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY, mem.arena_allocator(&arena))
	hierarchy_build(&pool)

	testing.expect_assert_message(t, "Hierarchy thing 2 has gen 1, the hierarchy holds gen 0.")
	ecs.hierarchy_pool_detach(&pool, ecs.thing_make(2, 1))
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_pool_nil_thing_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pool from the stack instead of the heap.
	backing: [8 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY, mem.arena_allocator(&arena))

	testing.expect_assert_message(t, "Hierarchy thing can't be THING_NIL.")
	ecs.hierarchy_pool_attach(&pool, hierarchy_thing(1), ecs.THING_NIL)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_pool_thing_out_of_range_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pool from the stack instead of the heap.
	backing: [8 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_POOL_MIN_CAPACITY, mem.arena_allocator(&arena))

	testing.expect_assert_message(t, "Hierarchy thing idx 64 is out of range, the capacity is 64.")
	ecs.hierarchy_pool_parent(&pool, hierarchy_thing(64))
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_pool_init_capacity_too_small_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	pool: ecs.Hierarchy_Pool
	testing.expect_assert_message(
		t,
		"Hierarchy pool capacity has to be between 64 and 1048576, got 8.",
	)
	ecs.hierarchy_pool_init(&pool, 8)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_pool_rebuild_too_deep_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pool from static memory instead of the heap.
	@(static) backing: [4 * mem.Megabyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: ecs.Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, 1 << 17, mem.arena_allocator(&arena))
	hierarchy_build_chain(&pool, ecs.HIERARCHY_MAX_DEPTH + 2)

	testing.expect_assert_message(t, "Hierarchy is deeper than HIERARCHY_MAX_DEPTH (65535).")
	ecs.hierarchy_pool_rebuild(&pool)
	testing.fail_now(t, "The call did not assert.")
}
