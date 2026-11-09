package ecs_tests

import "core:fmt"
import "core:mem"
import "core:testing"

import ecs "../ecs"

Query :: ecs.Query(Kind, Stage)

// Health is left unregistered on purpose.
@(private = "file")
make_world :: proc(world: ^World, allocator := context.allocator) {
	ecs.world_init(
		world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = allocator,
			dynamic_allocator = allocator,
		},
	)
	ecs.register_part(world, .Position, Position)
	ecs.register_part(world, .Velocity, Velocity)
	ecs.register_part(world, .Tag, Tag)
	ecs.register_part(world, .Target, Position)
	ecs.register_hierarchy(world, .Transform)
}

@(private = "file")
collect :: proc(query: ^Query) -> (things: [dynamic; 16]ecs.Thing) {
	for thing in ecs.query_iter(query) {
		assert(thing == query.thing, "The loop thing is the current thing.")
		append(&things, thing)
	}
	return
}

@(private = "file")
contains :: proc(things: []ecs.Thing, thing: ecs.Thing) -> bool {
	for th in things do if th == thing do return true
	return false
}

// >------------------------------------------------------------------ Iteration

@(test)
query_yields_things_with_all_and_none_of_without :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	pv := ecs.spawn(&world)
	ecs.set_now(&world, pv, .Position, Position{})
	ecs.set_now(&world, pv, .Velocity, Velocity{})

	p := ecs.spawn(&world)
	ecs.set_now(&world, p, .Position, Position{})

	pvt := ecs.spawn(&world)
	ecs.set_now(&world, pvt, .Position, Position{})
	ecs.set_now(&world, pvt, .Velocity, Velocity{})
	ecs.add_now(&world, pvt, .Tag)

	query := ecs.query_make(ecs.stuff_make(&world), {.Position, .Velocity}, {.Tag})
	things := collect(&query)

	testing.expect_value(t, len(things), 1)
	testing.expect(t, contains(things[:], pv))
}

@(test)
query_without_nothing_yields_every_match :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a := ecs.spawn(&world)
	b := ecs.spawn(&world)
	ecs.set_now(&world, a, .Velocity, Velocity{})
	ecs.set_now(&world, b, .Velocity, Velocity{})

	query := ecs.query_make(ecs.stuff_make(&world), {.Velocity}, {})
	things := collect(&query)

	testing.expect_value(t, len(things), 2)
	testing.expect(t, contains(things[:], a))
	testing.expect(t, contains(things[:], b))
}

@(test)
query_starts_from_the_smallest_set :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	for _ in 0 ..< 4 {
		thing := ecs.spawn(&world)
		ecs.set_now(&world, thing, .Position, Position{})
	}
	only := ecs.spawn(&world)
	ecs.set_now(&world, only, .Position, Position{})
	ecs.set_now(&world, only, .Velocity, Velocity{})

	// Position comes first in Kind, so picking it means the sizes were ignored.
	query := ecs.query_make(ecs.stuff_make(&world), {.Position, .Velocity}, {})
	testing.expect_value(t, query.first, Kind.Velocity)

	things := collect(&query)
	testing.expect_value(t, len(things), 1)
	testing.expect(t, contains(things[:], only))
}

@(test)
query_reads_the_right_part_when_sets_differ_in_order :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	// Velocity goes in reversed, so its dense order is the opposite of Position's.
	things: [8]ecs.Thing
	for &thing, i in things {
		thing = ecs.spawn(&world)
		ecs.set_now(&world, thing, .Position, Position{f32(i), 0})
	}
	#reverse for thing, i in things do ecs.set_now(&world, thing, .Velocity, Velocity{f32(i) + 100, 0})

	visited := 0
	query := ecs.query_make(ecs.stuff_make(&world), {.Position, .Velocity}, {})
	for _ in ecs.query_iter(&query) {
		pos := ecs.get_part(&query, .Position, Position)
		vel := ecs.get_part(&query, .Velocity, Velocity)
		testing.expect_value(t, vel.x, pos.x + 100)
		testing.expect_value(t, ecs.write_part(&query, .Velocity, Velocity).x, pos.x + 100)
		visited += 1
	}
	testing.expect_value(t, visited, len(things))
}

