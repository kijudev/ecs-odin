package ecs_tests

import "core:testing"

import ecs "../ecs"

Velocity :: struct {
	x, y: f32,
}

World_Part :: enum {
	Position,
	Velocity,
	Tag,
	Target, // shares the Position type
}

World :: ecs.World(World_Part)

@(private = "file")
make_world :: proc(world: ^World) {
	ecs.world_init(world, ecs.THING_POOL_MIN_CAPACITY)
	ecs.world_register_part(world, .Position, Position)
	ecs.world_register_part(world, .Velocity, Velocity, count_destroyed)
	ecs.world_register_part(world, .Tag, Tag)
	ecs.world_register_part(world, .Target, Position)
}

// >------------------------------------------------------------------ Lifecycle

@(test)
world_init_creates_empty_world :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	testing.expect_value(t, ecs.world_count_alive(&world), 0)
	testing.expect_value(t, ecs.world_capacity(&world), ecs.THING_POOL_MIN_CAPACITY)
	testing.expect(t, ecs.world_is_registered(&world, .Position))
	testing.expect_value(t, ecs.world_count(&world, .Position), 0)
}

@(test)
world_destroy_destroys_parts :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	destroyed_count = 0

	vel := Velocity{1, 1}
	ecs.world_set_now(&world, ecs.world_spawn(&world), .Velocity, &vel)
	ecs.world_set_now(&world, ecs.world_spawn(&world), .Velocity, &vel)
	ecs.world_destroy(&world)

	testing.expect_value(t, destroyed_count, 2)
}

@(test)
world_reset_kills_everything_keeps_registrations :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	ecs.world_set_now(&world, thing, .Position, &Position{1, 2})
	ecs.world_reset(&world)

	testing.expect(t, !ecs.world_check(&world, thing))
	testing.expect_value(t, ecs.world_count_alive(&world), 0)
	testing.expect_value(t, ecs.world_count(&world, .Position), 0)
	testing.expect(t, ecs.world_is_registered(&world, .Position))

	// Reused idx must not inherit the old mask.
	again := ecs.world_spawn(&world)
	testing.expect_value(t, again.idx, thing.idx)
	testing.expect(t, !ecs.world_has(&world, again, .Position))
}

// >---------------------------------------------------------------------- Parts

@(test)
world_set_and_get :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	ecs.world_set_now(&world, thing, .Position, &Position{1, 2})

	testing.expect(t, ecs.world_has(&world, thing, .Position))
	testing.expect(t, !ecs.world_has(&world, thing, .Velocity))
	testing.expect_value(t, ecs.world_get(&world, thing, .Position, Position)^, Position{1, 2})
	testing.expect(t, ecs.world_get(&world, thing, .Velocity, Velocity) == nil)
}

@(test)
world_set_overloads :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a := ecs.world_spawn(&world)
	b := ecs.world_spawn(&world)
	c := ecs.world_spawn(&world)
	d := ecs.world_spawn(&world)

	position := Position{3, 4}
	by_value := ecs.world_set_now(&world, a, .Position, Position{1, 2})
	by_pointer := ecs.world_set_now(&world, b, .Position, &position)
	zeroed := ecs.world_set_now(&world, c, .Position, Position)
	from_nil := ecs.world_set_now(&world, d, .Position, (^Position)(nil))

	testing.expect_value(t, by_value^, Position{1, 2})
	testing.expect_value(t, by_pointer^, Position{3, 4})
	testing.expect_value(t, zeroed^, Position{})
	testing.expect_value(t, from_nil^, Position{})
	testing.expect_value(t, ecs.world_count(&world, .Position), 4)
}

@(test)
world_set_existing_overwrites :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	ecs.world_set_now(&world, thing, .Position, Position{1, 2})
	ecs.world_set_now(&world, thing, .Position, Position{3, 4})

	testing.expect_value(t, ecs.world_count(&world, .Position), 1)
	testing.expect_value(t, ecs.world_get(&world, thing, .Position, Position)^, Position{3, 4})
}

@(test)
world_kinds_can_share_a_type :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	ecs.world_set_now(&world, thing, .Position, Position{1, 2})
	ecs.world_set_now(&world, thing, .Target, Position{5, 6})

	testing.expect_value(t, ecs.world_get(&world, thing, .Position, Position)^, Position{1, 2})
	testing.expect_value(t, ecs.world_get(&world, thing, .Target, Position)^, Position{5, 6})

	ecs.world_remove_now(&world, thing, .Target)
	testing.expect(t, ecs.world_has(&world, thing, .Position))
	testing.expect(t, !ecs.world_has(&world, thing, .Target))
}

