package ecs_tests

import "core:mem"
import "core:testing"

import ecs "../ecs"

// >-------------------------------------------------------------------- Helpers

// Things 1 to 7 with gen 0, so tests can name them by idx.
@(private = "file")
hierarchy_thing :: proc(idx: ecs.Thing_Idx) -> ecs.Thing {
	return ecs.thing_make(idx)
}

// Builds two trees, in pre-order:
// 1, 2, 4, 5, 3
// 6, 7
@(private = "file")
hierarchy_build :: proc(set: ^ecs.Hierarchy_Set) {
	h := hierarchy_thing
	ecs.hierarchy_set_attach(set, h(2), h(1))
	ecs.hierarchy_set_attach(set, h(3), h(1))
	ecs.hierarchy_set_attach(set, h(4), h(2))
	ecs.hierarchy_set_attach(set, h(5), h(2))
	ecs.hierarchy_set_attach(set, h(7), h(6))
}

// Chains things 1 to `count` with `count` as the root, so thing 1 sits at depth `count - 1`.
// Attaching above the root keeps every cycle check O(1).
@(private = "file")
hierarchy_build_chain :: proc(set: ^ecs.Hierarchy_Set, count: int) {
	for idx in 1 ..< count {
		ecs.hierarchy_set_attach(
			set,
			hierarchy_thing(ecs.Thing_Idx(idx)),
			hierarchy_thing(ecs.Thing_Idx(idx + 1)),
		)
	}
}

@(private = "file")
hierarchy_expect_order :: proc(
	t: ^testing.T,
	set: ^ecs.Hierarchy_Set,
	idxs: []ecs.Thing_Idx,
	loc := #caller_location,
) {
	order := ecs.hierarchy_set_order(set)
	if !testing.expect_value(t, len(order), len(idxs), loc) do return

	for thing, i in order do testing.expect_value(t, thing.idx, idxs[i], loc)
}

@(private = "file")
hierarchy_expect_depths :: proc(
	t: ^testing.T,
	set: ^ecs.Hierarchy_Set,
	depths: []ecs.Hierarchy_Depth,
	loc := #caller_location,
) {
	got := ecs.hierarchy_set_depths(set)
	if !testing.expect_value(t, len(got), len(depths), loc) do return

	for depth, i in got do testing.expect_value(t, depth, depths[i], loc)
}

@(private = "file")
hierarchy_expect_children :: proc(
	t: ^testing.T,
	set: ^ecs.Hierarchy_Set,
	parent: ecs.Thing,
	idxs: []ecs.Thing_Idx,
	loc := #caller_location,
) {
	it := ecs.hierarchy_set_iter_children(set, parent)
	hierarchy_expect_iter(t, &it, idxs, loc)
}

@(private = "file")
hierarchy_expect_roots :: proc(
	t: ^testing.T,
	set: ^ecs.Hierarchy_Set,
	idxs: []ecs.Thing_Idx,
	loc := #caller_location,
) {
	it := ecs.hierarchy_set_iter_roots(set)
	hierarchy_expect_iter(t, &it, idxs, loc)
}

@(private = "file")
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
hierarchy_set_init_creates_empty_pool :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	testing.expect_value(t, ecs.hierarchy_set_capacity(&set), ecs.HIERARCHY_SET_MIN_CAPACITY)
	testing.expect_value(t, ecs.hierarchy_set_count(&set), 0)
	testing.expect(t, !ecs.hierarchy_set_is_dirty(&set))
	testing.expect_value(t, len(ecs.hierarchy_set_order(&set)), 0)

	ecs.hierarchy_set_rebuild(&set)
	testing.expect_value(t, len(ecs.hierarchy_set_order(&set)), 0)
}

@(test)
hierarchy_set_destroy_frees_with_init_allocator :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY, mem.tracking_allocator(&track))
	testing.expect(t, len(track.allocation_map) > 0)

	ecs.hierarchy_set_destroy(&set)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
	testing.expect(t, set.nodes == nil)
}