@(test)
query_iter_clears_thing_when_done :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.spawn(&world)
	ecs.set_now(&world, thing, .Position, Position{})

	query := ecs.query_make(ecs.stuff_make(&world), {.Position}, {})
	got, ok := ecs.query_iter(&query)
	testing.expect(t, ok)
	testing.expect_value(t, got, thing)
	testing.expect_value(t, query.thing, thing)

	got, ok = ecs.query_iter(&query)
	testing.expect(t, !ok)
	testing.expect_value(t, got, ecs.THING_NIL)
	testing.expect_value(t, query.thing, ecs.THING_NIL)
}

@(test)
query_refresh_starts_over :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a := ecs.spawn(&world)
	ecs.set_now(&world, a, .Position, Position{})
	ecs.set_now(&world, a, .Velocity, Velocity{})

	query := ecs.query_make(ecs.stuff_make(&world), {.Position, .Velocity}, {})
	testing.expect_value(t, len(collect(&query)), 1)
	testing.expect_value(t, len(collect(&query)), 0)

	// Velocity grows past Position, so the refreshed query has to switch sets.
	for _ in 0 ..< 3 {
		thing := ecs.spawn(&world)
		ecs.set_now(&world, thing, .Velocity, Velocity{})
	}
	testing.expect_value(t, query.first, Kind.Position)

	ecs.query_refresh(&query)
	testing.expect_value(t, query.first, Kind.Position)
	testing.expect_value(t, query.thing, ecs.THING_NIL)
	testing.expect_value(t, len(collect(&query)), 1)

	b := ecs.spawn(&world)
	ecs.set_now(&world, b, .Position, Position{})
	ecs.set_now(&world, b, .Velocity, Velocity{})
	for _ in 0 ..< 4 {
		thing := ecs.spawn(&world)
		ecs.set_now(&world, thing, .Position, Position{})
	}

	ecs.query_refresh(&query)
	testing.expect_value(t, query.first, Kind.Velocity)
	things := collect(&query)
	testing.expect_value(t, len(things), 2)
	testing.expect(t, contains(things[:], a))
	testing.expect(t, contains(things[:], b))
}

@(test)
query_single_include_still_excludes :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	kept := ecs.spawn(&world)
	ecs.set_now(&world, kept, .Position, Position{})
	tagged := ecs.spawn(&world)
	ecs.set_now(&world, tagged, .Position, Position{})
	ecs.add_now(&world, tagged, .Tag)

	query := ecs.query_make(ecs.stuff_make(&world), {.Position}, {.Tag})
	things := collect(&query)
	testing.expect_value(t, len(things), 1)
	testing.expect(t, contains(things[:], kept))
}

// >-------------------------------------------------------------- Current Thing

@(test)
query_has_and_get_part_read_the_current_thing :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a := ecs.spawn(&world)
	ecs.set_now(&world, a, .Position, Position{1, 2})
	ecs.add_now(&world, a, .Tag)

	b := ecs.spawn(&world)
	ecs.set_now(&world, b, .Position, Position{3, 4})

	query := ecs.query_make(ecs.stuff_make(&world), {.Position}, {})
	for thing in ecs.query_iter(&query) {
		pos := ecs.write_part(&query, .Position, Position)
		testing.expect(t, pos == ecs.world_write_part(&world, thing, .Position, Position))
		testing.expect_value(t, ecs.get_part(&query, .Position, Position), pos^)

		if query.thing == a {
			testing.expect_value(t, pos^, Position{1, 2})
			testing.expect(t, ecs.has(&query, .Tag))
		} else {
			testing.expect_value(t, pos^, Position{3, 4})
			testing.expect(t, !ecs.has(&query, .Tag))
		}
	}
}

// >------------------------------------------------------------ Hierarchy Query

