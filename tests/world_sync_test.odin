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

World_Sync :: ecs.World_Sync(World_Part)

@(private = "file")
make_world :: proc(world: ^World_Sync) {
	ecs.world_sync_init(world, ecs.THING_POOL_MIN_CAPACITY)
	ecs.world_sync_register(world, .Position, Position)
	ecs.world_sync_register(world, .Velocity, Velocity, count_destroyed)
	ecs.world_sync_register(world, .Tag, Tag)
	ecs.world_sync_register(world, .Target, Position)
}

// >------------------------------------------------------------------ Lifecycle

@(test)
world_sync_init_creates_empty_world :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	testing.expect_value(t, ecs.world_sync_count_alive(&world), 0)
	testing.expect(t, ecs.world_sync_is_registered(&world, .Position))
	testing.expect_value(t, ecs.world_sync_count_parts(&world, .Position), 0)
}

@(test)
world_sync_destroy_destroys_parts :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	destroyed_count = 0

	vel := Velocity{1, 1}
	ecs.world_sync_set_now(&world, ecs.world_sync_spawn(&world), .Velocity, &vel)
	ecs.world_sync_set_now(&world, ecs.world_sync_spawn(&world), .Velocity, &vel)
	ecs.world_sync_destroy(&world)

	testing.expect_value(t, destroyed_count, 2)
}

@(test)
world_sync_reset_kills_everything_keeps_registrations :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	thing := ecs.world_sync_spawn(&world)
	ecs.world_sync_set_now(&world, thing, .Position, &Position{1, 2})
	ecs.world_sync_reset(&world)

	testing.expect(t, !ecs.world_sync_poke(&world, thing))
	testing.expect_value(t, ecs.world_sync_count_alive(&world), 0)
	testing.expect_value(t, ecs.world_sync_count_parts(&world, .Position), 0)
	testing.expect(t, ecs.world_sync_is_registered(&world, .Position))

	// Reused idx must not inherit the old mask.
	again := ecs.world_sync_spawn(&world)
	testing.expect_value(t, again.idx, thing.idx)
	testing.expect(t, !ecs.world_sync_has(&world, again, .Position))
}

// >---------------------------------------------------------------------- Parts

@(test)
world_sync_set_now_and_get_part :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	thing := ecs.world_sync_spawn(&world)
	ecs.world_sync_set_now(&world, thing, .Position, &Position{1, 2})

	testing.expect(t, ecs.world_sync_has(&world, thing, .Position))
	testing.expect(t, !ecs.world_sync_has(&world, thing, .Velocity))
	testing.expect_value(t, ecs.world_sync_get_part(&world, thing, .Position, Position)^, Position{1, 2})
	testing.expect(t, ecs.world_sync_get_part(&world, thing, .Velocity, Velocity) == nil)
}

@(test)
world_sync_set_now_overloads :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	a := ecs.world_sync_spawn(&world)
	b := ecs.world_sync_spawn(&world)
	c := ecs.world_sync_spawn(&world)
	d := ecs.world_sync_spawn(&world)

	position := Position{3, 4}
	by_value := ecs.world_sync_set_now(&world, a, .Position, Position{1, 2})
	by_pointer := ecs.world_sync_set_now(&world, b, .Position, &position)
	zeroed := ecs.world_sync_set_now(&world, c, .Position, Position)
	from_nil := ecs.world_sync_set_now(&world, d, .Position, (^Position)(nil))

	testing.expect_value(t, by_value^, Position{1, 2})
	testing.expect_value(t, by_pointer^, Position{3, 4})
	testing.expect_value(t, zeroed^, Position{})
	testing.expect_value(t, from_nil^, Position{})
	testing.expect_value(t, ecs.world_sync_count_parts(&world, .Position), 4)
}

@(test)
world_sync_set_now_existing_overwrites :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	thing := ecs.world_sync_spawn(&world)
	ecs.world_sync_set_now(&world, thing, .Position, Position{1, 2})
	ecs.world_sync_set_now(&world, thing, .Position, Position{3, 4})

	testing.expect_value(t, ecs.world_sync_count_parts(&world, .Position), 1)
	testing.expect_value(t, ecs.world_sync_get_part(&world, thing, .Position, Position)^, Position{3, 4})
}