@(test)
hierarchy_set_reset_empties_pool :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)
	ecs.hierarchy_set_rebuild(&set)
	ecs.hierarchy_set_reset(&set)

	testing.expect_value(t, ecs.hierarchy_set_count(&set), 0)
	testing.expect(t, !ecs.hierarchy_set_is_dirty(&set))
	testing.expect_value(t, len(ecs.hierarchy_set_order(&set)), 0)
	testing.expect(t, !ecs.hierarchy_set_contains(&set, h(1)))
	testing.expect(t, ecs.hierarchy_set_subtree(&set, h(1)) == nil)
	hierarchy_expect_roots(t, &set, {})

	// Usable again after reset.
	ecs.hierarchy_set_attach(&set, h(1), h(2))
	ecs.hierarchy_set_rebuild(&set)
	hierarchy_expect_order(t, &set, {2, 1})
}

// >--------------------------------------------------------------------- Attach

@(test)
hierarchy_set_attach_links_things :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)

	testing.expect_value(t, ecs.hierarchy_set_count(&set), 7)
	testing.expect(t, ecs.hierarchy_set_is_dirty(&set))
	for idx in 1 ..= 7 do testing.expect(t, ecs.hierarchy_set_contains(&set, h(ecs.Thing_Idx(idx))))
	testing.expect(t, !ecs.hierarchy_set_contains(&set, h(8)))

	testing.expect_value(t, ecs.hierarchy_set_parent(&set, h(1)), ecs.THING_NIL)
	testing.expect_value(t, ecs.hierarchy_set_parent(&set, h(2)), h(1))
	testing.expect_value(t, ecs.hierarchy_set_parent(&set, h(5)), h(2))
	testing.expect_value(t, ecs.hierarchy_set_first_child(&set, h(1)), h(2))
	testing.expect_value(t, ecs.hierarchy_set_first_child(&set, h(3)), ecs.THING_NIL)
	testing.expect_value(t, ecs.hierarchy_set_next_sibling(&set, h(2)), h(3))
	testing.expect_value(t, ecs.hierarchy_set_next_sibling(&set, h(3)), ecs.THING_NIL)
	testing.expect_value(t, ecs.hierarchy_set_next_sibling(&set, h(1)), h(6))
	testing.expect_value(t, ecs.hierarchy_set_next_sibling(&set, h(6)), ecs.THING_NIL)

	hierarchy_expect_roots(t, &set, {1, 6})
	hierarchy_expect_children(t, &set, h(1), {2, 3})
	hierarchy_expect_children(t, &set, h(2), {4, 5})
	hierarchy_expect_children(t, &set, h(4), {})
}

@(test)
hierarchy_set_attach_moves_subtree :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)
	ecs.hierarchy_set_attach(&set, h(2), h(7))
	ecs.hierarchy_set_rebuild(&set)

	testing.expect_value(t, ecs.hierarchy_set_count(&set), 7)
	hierarchy_expect_children(t, &set, h(1), {3})
	hierarchy_expect_children(t, &set, h(7), {2})
	hierarchy_expect_order(t, &set, {1, 3, 6, 7, 2, 4, 5})
	hierarchy_expect_depths(t, &set, {0, 1, 0, 1, 2, 3, 3})
}

@(test)
hierarchy_set_attach_root_under_other_tree :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)
	ecs.hierarchy_set_attach(&set, h(1), h(7))
	ecs.hierarchy_set_rebuild(&set)

	hierarchy_expect_roots(t, &set, {6})
	hierarchy_expect_order(t, &set, {6, 7, 1, 2, 4, 5, 3})
	hierarchy_expect_depths(t, &set, {0, 1, 2, 3, 4, 4, 3})
}

@(test)
hierarchy_set_attach_prunes_old_root_parent :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)
	ecs.hierarchy_set_attach(&set, h(7), h(3))
	ecs.hierarchy_set_rebuild(&set)

	testing.expect_value(t, ecs.hierarchy_set_count(&set), 6)
	testing.expect(t, !ecs.hierarchy_set_contains(&set, h(6)))
	hierarchy_expect_roots(t, &set, {1})
	hierarchy_expect_order(t, &set, {1, 2, 4, 5, 3, 7})
}

@(test)
hierarchy_set_attach_to_same_parent_keeps_place :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)
	ecs.hierarchy_set_rebuild(&set)

	ecs.hierarchy_set_attach(&set, h(2), h(1))

	testing.expect(t, !ecs.hierarchy_set_is_dirty(&set))
	hierarchy_expect_children(t, &set, h(1), {2, 3})
}

// >--------------------------------------------------------------------- Detach

