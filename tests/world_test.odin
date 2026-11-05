package ecs_tests

import "core:mem"
import "core:testing"

import ecs "../ecs"

@(private = "file")
make_world :: proc(world: ^World) {
	ecs.world_init(world, ecs.THING_POOL_MIN_CAPACITY)
	ecs.register(world, .Position, Position)
	ecs.register(world, .Velocity, Velocity, count_destroyed)
	ecs.register(world, .Tag, Tag)
	ecs.register(world, .Target, Position)
}

// >------------------------------------------------------------------ Lifecycle

@(test)
init_creates_empty_world :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	testing.expect_value(t, ecs.count_alive(&world), 0)
	testing.expect(t, ecs.is_registered(&world, .Position))
	testing.expect_value(t, ecs.count_parts(&world, .Position), 0)
}

@(test)
every_pool_allocates_with_pool_allocator :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	// Anything that bypasses the pool allocator panics.
	context.allocator = mem.panic_allocator()

	world: World
	ecs.world_init(
		&world,
		ecs.THING_POOL_MIN_CAPACITY,
		pool_allocator = mem.tracking_allocator(&track),
	)
	ecs.register(&world, .Position, Position)
	ecs.register(&world, .Velocity, Velocity)
	ecs.register_resource(&world, .Time, Time)

	// Grow the part sets, their pages and the command buffer past their first allocation.
	for _ in 0 ..< 32 {
		thing := ecs.spawn(&world)
		ecs.set_now(&world, thing, .Position, Position{1, 2})
		ecs.set_later(&world, thing, .Velocity, Velocity{3, 4})
	}
	ecs.apply_self(&world)
	testing.expect_value(t, ecs.count_parts(&world, .Velocity), 32)

	ecs.world_destroy(&world)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
destroy_destroys_parts :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	destroyed_count = 0

	vel := Velocity{1, 1}
	ecs.set_now(&world, ecs.spawn(&world), .Velocity, &vel)
	ecs.set_now(&world, ecs.spawn(&world), .Velocity, &vel)
	ecs.world_destroy(&world)

	testing.expect_value(t, destroyed_count, 2)
}

@(test)
reset_kills_everything_keeps_registrations :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.spawn(&world)
	ecs.set_now(&world, thing, .Position, &Position{1, 2})
	ecs.world_reset(&world)

	testing.expect(t, !ecs.poke(&world, thing))
	testing.expect_value(t, ecs.count_alive(&world), 0)
	testing.expect_value(t, ecs.count_parts(&world, .Position), 0)
	testing.expect(t, ecs.is_registered(&world, .Position))

	// Reused idx must not inherit the old mask.
	again := ecs.spawn(&world)
	testing.expect_value(t, again.idx, thing.idx)
	testing.expect(t, !ecs.has(&world, again, .Position))
}

// >---------------------------------------------------------------------- Parts

@(test)
set_now_and_get_part :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.spawn(&world)
	ecs.set_now(&world, thing, .Position, &Position{1, 2})

	testing.expect(t, ecs.has(&world, thing, .Position))
	testing.expect(t, !ecs.has(&world, thing, .Velocity))
	testing.expect_value(t, ecs.get_part(&world, thing, .Position, Position)^, Position{1, 2})
	testing.expect(t, ecs.get_part(&world, thing, .Velocity, Velocity) == nil)
}

@(test)
set_now_overloads :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a := ecs.spawn(&world)
	b := ecs.spawn(&world)
	c := ecs.spawn(&world)
	d := ecs.spawn(&world)

	position := Position{3, 4}
	by_value := ecs.set_now(&world, a, .Position, Position{1, 2})
	by_pointer := ecs.set_now(&world, b, .Position, &position)
	zeroed := ecs.set_now(&world, c, .Position, Position)
	from_nil := ecs.set_now(&world, d, .Position, (^Position)(nil))

	testing.expect_value(t, by_value^, Position{1, 2})
	testing.expect_value(t, by_pointer^, Position{3, 4})
	testing.expect_value(t, zeroed^, Position{})
	testing.expect_value(t, from_nil^, Position{})
	testing.expect_value(t, ecs.count_parts(&world, .Position), 4)
}

@(test)
set_now_existing_overwrites :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.spawn(&world)
	ecs.set_now(&world, thing, .Position, Position{1, 2})
	ecs.set_now(&world, thing, .Position, Position{3, 4})

	testing.expect_value(t, ecs.count_parts(&world, .Position), 1)
	testing.expect_value(t, ecs.get_part(&world, thing, .Position, Position)^, Position{3, 4})
}

