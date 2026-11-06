package ecs_tests

import "core:mem"
import "core:testing"

import ecs "../ecs"

Query :: ecs.Query(Part, Resource, Stage)

// Health is left unregistered on purpose.
@(private = "file")
make_world :: proc(world: ^World, allocator := context.allocator) {
	ecs.world_init(world, ecs.THING_POOL_MIN_CAPACITY, 64, allocator)
	ecs.register(world, .Position, Position)
	ecs.register(world, .Velocity, Velocity)
	ecs.register(world, .Tag, Tag)
	ecs.register(world, .Target, Position)
}

@(private = "file")
collect :: proc(query: ^Query) -> (things: [dynamic; 16]ecs.Thing) {
	for ecs.query_next(query) do append(&things, query.thing)
	return
}

@(private = "file")
contains :: proc(things: []ecs.Thing, thing: ecs.Thing) -> bool {
	for th in things do if th == thing do return true
	return false
}

// >---------------------------------------------------------------- Iteration

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

	// Position comes first in Part, so picking it means the sizes were ignored.
	query := ecs.query_make(ecs.stuff_make(&world), {.Position, .Velocity}, {})
	testing.expect_value(t, query.first_kind, Part.Velocity)

	things := collect(&query)
	testing.expect_value(t, len(things), 1)
	testing.expect(t, contains(things[:], only))
}

@(test)
query_next_clears_thing_when_done :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.spawn(&world)
	ecs.set_now(&world, thing, .Position, Position{})

	query := ecs.query_make(ecs.stuff_make(&world), {.Position}, {})
	testing.expect(t, ecs.query_next(&query))
	testing.expect_value(t, query.thing, thing)
	testing.expect(t, !ecs.query_next(&query))
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
	testing.expect_value(t, query.first_kind, Part.Position)

	ecs.query_refresh(&query)
	testing.expect_value(t, query.first_kind, Part.Position)
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
	testing.expect_value(t, query.first_kind, Part.Velocity)
	things := collect(&query)
	testing.expect_value(t, len(things), 2)
	testing.expect(t, contains(things[:], a))
	testing.expect(t, contains(things[:], b))
}

// >------------------------------------------------------------ Current Thing

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
	for ecs.query_next(&query) {
		pos := ecs.get_part(&query, .Position, Position)
		testing.expect(t, pos == ecs.world_get_part(&world, query.thing, .Position, Position))

		if query.thing == a {
			testing.expect_value(t, pos^, Position{1, 2})
			testing.expect(t, ecs.has(&query, .Tag))
		} else {
			testing.expect_value(t, pos^, Position{3, 4})
			testing.expect(t, !ecs.has(&query, .Tag))
		}
	}
}

// >------------------------------------------------------------------- Misuse

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