@(test)
hierarchy_set_detach_unlinks_any_sibling :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	for idx in 2 ..= 5 do ecs.hierarchy_set_attach(&set, h(ecs.Thing_Idx(idx)), h(1))

	// Middle, first, last, then only child.
	testing.expect(t, ecs.hierarchy_set_detach(&set, h(3)))
	hierarchy_expect_children(t, &set, h(1), {2, 4, 5})

	testing.expect(t, ecs.hierarchy_set_detach(&set, h(2)))
	hierarchy_expect_children(t, &set, h(1), {4, 5})
	testing.expect_value(t, ecs.hierarchy_set_first_child(&set, h(1)), h(4))

	testing.expect(t, ecs.hierarchy_set_detach(&set, h(5)))
	hierarchy_expect_children(t, &set, h(1), {4})
	testing.expect_value(t, ecs.hierarchy_set_next_sibling(&set, h(4)), ecs.THING_NIL)

	testing.expect(t, ecs.hierarchy_set_detach(&set, h(4)))
	hierarchy_expect_children(t, &set, h(1), {})
	testing.expect_value(t, ecs.hierarchy_set_first_child(&set, h(1)), ecs.THING_NIL)

	// Detached leaves drop out, and so does 1 once it has no children left.
	testing.expect_value(t, ecs.hierarchy_set_count(&set), 0)
	hierarchy_expect_roots(t, &set, {})
	for idx in 1 ..= 5 do testing.expect(t, !ecs.hierarchy_set_contains(&set, h(ecs.Thing_Idx(idx))))
}

@(test)
hierarchy_set_detach_last_child_prunes_root :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)

	testing.expect(t, ecs.hierarchy_set_detach(&set, h(7)))

	testing.expect_value(t, ecs.hierarchy_set_count(&set), 5)
	testing.expect(t, !ecs.hierarchy_set_contains(&set, h(6)))
	testing.expect(t, !ecs.hierarchy_set_contains(&set, h(7)))
	hierarchy_expect_roots(t, &set, {1})

	// An inner parent left without children stays, it still has a parent.
	testing.expect(t, ecs.hierarchy_set_detach(&set, h(4)))
	testing.expect(t, ecs.hierarchy_set_detach(&set, h(5)))
	testing.expect(t, ecs.hierarchy_set_contains(&set, h(2)))
	hierarchy_expect_children(t, &set, h(1), {2, 3})
	testing.expect_value(t, ecs.hierarchy_set_count(&set), 3)
}

@(test)
hierarchy_set_detach_keeps_subtree :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)
	testing.expect(t, ecs.hierarchy_set_detach(&set, h(2)))
	ecs.hierarchy_set_rebuild(&set)

	hierarchy_expect_roots(t, &set, {1, 6, 2})
	hierarchy_expect_order(t, &set, {1, 3, 6, 7, 2, 4, 5})
	hierarchy_expect_depths(t, &set, {0, 1, 0, 1, 0, 1, 1})
}

@(test)
hierarchy_set_detach_root_or_missing_returns_false :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)
	ecs.hierarchy_set_rebuild(&set)

	testing.expect(t, !ecs.hierarchy_set_detach(&set, h(1)))
	testing.expect(t, !ecs.hierarchy_set_detach(&set, h(9)))
	testing.expect(t, !ecs.hierarchy_set_is_dirty(&set))
	hierarchy_expect_roots(t, &set, {1, 6})
}

// >--------------------------------------------------------------------- Remove

@(test)
hierarchy_set_remove_makes_children_roots :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)
	ecs.hierarchy_set_attach(&set, h(8), h(4))
	ecs.hierarchy_set_rebuild(&set)

	testing.expect(t, ecs.hierarchy_set_remove(&set, h(2)))
	ecs.hierarchy_set_rebuild(&set)

	testing.expect_value(t, ecs.hierarchy_set_count(&set), 6)
	testing.expect(t, !ecs.hierarchy_set_contains(&set, h(2)))
	testing.expect(t, !ecs.hierarchy_set_contains(&set, h(5)))
	testing.expect_value(t, ecs.hierarchy_set_parent(&set, h(2)), ecs.THING_NIL)
	testing.expect_value(t, ecs.hierarchy_set_first_child(&set, h(2)), ecs.THING_NIL)
	testing.expect(t, ecs.hierarchy_set_subtree(&set, h(2)) == nil)

	// 4 still has a child, so it becomes a root. 5 has none, so it drops out.
	hierarchy_expect_roots(t, &set, {1, 6, 4})
	hierarchy_expect_children(t, &set, h(1), {3})
	hierarchy_expect_order(t, &set, {1, 3, 6, 7, 4, 8})
	hierarchy_expect_depths(t, &set, {0, 1, 0, 1, 0, 1})
}