@(test)
kinds_can_share_a_type :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.spawn(&world)
	ecs.set_now(&world, thing, .Position, Position{1, 2})
	ecs.set_now(&world, thing, .Target, Position{5, 6})

	testing.expect_value(t, ecs.get_part(&world, thing, .Position, Position)^, Position{1, 2})
	testing.expect_value(t, ecs.get_part(&world, thing, .Target, Position)^, Position{5, 6})

	ecs.remove_now(&world, thing, .Target)
	testing.expect(t, ecs.has(&world, thing, .Position))
	testing.expect(t, !ecs.has(&world, thing, .Target))
}

@(test)
remove_now_removes_part :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.spawn(&world)
	ecs.set_now(&world, thing, .Position, &Position{1, 2})
	ecs.set_now(&world, thing, .Tag, Tag{})

	testing.expect(t, ecs.remove_now(&world, thing, .Position))
	testing.expect(t, !ecs.remove_now(&world, thing, .Position))
	testing.expect(t, !ecs.has(&world, thing, .Position))
	testing.expect(t, ecs.has(&world, thing, .Tag))

	// Killing after a remove must not touch the removed part.
	ecs.kill_now(&world, thing)
	testing.expect_value(t, ecs.count_parts(&world, .Tag), 0)
}

@(test)
kill_now_removes_all_parts :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	destroyed_count = 0

	a := ecs.spawn(&world)
	b := ecs.spawn(&world)
	ecs.set_now(&world, a, .Position, &Position{1, 1})
	ecs.set_now(&world, a, .Velocity, &Velocity{1, 1})
	ecs.set_now(&world, b, .Position, &Position{2, 2})

	testing.expect(t, ecs.kill_now(&world, a))

	testing.expect(t, !ecs.poke(&world, a))
	testing.expect_value(t, destroyed_count, 1)
	testing.expect_value(t, ecs.count_parts(&world, .Position), 1)
	testing.expect_value(t, ecs.count_parts(&world, .Velocity), 0)
	testing.expect_value(t, ecs.get_part(&world, b, .Position, Position)^, Position{2, 2})

	// Reused idx starts with no parts.
	c := ecs.spawn(&world)
	testing.expect_value(t, c.idx, a.idx)
	testing.expect(t, !ecs.has(&world, c, .Position))
	testing.expect(t, !ecs.has(&world, c, .Velocity))
}

@(test)
kill_now_fails_for_dead_things :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	old := ecs.spawn(&world)
	testing.expect(t, ecs.kill_now(&world, old))
	testing.expect(t, !ecs.kill_now(&world, old))

	// A stale thing must not kill the thing reusing its idx.
	new := ecs.spawn(&world)
	ecs.set_now(&world, new, .Position, Position{1, 2})
	testing.expect(t, !ecs.kill_now(&world, old))
	testing.expect(t, ecs.poke(&world, new))
	testing.expect(t, ecs.has(&world, new, .Position))

	testing.expect(t, !ecs.kill_now(&world, ecs.THING_NIL))
}

@(test)
set_now_on_dead_thing_returns_nil :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	old := ecs.spawn(&world)
	ecs.kill_now(&world, old)
	new := ecs.spawn(&world)

	testing.expect(t, ecs.set_now(&world, old, .Position, Position{1, 2}) == nil)
	testing.expect(t, ecs.set_now(&world, ecs.THING_NIL, .Position, Position) == nil)
	testing.expect(t, !ecs.add_now(&world, old, .Tag))
	testing.expect_value(t, ecs.count_parts(&world, .Position), 0)
	testing.expect_value(t, ecs.count_parts(&world, .Tag), 0)
	testing.expect(t, !ecs.has(&world, new, .Position))
}

@(test)
add_now_inserts_zeroed_part :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.spawn(&world)
	testing.expect(t, ecs.add_now(&world, thing, .Tag))
	testing.expect(t, ecs.has(&world, thing, .Tag))

	ecs.set_now(&world, thing, .Position, Position{1, 2})
	testing.expect(t, ecs.add_now(&world, thing, .Position))
	testing.expect_value(t, ecs.get_part(&world, thing, .Position, Position)^, Position{})
	testing.expect_value(t, ecs.count_parts(&world, .Position), 1)

	// Killing removes added parts like any other.
	ecs.kill_now(&world, thing)
	testing.expect_value(t, ecs.count_parts(&world, .Tag), 0)
}