@(test)
world_sync_kinds_can_share_a_type :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	thing := ecs.world_sync_spawn(&world)
	ecs.world_sync_set_now(&world, thing, .Position, Position{1, 2})
	ecs.world_sync_set_now(&world, thing, .Target, Position{5, 6})

	testing.expect_value(t, ecs.world_sync_get_part(&world, thing, .Position, Position)^, Position{1, 2})
	testing.expect_value(t, ecs.world_sync_get_part(&world, thing, .Target, Position)^, Position{5, 6})

	ecs.world_sync_remove_now(&world, thing, .Target)
	testing.expect(t, ecs.world_sync_has(&world, thing, .Position))
	testing.expect(t, !ecs.world_sync_has(&world, thing, .Target))
}

@(test)
world_sync_remove_now_removes_part :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	thing := ecs.world_sync_spawn(&world)
	ecs.world_sync_set_now(&world, thing, .Position, &Position{1, 2})
	ecs.world_sync_set_now(&world, thing, .Tag, Tag{})

	testing.expect(t, ecs.world_sync_remove_now(&world, thing, .Position))
	testing.expect(t, !ecs.world_sync_remove_now(&world, thing, .Position))
	testing.expect(t, !ecs.world_sync_has(&world, thing, .Position))
	testing.expect(t, ecs.world_sync_has(&world, thing, .Tag))

	// Killing after a remove must not touch the removed part.
	ecs.world_sync_kill_now(&world, thing)
	testing.expect_value(t, ecs.world_sync_count_parts(&world, .Tag), 0)
}

@(test)
world_sync_kill_now_removes_all_parts :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)
	destroyed_count = 0

	a := ecs.world_sync_spawn(&world)
	b := ecs.world_sync_spawn(&world)
	ecs.world_sync_set_now(&world, a, .Position, &Position{1, 1})
	ecs.world_sync_set_now(&world, a, .Velocity, &Velocity{1, 1})
	ecs.world_sync_set_now(&world, b, .Position, &Position{2, 2})

	testing.expect(t, ecs.world_sync_kill_now(&world, a))

	testing.expect(t, !ecs.world_sync_poke(&world, a))
	testing.expect_value(t, destroyed_count, 1)
	testing.expect_value(t, ecs.world_sync_count_parts(&world, .Position), 1)
	testing.expect_value(t, ecs.world_sync_count_parts(&world, .Velocity), 0)
	testing.expect_value(t, ecs.world_sync_get_part(&world, b, .Position, Position)^, Position{2, 2})

	// Reused idx starts with no parts.
	c := ecs.world_sync_spawn(&world)
	testing.expect_value(t, c.idx, a.idx)
	testing.expect(t, !ecs.world_sync_has(&world, c, .Position))
	testing.expect(t, !ecs.world_sync_has(&world, c, .Velocity))
}

@(test)
world_sync_kill_now_fails_for_dead_things :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	old := ecs.world_sync_spawn(&world)
	testing.expect(t, ecs.world_sync_kill_now(&world, old))
	testing.expect(t, !ecs.world_sync_kill_now(&world, old))

	// A stale thing must not kill the thing reusing its idx.
	new := ecs.world_sync_spawn(&world)
	ecs.world_sync_set_now(&world, new, .Position, Position{1, 2})
	testing.expect(t, !ecs.world_sync_kill_now(&world, old))
	testing.expect(t, ecs.world_sync_poke(&world, new))
	testing.expect(t, ecs.world_sync_has(&world, new, .Position))

	testing.expect(t, !ecs.world_sync_kill_now(&world, ecs.THING_NIL))
}

@(test)
world_sync_set_now_on_dead_thing_returns_nil :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	old := ecs.world_sync_spawn(&world)
	ecs.world_sync_kill_now(&world, old)
	new := ecs.world_sync_spawn(&world)

	testing.expect(t, ecs.world_sync_set_now(&world, old, .Position, Position{1, 2}) == nil)
	testing.expect(t, ecs.world_sync_set_now(&world, ecs.THING_NIL, .Position, Position) == nil)
	testing.expect(t, !ecs.world_sync_add_now(&world, old, .Tag))
	testing.expect_value(t, ecs.world_sync_count_parts(&world, .Position), 0)
	testing.expect_value(t, ecs.world_sync_count_parts(&world, .Tag), 0)
	testing.expect(t, !ecs.world_sync_has(&world, new, .Position))
}