@(test)
hierarchy_set_remove_root_and_leaf :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)

	testing.expect(t, ecs.hierarchy_set_remove(&set, h(1)))
	testing.expect(t, ecs.hierarchy_set_remove(&set, h(7)))
	ecs.hierarchy_set_rebuild(&set)

	// 3 is left without a parent or children, and 6 without children.
	testing.expect_value(t, ecs.hierarchy_set_count(&set), 3)
	hierarchy_expect_roots(t, &set, {2})
	hierarchy_expect_order(t, &set, {2, 4, 5})
	for idx in ([]ecs.Thing_Idx{1, 3, 6, 7}) {
		testing.expect(t, !ecs.hierarchy_set_contains(&set, h(idx)))
	}
}

@(test)
hierarchy_set_remove_missing_returns_false :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)
	ecs.hierarchy_set_rebuild(&set)

	testing.expect(t, !ecs.hierarchy_set_remove(&set, h(9)))
	testing.expect(t, !ecs.hierarchy_set_is_dirty(&set))
	testing.expect_value(t, ecs.hierarchy_set_count(&set), 7)
}

// >------------------------------------------------------------------ Link Walks

@(test)
hierarchy_set_can_attach_rejects_cycles :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)

	testing.expect(t, ecs.hierarchy_set_can_attach(&set, h(2), h(1)))
	testing.expect(t, ecs.hierarchy_set_can_attach(&set, h(7), h(4)))
	testing.expect(t, ecs.hierarchy_set_can_attach(&set, h(1), h(7)))
	testing.expect(t, ecs.hierarchy_set_can_attach(&set, h(9), h(1)))
	testing.expect(t, ecs.hierarchy_set_can_attach(&set, h(1), h(9)))

	testing.expect(t, !ecs.hierarchy_set_can_attach(&set, h(2), h(2)))
	testing.expect(t, !ecs.hierarchy_set_can_attach(&set, h(1), h(2)))
	testing.expect(t, !ecs.hierarchy_set_can_attach(&set, h(1), h(5)))
	testing.expect(t, !ecs.hierarchy_set_can_attach(&set, h(6), h(7)))
}

@(test)
hierarchy_set_collect_subtree_walks_links :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)

	// No rebuild needed, it reads the links.
	ecs.hierarchy_set_attach(&set, h(6), h(3))

	Case :: struct {
		thing: ecs.Thing_Idx,
		idxs:  []ecs.Thing_Idx,
	}

	cases := []Case{{1, {1, 2, 4, 5, 3, 6, 7}}, {2, {2, 4, 5}}, {3, {3, 6, 7}}, {7, {7}}, {9, {9}}}

	buffer: [8]ecs.Thing
	for c in cases {
		subtree := ecs.hierarchy_set_collect_subtree(&set, h(c.thing), buffer[:])
		if !testing.expect_value(t, len(subtree), len(c.idxs)) do continue
		for thing, i in subtree do testing.expect_value(t, thing.idx, c.idxs[i])
	}
}

// >-------------------------------------------------------------------- Rebuild

@(test)
hierarchy_set_rebuild_flattens_in_pre_order :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	hierarchy_build(&set)
	ecs.hierarchy_set_rebuild(&set)

	testing.expect(t, !ecs.hierarchy_set_is_dirty(&set))
	hierarchy_expect_order(t, &set, {1, 2, 4, 5, 3, 6, 7})
	hierarchy_expect_depths(t, &set, {0, 1, 2, 2, 1, 0, 1})

	expected_ends := []ecs.Hierarchy_Pos{5, 4, 3, 4, 5, 7, 7}
	ends := ecs.hierarchy_set_ends(&set)
	if testing.expect_value(t, len(ends), len(expected_ends)) {
		for end, i in ends do testing.expect_value(t, end, expected_ends[i])
	}
}