// >--------------------------------------------------------------------- Slices

@(test)
get_parts_and_things_match_up :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	spawned: [4]ecs.Thing
	for &thing, i in spawned {
		thing = ecs.spawn(&world)
		ecs.set_now(&world, thing, .Position, &Position{f32(i), 0})
	}
	ecs.kill_now(&world, spawned[1])

	parts := ecs.get_parts(&world, .Position, Position)
	things := ecs.get_things(&world, .Position)

	testing.expect_value(t, len(parts), 3)
	testing.expect_value(t, len(things), 3)
	for thing, i in things {
		testing.expect_value(t, ecs.get_part(&world, thing, .Position, Position)^, parts[i])
	}
}

@(test)
get_parts_of_tags_has_length :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	ecs.set_now(&world, ecs.spawn(&world), .Tag, Tag{})
	ecs.set_now(&world, ecs.spawn(&world), .Tag, Tag{})

	testing.expect_value(t, len(ecs.get_parts(&world, .Tag, Tag)), 2)
	testing.expect_value(t, len(ecs.get_things(&world, .Tag)), 2)
}

// >------------------------------------------------------------------- Commands

@(test)
later_waits_for_apply_self :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.spawn(&world)
	ecs.set_later(&world, thing, .Position, Position{1, 2})
	ecs.add_later(&world, thing, .Tag)

	testing.expect_value(t, ecs.count_cmds(&world), 2)
	testing.expect(t, !ecs.has(&world, thing, .Position))
	testing.expect(t, !ecs.has(&world, thing, .Tag))

	ecs.apply_self(&world)

	testing.expect_value(t, ecs.count_cmds(&world), 0)
	testing.expect_value(t, ecs.get_part(&world, thing, .Position, Position)^, Position{1, 2})
	testing.expect(t, ecs.has(&world, thing, .Tag))
}

@(test)
set_later_overloads :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a := ecs.spawn(&world)
	b := ecs.spawn(&world)
	c := ecs.spawn(&world)
	d := ecs.spawn(&world)

	position := Position{3, 4}
	ecs.set_later(&world, a, .Position, Position{1, 2})
	ecs.set_later(&world, b, .Position, &position)
	ecs.set_later(&world, c, .Position, Position)
	ecs.set_later(&world, d, .Position, (^Position)(nil))

	// The part is copied when recorded.
	position = Position{9, 9}

	ecs.apply_self(&world)

	testing.expect_value(t, ecs.get_part(&world, a, .Position, Position)^, Position{1, 2})
	testing.expect_value(t, ecs.get_part(&world, b, .Position, Position)^, Position{3, 4})
	testing.expect_value(t, ecs.get_part(&world, c, .Position, Position)^, Position{})
	testing.expect_value(t, ecs.get_part(&world, d, .Position, Position)^, Position{})
	testing.expect_value(t, ecs.count_parts(&world, .Position), 4)
}

@(test)
set_later_overwrites_existing :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	destroyed_count = 0

	thing := ecs.spawn(&world)
	ecs.set_now(&world, thing, .Velocity, Velocity{1, 2})
	ecs.set_later(&world, thing, .Velocity, Velocity{3, 4})
	ecs.apply_self(&world)

	testing.expect_value(t, destroyed_count, 1)
	testing.expect_value(t, ecs.count_parts(&world, .Velocity), 1)
	testing.expect_value(t, ecs.get_part(&world, thing, .Velocity, Velocity)^, Velocity{3, 4})
}

@(test)
later_supports_zero_sized_parts :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.spawn(&world)
	ecs.set_later(&world, thing, .Tag, Tag{})
	ecs.apply_self(&world)

	testing.expect(t, ecs.has(&world, thing, .Tag))
}

@(test)
remove_later_removes_part :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.spawn(&world)
	ecs.set_now(&world, thing, .Position, Position{1, 2})
	ecs.set_now(&world, thing, .Tag, Tag{})

	ecs.remove_later(&world, thing, .Position)
	testing.expect(t, ecs.has(&world, thing, .Position))

	ecs.apply_self(&world)
	testing.expect(t, !ecs.has(&world, thing, .Position))
	testing.expect(t, ecs.has(&world, thing, .Tag))

	// Removing a missing part is skipped.
	ecs.remove_later(&world, thing, .Position)
	ecs.apply_self(&world)
	testing.expect(t, ecs.has(&world, thing, .Tag))
}