@(test)
world_remove_part :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	ecs.world_set_now(&world, thing, .Position, &Position{1, 2})
	ecs.world_set_now(&world, thing, .Tag, Tag{})

	testing.expect(t, ecs.world_remove_now(&world, thing, .Position))
	testing.expect(t, !ecs.world_remove_now(&world, thing, .Position))
	testing.expect(t, !ecs.world_has(&world, thing, .Position))
	testing.expect(t, ecs.world_has(&world, thing, .Tag))

	// Killing after a remove must not touch the removed part.
	ecs.world_kill(&world, thing)
	testing.expect_value(t, ecs.world_count(&world, .Tag), 0)
}

@(test)
world_kill_removes_all_parts :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	destroyed_count = 0

	a := ecs.world_spawn(&world)
	b := ecs.world_spawn(&world)
	ecs.world_set_now(&world, a, .Position, &Position{1, 1})
	ecs.world_set_now(&world, a, .Velocity, &Velocity{1, 1})
	ecs.world_set_now(&world, b, .Position, &Position{2, 2})

	testing.expect(t, ecs.world_kill(&world, a))

	testing.expect(t, !ecs.world_check(&world, a))
	testing.expect_value(t, destroyed_count, 1)
	testing.expect_value(t, ecs.world_count(&world, .Position), 1)
	testing.expect_value(t, ecs.world_count(&world, .Velocity), 0)
	testing.expect_value(t, ecs.world_get(&world, b, .Position, Position)^, Position{2, 2})

	// Reused idx starts with no parts.
	c := ecs.world_spawn(&world)
	testing.expect_value(t, c.idx, a.idx)
	testing.expect(t, !ecs.world_has(&world, c, .Position))
	testing.expect(t, !ecs.world_has(&world, c, .Velocity))
}

@(test)
world_kill_fails_for_dead_things :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	old := ecs.world_spawn(&world)
	testing.expect(t, ecs.world_kill(&world, old))
	testing.expect(t, !ecs.world_kill(&world, old))

	// A stale thing must not kill the thing reusing its idx.
	new := ecs.world_spawn(&world)
	ecs.world_set_now(&world, new, .Position, Position{1, 2})
	testing.expect(t, !ecs.world_kill(&world, old))
	testing.expect(t, ecs.world_check(&world, new))
	testing.expect(t, ecs.world_has(&world, new, .Position))

	testing.expect(t, !ecs.world_kill(&world, ecs.THING_NIL))
}

@(test)
world_set_on_dead_thing_returns_nil :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	old := ecs.world_spawn(&world)
	ecs.world_kill(&world, old)
	new := ecs.world_spawn(&world)

	testing.expect(t, ecs.world_set_now(&world, old, .Position, Position{1, 2}) == nil)
	testing.expect(t, ecs.world_set_now(&world, ecs.THING_NIL, .Position, Position) == nil)
	testing.expect(t, !ecs.world_add_now(&world, old, .Tag))
	testing.expect_value(t, ecs.world_count(&world, .Position), 0)
	testing.expect_value(t, ecs.world_count(&world, .Tag), 0)
	testing.expect(t, !ecs.world_has(&world, new, .Position))
}

@(test)
world_add_inserts_zeroed_part :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	testing.expect(t, ecs.world_add_now(&world, thing, .Tag))
	testing.expect(t, ecs.world_has(&world, thing, .Tag))

	ecs.world_set_now(&world, thing, .Position, Position{1, 2})
	testing.expect(t, ecs.world_add_now(&world, thing, .Position))
	testing.expect_value(t, ecs.world_get(&world, thing, .Position, Position)^, Position{})
	testing.expect_value(t, ecs.world_count(&world, .Position), 1)

	// Killing removes added parts like any other.
	ecs.world_kill(&world, thing)
	testing.expect_value(t, ecs.world_count(&world, .Tag), 0)
}

// >--------------------------------------------------------------------- Slices

@(test)
world_slices_match_up :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	spawned: [4]ecs.Thing
	for &thing, i in spawned {
		thing = ecs.world_spawn(&world)
		ecs.world_set_now(&world, thing, .Position, &Position{f32(i), 0})
	}
	ecs.world_kill(&world, spawned[1])

	parts := ecs.world_part_slice(&world, .Position, Position)
	things := ecs.world_thing_slice(&world, .Position)

	testing.expect_value(t, len(parts), 3)
	testing.expect_value(t, len(things), 3)
	for thing, i in things {
		testing.expect_value(t, ecs.world_get(&world, thing, .Position, Position)^, parts[i])
	}
}

@(test)
world_tag_slice_has_length :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	ecs.world_set_now(&world, ecs.world_spawn(&world), .Tag, Tag{})
	ecs.world_set_now(&world, ecs.world_spawn(&world), .Tag, Tag{})

	testing.expect_value(t, len(ecs.world_part_slice(&world, .Tag, Tag)), 2)
	testing.expect_value(t, len(ecs.world_thing_slice(&world, .Tag)), 2)
}