@(test)
hierarchy_set_order_is_stale_until_rebuild :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)
	ecs.hierarchy_set_rebuild(&set)

	ecs.hierarchy_set_attach(&set, h(8), h(3))
	ecs.hierarchy_set_remove(&set, h(7))

	testing.expect(t, ecs.hierarchy_set_is_dirty(&set))
	hierarchy_expect_order(t, &set, {1, 2, 4, 5, 3, 6, 7})
	testing.expect_value(t, len(ecs.hierarchy_set_subtree(&set, h(7))), 1)

	ecs.hierarchy_set_rebuild(&set)

	testing.expect(t, !ecs.hierarchy_set_is_dirty(&set))
	hierarchy_expect_order(t, &set, {1, 2, 4, 5, 3, 8})
	testing.expect(t, ecs.hierarchy_set_subtree(&set, h(6)) == nil)
	testing.expect(t, ecs.hierarchy_set_subtree(&set, h(7)) == nil)
}

@(test)
hierarchy_set_rebuild_forgets_things_past_shrunk_order :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)
	ecs.hierarchy_set_rebuild(&set)

	// Removing 7 drops 6 too. Both sat at the end of the order, which the next rebuild doesn't
	// reach anymore.
	ecs.hierarchy_set_remove(&set, h(7))
	ecs.hierarchy_set_rebuild(&set)

	hierarchy_expect_order(t, &set, {1, 2, 4, 5, 3})
	testing.expect(t, ecs.hierarchy_set_subtree(&set, h(6)) == nil)
	testing.expect(t, ecs.hierarchy_set_subtree(&set, h(7)) == nil)
	testing.expect(t, !ecs.hierarchy_set_is_ancestor(&set, h(6), h(7)))
}

@(test)
hierarchy_set_rebuild_reaches_max_depth :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, 1 << 17)
	defer ecs.hierarchy_set_destroy(&set)

	hierarchy_build_chain(&set, ecs.HIERARCHY_MAX_DEPTH + 1)
	ecs.hierarchy_set_rebuild(&set)

	depths := ecs.hierarchy_set_depths(&set)
	if testing.expect_value(t, len(depths), ecs.HIERARCHY_MAX_DEPTH + 1) {
		testing.expect_value(t, int(depths[len(depths) - 1]), ecs.HIERARCHY_MAX_DEPTH)
	}
}

@(test)
hierarchy_set_order_keeps_gens :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	parent := ecs.thing_make(1, 3)
	child := ecs.thing_make(2, 4095)
	ecs.hierarchy_set_attach(&set, child, parent)
	ecs.hierarchy_set_rebuild(&set)

	order := ecs.hierarchy_set_order(&set)
	if testing.expect_value(t, len(order), 2) {
		testing.expect_value(t, order[0], parent)
		testing.expect_value(t, order[1], child)
	}
	testing.expect_value(t, ecs.hierarchy_set_parent(&set, child), parent)
	testing.expect_value(t, ecs.hierarchy_set_first_child(&set, parent), child)

	// The same idx with another gen isn't the thing in the hierarchy.
	stale := ecs.thing_make(2, 0)
	testing.expect(t, !ecs.hierarchy_set_contains(&set, stale))
	testing.expect(t, ecs.hierarchy_set_subtree(&set, stale) == nil)
	testing.expect(t, !ecs.hierarchy_set_is_ancestor(&set, parent, stale))
}

@(test)
hierarchy_set_subtree_is_contiguous :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)
	ecs.hierarchy_set_rebuild(&set)

	Case :: struct {
		thing: ecs.Thing_Idx,
		idxs:  []ecs.Thing_Idx,
	}

	cases := []Case{{1, {1, 2, 4, 5, 3}}, {2, {2, 4, 5}}, {5, {5}}, {6, {6, 7}}, {7, {7}}}

	for c in cases {
		subtree := ecs.hierarchy_set_subtree(&set, h(c.thing))
		if !testing.expect_value(t, len(subtree), len(c.idxs)) do continue
		for thing, i in subtree do testing.expect_value(t, thing.idx, c.idxs[i])
	}

	testing.expect(t, ecs.hierarchy_set_subtree(&set, h(9)) == nil)
}