@(test)
world_sync_add_now_inserts_zeroed_part :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	thing := ecs.world_sync_spawn(&world)
	testing.expect(t, ecs.world_sync_add_now(&world, thing, .Tag))
	testing.expect(t, ecs.world_sync_has(&world, thing, .Tag))

	ecs.world_sync_set_now(&world, thing, .Position, Position{1, 2})
	testing.expect(t, ecs.world_sync_add_now(&world, thing, .Position))
	testing.expect_value(t, ecs.world_sync_get_part(&world, thing, .Position, Position)^, Position{})
	testing.expect_value(t, ecs.world_sync_count_parts(&world, .Position), 1)

	// Killing removes added parts like any other.
	ecs.world_sync_kill_now(&world, thing)
	testing.expect_value(t, ecs.world_sync_count_parts(&world, .Tag), 0)
}

// >--------------------------------------------------------------------- Slices

@(test)
world_sync_get_parts_and_things_match_up :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	spawned: [4]ecs.Thing
	for &thing, i in spawned {
		thing = ecs.world_sync_spawn(&world)
		ecs.world_sync_set_now(&world, thing, .Position, &Position{f32(i), 0})
	}
	ecs.world_sync_kill_now(&world, spawned[1])

	parts := ecs.world_sync_get_parts(&world, .Position, Position)
	things := ecs.world_sync_get_things(&world, .Position)

	testing.expect_value(t, len(parts), 3)
	testing.expect_value(t, len(things), 3)
	for thing, i in things {
		testing.expect_value(t, ecs.world_sync_get_part(&world, thing, .Position, Position)^, parts[i])
	}
}

@(test)
world_sync_get_parts_of_tags_has_length :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	ecs.world_sync_set_now(&world, ecs.world_sync_spawn(&world), .Tag, Tag{})
	ecs.world_sync_set_now(&world, ecs.world_sync_spawn(&world), .Tag, Tag{})

	testing.expect_value(t, len(ecs.world_sync_get_parts(&world, .Tag, Tag)), 2)
	testing.expect_value(t, len(ecs.world_sync_get_things(&world, .Tag)), 2)
}

// >------------------------------------------------------------------- Commands

@(test)
world_sync_later_waits_for_apply_self :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	thing := ecs.world_sync_spawn(&world)
	ecs.world_sync_set_later(&world, thing, .Position, Position{1, 2})
	ecs.world_sync_add_later(&world, thing, .Tag)

	testing.expect_value(t, ecs.world_sync_count_cmds(&world), 2)
	testing.expect(t, !ecs.world_sync_has(&world, thing, .Position))
	testing.expect(t, !ecs.world_sync_has(&world, thing, .Tag))

	ecs.world_sync_apply_self(&world)

	testing.expect_value(t, ecs.world_sync_count_cmds(&world), 0)
	testing.expect_value(t, ecs.world_sync_get_part(&world, thing, .Position, Position)^, Position{1, 2})
	testing.expect(t, ecs.world_sync_has(&world, thing, .Tag))
}

@(test)
world_sync_set_later_overloads :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	a := ecs.world_sync_spawn(&world)
	b := ecs.world_sync_spawn(&world)
	c := ecs.world_sync_spawn(&world)
	d := ecs.world_sync_spawn(&world)

	position := Position{3, 4}
	ecs.world_sync_set_later(&world, a, .Position, Position{1, 2})
	ecs.world_sync_set_later(&world, b, .Position, &position)
	ecs.world_sync_set_later(&world, c, .Position, Position)
	ecs.world_sync_set_later(&world, d, .Position, (^Position)(nil))

	// The part is copied when recorded.
	position = Position{9, 9}

	ecs.world_sync_apply_self(&world)

	testing.expect_value(t, ecs.world_sync_get_part(&world, a, .Position, Position)^, Position{1, 2})
	testing.expect_value(t, ecs.world_sync_get_part(&world, b, .Position, Position)^, Position{3, 4})
	testing.expect_value(t, ecs.world_sync_get_part(&world, c, .Position, Position)^, Position{})
	testing.expect_value(t, ecs.world_sync_get_part(&world, d, .Position, Position)^, Position{})
	testing.expect_value(t, ecs.world_sync_count_parts(&world, .Position), 4)
}