@(test)
kill_later_kills_on_apply :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.spawn(&world)
	ecs.set_now(&world, thing, .Position, Position{1, 2})

	ecs.kill_later(&world, thing)
	testing.expect(t, ecs.poke(&world, thing))

	ecs.apply_self(&world)
	testing.expect(t, !ecs.poke(&world, thing))
	testing.expect_value(t, ecs.count_parts(&world, .Position), 0)
}

@(test)
apply_keeps_record_order :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a := ecs.spawn(&world)
	b := ecs.spawn(&world)

	// Set then kill: the set happens, then the kill removes it.
	ecs.set_later(&world, a, .Position, Position{1, 2})
	ecs.kill_later(&world, a)

	// Kill then set: the set is skipped, the thing is dead by then.
	ecs.kill_later(&world, b)
	ecs.set_later(&world, b, .Position, Position{3, 4})

	// Set twice: the last one wins.
	c := ecs.spawn(&world)
	ecs.set_later(&world, c, .Position, Position{5, 6})
	ecs.set_later(&world, c, .Position, Position{7, 8})

	ecs.apply_self(&world)

	testing.expect(t, !ecs.poke(&world, a))
	testing.expect(t, !ecs.poke(&world, b))
	testing.expect_value(t, ecs.count_parts(&world, .Position), 1)
	testing.expect_value(t, ecs.get_part(&world, c, .Position, Position)^, Position{7, 8})
}

@(test)
later_skips_stale_and_nil_things :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	old := ecs.spawn(&world)
	ecs.kill_now(&world, old)
	new := ecs.spawn(&world)

	ecs.set_later(&world, old, .Position, Position{1, 2})
	ecs.add_later(&world, old, .Tag)
	ecs.kill_later(&world, old)

	// THING_NIL is never recorded.
	ecs.set_later(&world, ecs.THING_NIL, .Position, Position{1, 2})
	ecs.kill_later(&world, ecs.THING_NIL)
	testing.expect_value(t, ecs.count_cmds(&world), 3)

	ecs.apply_self(&world)

	testing.expect(t, ecs.poke(&world, new))
	testing.expect(t, !ecs.has(&world, new, .Position))
	testing.expect_value(t, ecs.count_parts(&world, .Position), 0)
	testing.expect_value(t, ecs.count_parts(&world, .Tag), 0)
}

@(test)
reset_drops_recorded_cmds :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.spawn(&world)
	ecs.set_later(&world, thing, .Position, Position{1, 2})
	ecs.world_reset(&world)

	testing.expect_value(t, ecs.count_cmds(&world), 0)

	again := ecs.spawn(&world)
	ecs.apply_self(&world)
	testing.expect(t, !ecs.has(&world, again, .Position))
}

@(test)
destroy_frees_recorded_cmds :: proc(t: ^testing.T) {
	world: World
	make_world(&world)

	// Leaks would be reported by the test runner's tracking allocator.
	thing := ecs.spawn(&world)
	ecs.set_later(&world, thing, .Position, Position{1, 2})
	ecs.world_destroy(&world)
}

@(test)
apply_other_applies_and_keeps_buffer :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	cmds: Cmd_Pool
	ecs.cmd_pool_init(&cmds)
	defer ecs.cmd_pool_destroy(&cmds)

	a := ecs.spawn(&world)
	b := ecs.spawn(&world)
	ecs.set_now(&world, b, .Tag, Tag{})

	position := Position{1, 2}
	ecs.cmd_pool_record_set_value(&cmds, a, .Position, &position, size_of(Position))
	ecs.cmd_pool_record_set_zero(&cmds, a, .Velocity)
	ecs.cmd_pool_record_remove(&cmds, b, .Tag)

	ecs.apply_other(&world, &cmds)

	testing.expect_value(t, ecs.get_part(&world, a, .Position, Position)^, Position{1, 2})
	testing.expect_value(t, ecs.get_part(&world, a, .Velocity, Velocity)^, Velocity{})
	testing.expect(t, !ecs.has(&world, b, .Tag))
	testing.expect_value(t, ecs.cmd_pool_count_cmds(&cmds), 3)
	testing.expect_value(t, ecs.count_cmds(&world), 0)
}