// Builds, in pre-order, with Position on every thing except b:
//
//   a          e
//   ├─ b       └─ f
//   │  ├─ c
//   │  └─ d
//   └─ g
@(private = "file")
build_tree :: proc(world: ^World) -> (a, b, c, d, e, f, g: ecs.Thing) {
	a, b, c, d = ecs.spawn(world), ecs.spawn(world), ecs.spawn(world), ecs.spawn(world)
	e, f, g = ecs.spawn(world), ecs.spawn(world), ecs.spawn(world)

	ecs.attach_now(world, .Transform, b, a)
	ecs.attach_now(world, .Transform, c, b)
	ecs.attach_now(world, .Transform, d, b)
	ecs.attach_now(world, .Transform, g, a)
	ecs.attach_now(world, .Transform, f, e)

	for thing in ([]ecs.Thing{a, c, d, e, f, g}) {
		ecs.set_now(world, thing, .Position, Position{f32(thing.idx), 0})
	}

	ecs.world_rebuild_hierarchy(world, .Transform)
	return
}

@(private = "file")
expect_collected :: proc(
	t: ^testing.T,
	query: ^ecs.Hierarchy_Query(Kind, Stage),
	want: []ecs.Thing,
	loc := #caller_location,
) {
	got: [dynamic; 16]ecs.Thing
	for thing in ecs.hierarchy_query_iter(query) do append(&got, thing)
	if !testing.expect_value(t, len(got), len(want), loc) do return
	for thing, i in got do testing.expect_value(t, thing, want[i], loc)
}

@(test)
hierarchy_query_walks_pre_order_and_filters :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a, _, c, d, e, f, g := build_tree(&world)
	ecs.add_now(&world, d, .Tag)

	// b has no Position and d is excluded, the children of b are still visited.
	query := ecs.hierarchy_query_make(ecs.stuff_make(&world), .Transform, {.Position}, {.Tag})
	expect_collected(t, &query, {a, c, g, e, f})

	// A thing with the parts but outside the hierarchy is never visited.
	outside := ecs.spawn(&world)
	ecs.set_now(&world, outside, .Position, Position{})
	ecs.hierarchy_query_refresh(&query)
	expect_collected(t, &query, {a, c, g, e, f})
}

@(test)
hierarchy_query_sees_the_last_rebuild :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a, _, c, d, e, f, g := build_tree(&world)

	// Killed since the rebuild: skipped, also once its slot is reused by a thing with the parts.
	ecs.kill_now(&world, c)
	reused := ecs.spawn(&world)
	testing.expect_value(t, reused.idx, c.idx)
	ecs.set_now(&world, reused, .Position, Position{})

	// Attached since the rebuild: not visited yet.
	late := ecs.spawn(&world)
	ecs.set_now(&world, late, .Position, Position{})
	ecs.attach_now(&world, .Transform, late, g)

	query := ecs.hierarchy_query_make(ecs.stuff_make(&world), .Transform, {.Position}, {})
	expect_collected(t, &query, {a, d, g, e, f})

	ecs.world_rebuild_hierarchy(&world, .Transform)
	ecs.hierarchy_query_refresh(&query)
	expect_collected(t, &query, {a, d, g, late, e, f})
}

@(test)
hierarchy_query_reads_parent_and_depth :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a, b, c, d, e, f, g := build_tree(&world)

	visited := 0
	query := ecs.hierarchy_query_make(ecs.stuff_make(&world), .Transform, {.Position}, {})
	for thing in ecs.hierarchy_query_iter(&query) {
		visited += 1
		parent := ecs.get_parent(&query)
		parent_pos, has_parent_pos := ecs.hierarchy_query_get_parent_part(
			&query,
			.Position,
			Position,
		)

		switch thing {
		case a, e:
			testing.expect_value(t, parent, ecs.THING_NIL)
			testing.expect_value(t, ecs.hierarchy_query_get_depth(&query), 0)
			testing.expect(t, !has_parent_pos)
		case c, d:
			// b is the parent but has no Position.
			testing.expect_value(t, parent, b)
			testing.expect_value(t, ecs.hierarchy_query_get_depth(&query), 2)
			testing.expect(t, !has_parent_pos)
		case f, g:
			testing.expect_value(t, parent, thing == f ? e : a)
			testing.expect_value(t, ecs.hierarchy_query_get_depth(&query), 1)
			testing.expect(t, has_parent_pos)
			expect_part(t, &world, parent, .Position, parent_pos)
		case:
			testing.fail_now(t, "Visited a thing outside the tree.")
		}
	}
	testing.expect_value(t, visited, 6)
}