@(test)
hierarchy_set_is_ancestor_checks_strict_ancestry :: proc(t: ^testing.T) {
	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_set_destroy(&set)

	h := hierarchy_thing
	hierarchy_build(&set)
	ecs.hierarchy_set_rebuild(&set)

	testing.expect(t, ecs.hierarchy_set_is_ancestor(&set, h(1), h(2)))
	testing.expect(t, ecs.hierarchy_set_is_ancestor(&set, h(1), h(5)))
	testing.expect(t, ecs.hierarchy_set_is_ancestor(&set, h(1), h(3)))
	testing.expect(t, ecs.hierarchy_set_is_ancestor(&set, h(6), h(7)))

	testing.expect(t, !ecs.hierarchy_set_is_ancestor(&set, h(2), h(2)))
	testing.expect(t, !ecs.hierarchy_set_is_ancestor(&set, h(5), h(1)))
	testing.expect(t, !ecs.hierarchy_set_is_ancestor(&set, h(2), h(3)))
	testing.expect(t, !ecs.hierarchy_set_is_ancestor(&set, h(4), h(5)))
	testing.expect(t, !ecs.hierarchy_set_is_ancestor(&set, h(1), h(7)))
	testing.expect(t, !ecs.hierarchy_set_is_ancestor(&set, h(1), h(9)))
}

// >-------------------------------------------------------------------- Asserts

@(test)
hierarchy_set_attach_to_self_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the set from the stack instead of the heap.
	backing: [8 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY, mem.arena_allocator(&arena))
	hierarchy_build(&set)

	testing.expect_assert_message(t, "Hierarchy thing 2 can't be attached to itself.")
	ecs.hierarchy_set_attach(&set, hierarchy_thing(2), hierarchy_thing(2))
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_set_attach_to_descendant_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the set from the stack instead of the heap.
	backing: [8 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY, mem.arena_allocator(&arena))
	hierarchy_build(&set)

	testing.expect_assert_message(t, "Hierarchy thing 1 can't be attached to its descendant 4.")
	ecs.hierarchy_set_attach(&set, hierarchy_thing(1), hierarchy_thing(4))
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_set_stale_thing_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the set from the stack instead of the heap.
	backing: [8 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY, mem.arena_allocator(&arena))
	hierarchy_build(&set)

	testing.expect_assert_message(t, "Hierarchy thing 2 has gen 1, the hierarchy holds gen 0.")
	ecs.hierarchy_set_detach(&set, ecs.thing_make(2, 1))
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_set_nil_thing_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the set from the stack instead of the heap.
	backing: [8 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY, mem.arena_allocator(&arena))

	testing.expect_assert_message(t, "Hierarchy thing can't be THING_NIL.")
	ecs.hierarchy_set_attach(&set, hierarchy_thing(1), ecs.THING_NIL)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_set_thing_out_of_range_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the set from the stack instead of the heap.
	backing: [8 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY, mem.arena_allocator(&arena))

	testing.expect_assert_message(t, "Hierarchy thing idx 64 is out of range, the capacity is 64.")
	ecs.hierarchy_set_parent(&set, hierarchy_thing(64))
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_set_init_capacity_too_small_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	set: ecs.Hierarchy_Set
	testing.expect_assert_message(
		t,
		"Hierarchy set capacity has to be between 64 and 1048576, got 8.",
	)
	ecs.hierarchy_set_init(&set, 8)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_set_rebuild_too_deep_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the set from static memory instead of the heap.
	@(static) backing: [4 * mem.Megabyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, 1 << 17, mem.arena_allocator(&arena))
	hierarchy_build_chain(&set, ecs.HIERARCHY_MAX_DEPTH + 2)

	testing.expect_assert_message(t, "Hierarchy is deeper than HIERARCHY_MAX_DEPTH (65535).")
	ecs.hierarchy_set_rebuild(&set)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_set_collect_subtree_too_small_buffer_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the set from the stack instead of the heap.
	backing: [8 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	set: ecs.Hierarchy_Set
	ecs.hierarchy_set_init(&set, ecs.HIERARCHY_SET_MIN_CAPACITY, mem.arena_allocator(&arena))
	hierarchy_build(&set)

	buffer: [2]ecs.Thing
	testing.expect_assert_message(t, "Subtree of thing 2 doesn't fit in the buffer.")
	ecs.hierarchy_set_collect_subtree(&set, hierarchy_thing(2), buffer[:])
	testing.fail_now(t, "The call did not assert.")
}