@(test)
apply_other_replays_into_many_worlds :: proc(t: ^testing.T) {
	first, second: World
	make_world(&first)
	defer ecs.world_destroy(&first)
	make_world(&second)
	defer ecs.world_destroy(&second)
	cmds: Cmd_Pool
	ecs.cmd_pool_init(&cmds)
	defer ecs.cmd_pool_destroy(&cmds)

	// Worlds spawned the same way hand out the same things.
	thing := ecs.spawn(&first)
	testing.expect_value(t, ecs.spawn(&second), thing)

	position := Position{1, 2}
	ecs.cmd_pool_record_set_value(&cmds, thing, .Position, &position, size_of(Position))

	ecs.apply_other(&first, &cmds)
	ecs.apply_other(&second, &cmds)

	testing.expect_value(t, ecs.get_part(&first, thing, .Position, Position)^, Position{1, 2})
	testing.expect_value(t, ecs.get_part(&second, thing, .Position, Position)^, Position{1, 2})
}

@(test)
apply_other_leaves_own_cmds_pending :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	cmds: Cmd_Pool
	ecs.cmd_pool_init(&cmds)
	defer ecs.cmd_pool_destroy(&cmds)

	thing := ecs.spawn(&world)
	ecs.add_later(&world, thing, .Tag)
	ecs.cmd_pool_record_set_zero(&cmds, thing, .Position)

	ecs.apply_other(&world, &cmds)

	testing.expect(t, ecs.has(&world, thing, .Position))
	testing.expect(t, !ecs.has(&world, thing, .Tag))
	testing.expect_value(t, ecs.count_cmds(&world), 1)
}

// >------------------------------------------------------------------ Resources

@(test)
register_resource_and_get :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	testing.expect(t, !ecs.is_resource_registered(&world, .Time))
	ecs.register_resource(&world, .Time, Time)
	testing.expect(t, ecs.is_resource_registered(&world, .Time))

	time := ecs.get_resource(&world, .Time, Time)
	testing.expect_value(t, time^, Time{})

	time.delta = 0.5
	testing.expect_value(t, ecs.get_resource(&world, .Time, Time)^, Time{0.5, 0})
}

@(test)
reset_zeroes_resources_keeps_registrations :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	ecs.register_resource(&world, .Time, Time, count_destroyed_time)
	ecs.register_resource(&world, .Gravity, f32)
	ecs.get_resource(&world, .Time, Time)^ = {1, 2}
	ecs.get_resource(&world, .Gravity, f32)^ = 9.81

	destroyed_resources = {}
	ecs.world_reset(&world)

	testing.expect_value(t, destroyed_resources[.Time], 1)
	testing.expect(t, ecs.is_resource_registered(&world, .Time))
	testing.expect(t, ecs.is_resource_registered(&world, .Gravity))
	testing.expect_value(t, ecs.get_resource(&world, .Time, Time)^, Time{})
	testing.expect_value(t, ecs.get_resource(&world, .Gravity, f32)^, 0)
}

@(test)
destroy_runs_resource_destroyers :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	ecs.register_resource(&world, .Time, Time, count_destroyed_time)

	destroyed_resources = {}
	ecs.world_destroy(&world)

	testing.expect_value(t, destroyed_resources[.Time], 1)
}

// >-------------------------------------------------------------------- Asserts

@(test)
set_later_wrong_type_asserts_when_recording :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	backing: [1 << 16]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(&world, ecs.THING_POOL_MIN_CAPACITY, 64, mem.arena_allocator(&arena))
	ecs.register(&world, .Target, Position)
	thing := ecs.spawn(&world)

	testing.expect_assert_message(t, "Part kind Target is a Position, not a Velocity.")
	ecs.set_later(&world, thing, .Target, Velocity{1, 2})
	testing.fail_now(t, "The call did not assert.")
}

@(test)
get_resource_wrong_type_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	backing: [1 << 16]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(&world, ecs.THING_POOL_MIN_CAPACITY, 64, mem.arena_allocator(&arena))
	ecs.register_resource(&world, .Gravity, f32)

	testing.expect_assert_message(t, "Resource Gravity is a f32, not a f64.")
	ecs.get_resource(&world, .Gravity, f64)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
get_resource_unregistered_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	backing: [1 << 16]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(&world, ecs.THING_POOL_MIN_CAPACITY, 64, mem.arena_allocator(&arena))

	testing.expect_assert_message(t, "Resource Time is not registered in the pool.")
	ecs.get_resource(&world, .Time, Time)
	testing.fail_now(t, "The call did not assert.")
}