@(test)
hierarchy_query_skips_subtrees :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a, b, _, _, e, _, g := build_tree(&world)
	ecs.set_now(&world, b, .Position, Position{})

	things: [dynamic; 16]ecs.Thing
	query := ecs.hierarchy_query_make(ecs.stuff_make(&world), .Transform, {.Position}, {})

	// A subtree in the middle of the order, and one that runs to its end.
	for thing in ecs.hierarchy_query_iter(&query) {
		append(&things, thing)
		if thing == b || thing == e do ecs.hierarchy_query_skip_subtree(&query)
	}

	want := []ecs.Thing{a, b, g, e}
	if testing.expect_value(t, len(things), len(want)) {
		for thing, i in things do testing.expect_value(t, thing, want[i])
	}
}

// >--------------------------------------------------------------------- Misuse

@(test)
query_with_nothing_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_world(&world, mem.arena_allocator(&arena))

	testing.expect_assert_message(t, "Query needs at least one part to iterate.")
	ecs.query_make(ecs.stuff_make(&world), {}, {.Tag})
	testing.fail_now(t, "The call did not assert.")
}

@(test)
query_conflicting_parts_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_world(&world, mem.arena_allocator(&arena))

	testing.expect_assert_message(
		t,
		"Query has conflicting parts: Velocity is in both include and exclude.",
	)
	ecs.query_make(ecs.stuff_make(&world), {.Position, .Velocity}, {.Velocity, .Tag})
	testing.fail_now(t, "The call did not assert.")
}

@(test)
query_unregistered_part_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_world(&world, mem.arena_allocator(&arena))

	testing.expect_assert_message(t, "Part kind Health is not registered.")
	ecs.query_make(ecs.stuff_make(&world), {.Position, .Health}, {})
	testing.fail_now(t, "The call did not assert.")
}

@(test)
query_get_part_without_current_thing_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_world(&world, mem.arena_allocator(&arena))
	thing := ecs.spawn(&world)
	ecs.set_now(&world, thing, .Position, Position{1, 2})

	// Made but never advanced, so there is no current thing yet.
	query := ecs.query_make(ecs.stuff_make(&world), {.Position}, {})

	testing.expect_assert_message(t, "Query has no current thing to get part Position from.")
	ecs.get_part(&query, .Position, Position)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
query_get_part_missing_on_current_thing_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_world(&world, mem.arena_allocator(&arena))
	thing := ecs.spawn(&world)
	ecs.set_now(&world, thing, .Position, Position{1, 2})

	query := ecs.query_make(ecs.stuff_make(&world), {.Position}, {})
	_, ok := ecs.query_iter(&query)
	testing.expect(t, ok)

	testing.expect_assert_message(
		t,
		fmt.tprintf("Query does not have part Velocity for thing %v.", thing),
	)
	ecs.get_part(&query, .Velocity, Velocity)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_query_unregistered_kind_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_world(&world, mem.arena_allocator(&arena))

	testing.expect_assert_message(t, "Hierarchy kind Inside is not registered.")
	ecs.hierarchy_query_make(ecs.stuff_make(&world), .Inside, {.Position}, {})
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_procs_without_current_thing_assert :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_world(&world, mem.arena_allocator(&arena))

	query := ecs.hierarchy_query_make(ecs.stuff_make(&world), .Transform, {.Position}, {})

	testing.expect_assert_message(t, "Query has no current thing.")
	ecs.hierarchy_query_skip_subtree(&query)
	testing.fail_now(t, "The call did not assert.")
}