@(test)
world_sync_set_later_overwrites_existing :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)
	destroyed_count = 0

	thing := ecs.world_sync_spawn(&world)
	ecs.world_sync_set_now(&world, thing, .Velocity, Velocity{1, 2})
	ecs.world_sync_set_later(&world, thing, .Velocity, Velocity{3, 4})
	ecs.world_sync_apply_self(&world)

	testing.expect_value(t, destroyed_count, 1)
	testing.expect_value(t, ecs.world_sync_count_parts(&world, .Velocity), 1)
	testing.expect_value(t, ecs.world_sync_get_part(&world, thing, .Velocity, Velocity)^, Velocity{3, 4})
}

@(test)
world_sync_later_supports_zero_sized_parts :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	thing := ecs.world_sync_spawn(&world)
	ecs.world_sync_set_later(&world, thing, .Tag, Tag{})
	ecs.world_sync_apply_self(&world)

	testing.expect(t, ecs.world_sync_has(&world, thing, .Tag))
}

@(test)
world_sync_remove_later_removes_part :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	thing := ecs.world_sync_spawn(&world)
	ecs.world_sync_set_now(&world, thing, .Position, Position{1, 2})
	ecs.world_sync_set_now(&world, thing, .Tag, Tag{})

	ecs.world_sync_remove_later(&world, thing, .Position)
	testing.expect(t, ecs.world_sync_has(&world, thing, .Position))

	ecs.world_sync_apply_self(&world)
	testing.expect(t, !ecs.world_sync_has(&world, thing, .Position))
	testing.expect(t, ecs.world_sync_has(&world, thing, .Tag))

	// Removing a missing part is skipped.
	ecs.world_sync_remove_later(&world, thing, .Position)
	ecs.world_sync_apply_self(&world)
	testing.expect(t, ecs.world_sync_has(&world, thing, .Tag))
}

@(test)
world_sync_kill_later_kills_on_apply :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	thing := ecs.world_sync_spawn(&world)
	ecs.world_sync_set_now(&world, thing, .Position, Position{1, 2})

	ecs.world_sync_kill_later(&world, thing)
	testing.expect(t, ecs.world_sync_poke(&world, thing))

	ecs.world_sync_apply_self(&world)
	testing.expect(t, !ecs.world_sync_poke(&world, thing))
	testing.expect_value(t, ecs.world_sync_count_parts(&world, .Position), 0)
}

@(test)
world_sync_apply_keeps_record_order :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	a := ecs.world_sync_spawn(&world)
	b := ecs.world_sync_spawn(&world)

	// Set then kill: the set happens, then the kill removes it.
	ecs.world_sync_set_later(&world, a, .Position, Position{1, 2})
	ecs.world_sync_kill_later(&world, a)

	// Kill then set: the set is skipped, the thing is dead by then.
	ecs.world_sync_kill_later(&world, b)
	ecs.world_sync_set_later(&world, b, .Position, Position{3, 4})

	// Set twice: the last one wins.
	c := ecs.world_sync_spawn(&world)
	ecs.world_sync_set_later(&world, c, .Position, Position{5, 6})
	ecs.world_sync_set_later(&world, c, .Position, Position{7, 8})

	ecs.world_sync_apply_self(&world)

	testing.expect(t, !ecs.world_sync_poke(&world, a))
	testing.expect(t, !ecs.world_sync_poke(&world, b))
	testing.expect_value(t, ecs.world_sync_count_parts(&world, .Position), 1)
	testing.expect_value(t, ecs.world_sync_get_part(&world, c, .Position, Position)^, Position{7, 8})
}

@(test)
world_sync_later_skips_stale_and_nil_things :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	old := ecs.world_sync_spawn(&world)
	ecs.world_sync_kill_now(&world, old)
	new := ecs.world_sync_spawn(&world)

	ecs.world_sync_set_later(&world, old, .Position, Position{1, 2})
	ecs.world_sync_add_later(&world, old, .Tag)
	ecs.world_sync_kill_later(&world, old)

	// THING_NIL is never recorded.
	ecs.world_sync_set_later(&world, ecs.THING_NIL, .Position, Position{1, 2})
	ecs.world_sync_kill_later(&world, ecs.THING_NIL)
	testing.expect_value(t, ecs.world_sync_count_cmds(&world), 3)

	ecs.world_sync_apply_self(&world)

	testing.expect(t, ecs.world_sync_poke(&world, new))
	testing.expect(t, !ecs.world_sync_has(&world, new, .Position))
	testing.expect_value(t, ecs.world_sync_count_parts(&world, .Position), 0)
	testing.expect_value(t, ecs.world_sync_count_parts(&world, .Tag), 0)
}

@(test)
world_sync_reset_drops_recorded_cmds :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)

	thing := ecs.world_sync_spawn(&world)
	ecs.world_sync_set_later(&world, thing, .Position, Position{1, 2})
	ecs.world_sync_reset(&world)

	testing.expect_value(t, ecs.world_sync_count_cmds(&world), 0)

	again := ecs.world_sync_spawn(&world)
	ecs.world_sync_apply_self(&world)
	testing.expect(t, !ecs.world_sync_has(&world, again, .Position))
}

@(test)
world_sync_destroy_frees_recorded_cmds :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)

	// Leaks would be reported by the test runner's tracking allocator.
	thing := ecs.world_sync_spawn(&world)
	ecs.world_sync_set_later(&world, thing, .Position, Position{1, 2})
	ecs.world_sync_destroy(&world)
}

@(test)
world_sync_apply_other_applies_and_keeps_buffer :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)
	cmds: ecs.Cmd_Pool(World_Part)
	ecs.cmd_pool_init(&cmds)
	defer ecs.cmd_pool_destroy(&cmds)

	a := ecs.world_sync_spawn(&world)
	b := ecs.world_sync_spawn(&world)
	ecs.world_sync_set_now(&world, b, .Tag, Tag{})

	position := Position{1, 2}
	ecs.cmd_pool_record_set_value(&cmds, a, .Position, &position, size_of(Position))
	ecs.cmd_pool_record_set_zero(&cmds, a, .Velocity)
	ecs.cmd_pool_record_remove(&cmds, b, .Tag)

	ecs.world_sync_apply_other(&world, &cmds)

	testing.expect_value(t, ecs.world_sync_get_part(&world, a, .Position, Position)^, Position{1, 2})
	testing.expect_value(t, ecs.world_sync_get_part(&world, a, .Velocity, Velocity)^, Velocity{})
	testing.expect(t, !ecs.world_sync_has(&world, b, .Tag))
	testing.expect_value(t, ecs.cmd_pool_count_cmds(&cmds), 3)
	testing.expect_value(t, ecs.world_sync_count_cmds(&world), 0)
}

@(test)
world_sync_apply_other_replays_into_many_worlds :: proc(t: ^testing.T) {
	first, second: World_Sync
	make_world(&first)
	defer ecs.world_sync_destroy(&first)
	make_world(&second)
	defer ecs.world_sync_destroy(&second)
	cmds: ecs.Cmd_Pool(World_Part)
	ecs.cmd_pool_init(&cmds)
	defer ecs.cmd_pool_destroy(&cmds)

	// Worlds spawned the same way hand out the same things.
	thing := ecs.world_sync_spawn(&first)
	testing.expect_value(t, ecs.world_sync_spawn(&second), thing)

	position := Position{1, 2}
	ecs.cmd_pool_record_set_value(&cmds, thing, .Position, &position, size_of(Position))

	ecs.world_sync_apply_other(&first, &cmds)
	ecs.world_sync_apply_other(&second, &cmds)

	testing.expect_value(t, ecs.world_sync_get_part(&first, thing, .Position, Position)^, Position{1, 2})
	testing.expect_value(t, ecs.world_sync_get_part(&second, thing, .Position, Position)^, Position{1, 2})
}

@(test)
world_sync_apply_other_leaves_own_cmds_pending :: proc(t: ^testing.T) {
	world: World_Sync
	make_world(&world)
	defer ecs.world_sync_destroy(&world)
	cmds: ecs.Cmd_Pool(World_Part)
	ecs.cmd_pool_init(&cmds)
	defer ecs.cmd_pool_destroy(&cmds)

	thing := ecs.world_sync_spawn(&world)
	ecs.world_sync_add_later(&world, thing, .Tag)
	ecs.cmd_pool_record_set_zero(&cmds, thing, .Position)

	ecs.world_sync_apply_other(&world, &cmds)

	testing.expect(t, ecs.world_sync_has(&world, thing, .Position))
	testing.expect(t, !ecs.world_sync_has(&world, thing, .Tag))
	testing.expect_value(t, ecs.world_sync_count_cmds(&world), 1)
}
