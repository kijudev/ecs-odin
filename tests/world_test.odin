package ecs_tests

import "core:mem"
import "core:testing"

import ecs "../ecs"

@(private = "file")
make_world :: proc(world: ^World) {
	ecs.world_init(world, ecs.THING_POOL_MIN_CAPACITY)
	ecs.world_register(world, .Position, Position)
	ecs.world_register(world, .Velocity, Velocity, count_destroyed)
	ecs.world_register(world, .Tag, Tag)
	ecs.world_register(world, .Target, Position)
}

// >------------------------------------------------------------------ Lifecycle

@(test)
init_creates_empty_world :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	testing.expect_value(t, ecs.world_count_alive(&world), 0)
	testing.expect(t, ecs.world_is_registered(&world, .Position))
	testing.expect_value(t, ecs.world_count_parts(&world, .Position), 0)
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
	ecs.world_register(&world, .Position, Position)
	ecs.world_register(&world, .Velocity, Velocity)
	ecs.world_register_resource(&world, .Time, Time)

	// Grow the part sets, their pages and the command buffer past their first allocation.
	for _ in 0 ..< 32 {
		thing := ecs.world_spawn(&world)
		ecs.set_now(&world, thing, .Position, Position{1, 2})
		ecs.set_later(&world, thing, .Velocity, Velocity{3, 4})
	}
	ecs.world_apply(&world)
	testing.expect_value(t, ecs.world_count_parts(&world, .Velocity), 32)

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
	ecs.set_now(&world, ecs.world_spawn(&world), .Velocity, &vel)
	ecs.set_now(&world, ecs.world_spawn(&world), .Velocity, &vel)
	ecs.world_destroy(&world)

	testing.expect_value(t, destroyed_count, 2)
}

@(test)
reset_kills_everything_keeps_registrations :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	ecs.set_now(&world, thing, .Position, &Position{1, 2})
	ecs.world_reset(&world)

	testing.expect(t, !ecs.world_is_alive(&world, thing))
	testing.expect_value(t, ecs.world_count_alive(&world), 0)
	testing.expect_value(t, ecs.world_count_parts(&world, .Position), 0)
	testing.expect(t, ecs.world_is_registered(&world, .Position))

	// Reused idx must not inherit the old mask.
	again := ecs.world_spawn(&world)
	testing.expect_value(t, again.idx, thing.idx)
	testing.expect(t, !ecs.world_has(&world, again, .Position))
}

// >---------------------------------------------------------------------- Parts

@(test)
set_now_and_get_part :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	ecs.set_now(&world, thing, .Position, &Position{1, 2})

	testing.expect(t, ecs.world_has(&world, thing, .Position))
	testing.expect(t, !ecs.world_has(&world, thing, .Velocity))
	testing.expect_value(t, ecs.world_get_part(&world, thing, .Position, Position)^, Position{1, 2})
	testing.expect(t, ecs.world_get_part(&world, thing, .Velocity, Velocity) == nil)
}

@(test)
set_now_overloads :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a := ecs.world_spawn(&world)
	b := ecs.world_spawn(&world)
	c := ecs.world_spawn(&world)
	d := ecs.world_spawn(&world)

	position := Position{3, 4}
	by_value := ecs.set_now(&world, a, .Position, Position{1, 2})
	by_pointer := ecs.set_now(&world, b, .Position, &position)
	zeroed := ecs.set_now(&world, c, .Position, Position)
	from_nil := ecs.set_now(&world, d, .Position, (^Position)(nil))

	testing.expect_value(t, by_value^, Position{1, 2})
	testing.expect_value(t, by_pointer^, Position{3, 4})
	testing.expect_value(t, zeroed^, Position{})
	testing.expect_value(t, from_nil^, Position{})
	testing.expect_value(t, ecs.world_count_parts(&world, .Position), 4)
}

@(test)
set_now_existing_overwrites :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	ecs.set_now(&world, thing, .Position, Position{1, 2})
	ecs.set_now(&world, thing, .Position, Position{3, 4})

	testing.expect_value(t, ecs.world_count_parts(&world, .Position), 1)
	testing.expect_value(t, ecs.world_get_part(&world, thing, .Position, Position)^, Position{3, 4})
}

@(test)
kinds_can_share_a_type :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	ecs.set_now(&world, thing, .Position, Position{1, 2})
	ecs.set_now(&world, thing, .Target, Position{5, 6})

	testing.expect_value(t, ecs.world_get_part(&world, thing, .Position, Position)^, Position{1, 2})
	testing.expect_value(t, ecs.world_get_part(&world, thing, .Target, Position)^, Position{5, 6})

	ecs.world_remove_now(&world, thing, .Target)
	testing.expect(t, ecs.world_has(&world, thing, .Position))
	testing.expect(t, !ecs.world_has(&world, thing, .Target))
}

@(test)
remove_now_removes_part :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	ecs.set_now(&world, thing, .Position, &Position{1, 2})
	ecs.set_now(&world, thing, .Tag, Tag{})

	testing.expect(t, ecs.world_remove_now(&world, thing, .Position))
	testing.expect(t, !ecs.world_remove_now(&world, thing, .Position))
	testing.expect(t, !ecs.world_has(&world, thing, .Position))
	testing.expect(t, ecs.world_has(&world, thing, .Tag))

	// Killing after a remove must not touch the removed part.
	ecs.world_kill_now(&world, thing)
	testing.expect_value(t, ecs.world_count_parts(&world, .Tag), 0)
}

@(test)
kill_now_removes_all_parts :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	destroyed_count = 0

	a := ecs.world_spawn(&world)
	b := ecs.world_spawn(&world)
	ecs.set_now(&world, a, .Position, &Position{1, 1})
	ecs.set_now(&world, a, .Velocity, &Velocity{1, 1})
	ecs.set_now(&world, b, .Position, &Position{2, 2})

	testing.expect(t, ecs.world_kill_now(&world, a))

	testing.expect(t, !ecs.world_is_alive(&world, a))
	testing.expect_value(t, destroyed_count, 1)
	testing.expect_value(t, ecs.world_count_parts(&world, .Position), 1)
	testing.expect_value(t, ecs.world_count_parts(&world, .Velocity), 0)
	testing.expect_value(t, ecs.world_get_part(&world, b, .Position, Position)^, Position{2, 2})

	// Reused idx starts with no parts.
	c := ecs.world_spawn(&world)
	testing.expect_value(t, c.idx, a.idx)
	testing.expect(t, !ecs.world_has(&world, c, .Position))
	testing.expect(t, !ecs.world_has(&world, c, .Velocity))
}

@(test)
kill_now_fails_for_dead_things :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	old := ecs.world_spawn(&world)
	testing.expect(t, ecs.world_kill_now(&world, old))
	testing.expect(t, !ecs.world_kill_now(&world, old))

	// A stale thing must not kill the thing reusing its idx.
	new := ecs.world_spawn(&world)
	ecs.set_now(&world, new, .Position, Position{1, 2})
	testing.expect(t, !ecs.world_kill_now(&world, old))
	testing.expect(t, ecs.world_is_alive(&world, new))
	testing.expect(t, ecs.world_has(&world, new, .Position))

	testing.expect(t, !ecs.world_kill_now(&world, ecs.THING_NIL))
}

@(test)
set_now_on_dead_thing_returns_nil :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	old := ecs.world_spawn(&world)
	ecs.world_kill_now(&world, old)
	new := ecs.world_spawn(&world)

	testing.expect(t, ecs.set_now(&world, old, .Position, Position{1, 2}) == nil)
	testing.expect(t, ecs.set_now(&world, ecs.THING_NIL, .Position, Position) == nil)
	testing.expect(t, !ecs.world_add_now(&world, old, .Tag))
	testing.expect_value(t, ecs.world_count_parts(&world, .Position), 0)
	testing.expect_value(t, ecs.world_count_parts(&world, .Tag), 0)
	testing.expect(t, !ecs.world_has(&world, new, .Position))
}

@(test)
add_now_inserts_zeroed_part :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	testing.expect(t, ecs.world_add_now(&world, thing, .Tag))
	testing.expect(t, ecs.world_has(&world, thing, .Tag))

	ecs.set_now(&world, thing, .Position, Position{1, 2})
	testing.expect(t, ecs.world_add_now(&world, thing, .Position))
	testing.expect_value(t, ecs.world_get_part(&world, thing, .Position, Position)^, Position{})
	testing.expect_value(t, ecs.world_count_parts(&world, .Position), 1)

	// Killing removes added parts like any other.
	ecs.world_kill_now(&world, thing)
	testing.expect_value(t, ecs.world_count_parts(&world, .Tag), 0)
}

// >--------------------------------------------------------------------- Slices

@(test)
get_parts_and_things_match_up :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	spawned: [4]ecs.Thing
	for &thing, i in spawned {
		thing = ecs.world_spawn(&world)
		ecs.set_now(&world, thing, .Position, &Position{f32(i), 0})
	}
	ecs.world_kill_now(&world, spawned[1])

	parts := ecs.world_get_parts(&world, .Position, Position)
	things := ecs.world_get_things(&world, .Position)

	testing.expect_value(t, len(parts), 3)
	testing.expect_value(t, len(things), 3)
	for thing, i in things {
		testing.expect_value(t, ecs.world_get_part(&world, thing, .Position, Position)^, parts[i])
	}
}

@(test)
get_parts_of_tags_has_length :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	ecs.set_now(&world, ecs.world_spawn(&world), .Tag, Tag{})
	ecs.set_now(&world, ecs.world_spawn(&world), .Tag, Tag{})

	testing.expect_value(t, len(ecs.world_get_parts(&world, .Tag, Tag)), 2)
	testing.expect_value(t, len(ecs.world_get_things(&world, .Tag)), 2)
}

// >------------------------------------------------------------------- Commands

@(test)
later_waits_for_apply :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	ecs.set_later(&world, thing, .Position, Position{1, 2})
	ecs.world_add_later(&world, thing, .Tag)

	testing.expect_value(t, ecs.world_count_cmds(&world), 2)
	testing.expect(t, !ecs.world_has(&world, thing, .Position))
	testing.expect(t, !ecs.world_has(&world, thing, .Tag))

	ecs.world_apply(&world)

	testing.expect_value(t, ecs.world_count_cmds(&world), 0)
	testing.expect_value(t, ecs.world_get_part(&world, thing, .Position, Position)^, Position{1, 2})
	testing.expect(t, ecs.world_has(&world, thing, .Tag))
}

@(test)
set_later_overloads :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a := ecs.world_spawn(&world)
	b := ecs.world_spawn(&world)
	c := ecs.world_spawn(&world)
	d := ecs.world_spawn(&world)

	position := Position{3, 4}
	ecs.set_later(&world, a, .Position, Position{1, 2})
	ecs.set_later(&world, b, .Position, &position)
	ecs.set_later(&world, c, .Position, Position)
	ecs.set_later(&world, d, .Position, (^Position)(nil))

	// The part is copied when recorded.
	position = Position{9, 9}

	ecs.world_apply(&world)

	testing.expect_value(t, ecs.world_get_part(&world, a, .Position, Position)^, Position{1, 2})
	testing.expect_value(t, ecs.world_get_part(&world, b, .Position, Position)^, Position{3, 4})
	testing.expect_value(t, ecs.world_get_part(&world, c, .Position, Position)^, Position{})
	testing.expect_value(t, ecs.world_get_part(&world, d, .Position, Position)^, Position{})
	testing.expect_value(t, ecs.world_count_parts(&world, .Position), 4)
}

@(test)
set_later_overwrites_existing :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	destroyed_count = 0

	thing := ecs.world_spawn(&world)
	ecs.set_now(&world, thing, .Velocity, Velocity{1, 2})
	ecs.set_later(&world, thing, .Velocity, Velocity{3, 4})
	ecs.world_apply(&world)

	testing.expect_value(t, destroyed_count, 1)
	testing.expect_value(t, ecs.world_count_parts(&world, .Velocity), 1)
	testing.expect_value(t, ecs.world_get_part(&world, thing, .Velocity, Velocity)^, Velocity{3, 4})
}

@(test)
later_supports_zero_sized_parts :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	ecs.set_later(&world, thing, .Tag, Tag{})
	ecs.world_apply(&world)

	testing.expect(t, ecs.world_has(&world, thing, .Tag))
}

@(test)
remove_later_removes_part :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	ecs.set_now(&world, thing, .Position, Position{1, 2})
	ecs.set_now(&world, thing, .Tag, Tag{})

	ecs.world_remove_later(&world, thing, .Position)
	testing.expect(t, ecs.world_has(&world, thing, .Position))

	ecs.world_apply(&world)
	testing.expect(t, !ecs.world_has(&world, thing, .Position))
	testing.expect(t, ecs.world_has(&world, thing, .Tag))

	// Removing a missing part is skipped.
	ecs.world_remove_later(&world, thing, .Position)
	ecs.world_apply(&world)
	testing.expect(t, ecs.world_has(&world, thing, .Tag))
}

@(test)
kill_later_kills_on_apply :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	ecs.set_now(&world, thing, .Position, Position{1, 2})

	ecs.world_kill_later(&world, thing)
	testing.expect(t, ecs.world_is_alive(&world, thing))

	ecs.world_apply(&world)
	testing.expect(t, !ecs.world_is_alive(&world, thing))
	testing.expect_value(t, ecs.world_count_parts(&world, .Position), 0)
}

@(test)
apply_keeps_record_order :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a := ecs.world_spawn(&world)
	b := ecs.world_spawn(&world)

	// Set then kill: the set happens, then the kill removes it.
	ecs.set_later(&world, a, .Position, Position{1, 2})
	ecs.world_kill_later(&world, a)

	// Kill then set: the set is skipped, the thing is dead by then.
	ecs.world_kill_later(&world, b)
	ecs.set_later(&world, b, .Position, Position{3, 4})

	// Set twice: the last one wins.
	c := ecs.world_spawn(&world)
	ecs.set_later(&world, c, .Position, Position{5, 6})
	ecs.set_later(&world, c, .Position, Position{7, 8})

	ecs.world_apply(&world)

	testing.expect(t, !ecs.world_is_alive(&world, a))
	testing.expect(t, !ecs.world_is_alive(&world, b))
	testing.expect_value(t, ecs.world_count_parts(&world, .Position), 1)
	testing.expect_value(t, ecs.world_get_part(&world, c, .Position, Position)^, Position{7, 8})
}

@(test)
later_skips_stale_and_nil_things :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	old := ecs.world_spawn(&world)
	ecs.world_kill_now(&world, old)
	new := ecs.world_spawn(&world)

	ecs.set_later(&world, old, .Position, Position{1, 2})
	ecs.world_add_later(&world, old, .Tag)
	ecs.world_kill_later(&world, old)

	// THING_NIL is never recorded.
	ecs.set_later(&world, ecs.THING_NIL, .Position, Position{1, 2})
	ecs.world_kill_later(&world, ecs.THING_NIL)
	testing.expect_value(t, ecs.world_count_cmds(&world), 3)

	ecs.world_apply(&world)

	testing.expect(t, ecs.world_is_alive(&world, new))
	testing.expect(t, !ecs.world_has(&world, new, .Position))
	testing.expect_value(t, ecs.world_count_parts(&world, .Position), 0)
	testing.expect_value(t, ecs.world_count_parts(&world, .Tag), 0)
}

@(test)
reset_drops_recorded_cmds :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	ecs.set_later(&world, thing, .Position, Position{1, 2})
	ecs.world_reset(&world)

	testing.expect_value(t, ecs.world_count_cmds(&world), 0)

	again := ecs.world_spawn(&world)
	ecs.world_apply(&world)
	testing.expect(t, !ecs.world_has(&world, again, .Position))
}

@(test)
destroy_frees_recorded_cmds :: proc(t: ^testing.T) {
	world: World
	make_world(&world)

	// Leaks would be reported by the test runner's tracking allocator.
	thing := ecs.world_spawn(&world)
	ecs.set_later(&world, thing, .Position, Position{1, 2})
	ecs.world_destroy(&world)
}

@(test)
apply_buffer_applies_and_keeps_buffer :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer)
	defer ecs.cmd_buffer_destroy(&buffer)

	a := ecs.world_spawn(&world)
	b := ecs.world_spawn(&world)
	ecs.set_now(&world, b, .Tag, Tag{})

	position := Position{1, 2}
	ecs.cmd_buffer_record_set_value(&buffer, a, .Position, &position, size_of(Position))
	ecs.cmd_buffer_record_set_zero(&buffer, a, .Velocity)
	ecs.cmd_buffer_record_remove(&buffer, b, .Tag)

	ecs.world_apply_buffer(&world, &buffer)

	testing.expect_value(t, ecs.world_get_part(&world, a, .Position, Position)^, Position{1, 2})
	testing.expect_value(t, ecs.world_get_part(&world, a, .Velocity, Velocity)^, Velocity{})
	testing.expect(t, !ecs.world_has(&world, b, .Tag))
	testing.expect_value(t, len(buffer.cmds), 3)
	testing.expect_value(t, ecs.world_count_cmds(&world), 0)
}

@(test)
apply_buffer_replays_into_many_worlds :: proc(t: ^testing.T) {
	first, second: World
	make_world(&first)
	defer ecs.world_destroy(&first)
	make_world(&second)
	defer ecs.world_destroy(&second)
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer)
	defer ecs.cmd_buffer_destroy(&buffer)

	// Worlds spawned the same way hand out the same things.
	thing := ecs.world_spawn(&first)
	testing.expect_value(t, ecs.world_spawn(&second), thing)

	position := Position{1, 2}
	ecs.cmd_buffer_record_set_value(&buffer, thing, .Position, &position, size_of(Position))

	ecs.world_apply_buffer(&first, &buffer)
	ecs.world_apply_buffer(&second, &buffer)

	testing.expect_value(t, ecs.world_get_part(&first, thing, .Position, Position)^, Position{1, 2})
	testing.expect_value(t, ecs.world_get_part(&second, thing, .Position, Position)^, Position{1, 2})
}

@(test)
apply_buffer_leaves_own_cmds_pending :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer)
	defer ecs.cmd_buffer_destroy(&buffer)

	thing := ecs.world_spawn(&world)
	ecs.world_add_later(&world, thing, .Tag)
	ecs.cmd_buffer_record_set_zero(&buffer, thing, .Position)

	ecs.world_apply_buffer(&world, &buffer)

	testing.expect(t, ecs.world_has(&world, thing, .Position))
	testing.expect(t, !ecs.world_has(&world, thing, .Tag))
	testing.expect_value(t, ecs.world_count_cmds(&world), 1)
}

// >------------------------------------------------------------------ Resources

@(test)
register_resource_and_get :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	testing.expect(t, !ecs.world_is_resource_registered(&world, .Time))
	ecs.world_register_resource(&world, .Time, Time)
	testing.expect(t, ecs.world_is_resource_registered(&world, .Time))

	time := ecs.world_get_resource(&world, .Time, Time)
	testing.expect_value(t, time^, Time{})

	time.delta = 0.5
	testing.expect_value(t, ecs.world_get_resource(&world, .Time, Time)^, Time{0.5, 0})
}

@(test)
reset_zeroes_resources_keeps_registrations :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	ecs.world_register_resource(&world, .Time, Time, count_destroyed_time)
	ecs.world_register_resource(&world, .Gravity, f32)
	ecs.world_get_resource(&world, .Time, Time)^ = {1, 2}
	ecs.world_get_resource(&world, .Gravity, f32)^ = 9.81

	destroyed_resources = {}
	ecs.world_reset(&world)

	testing.expect_value(t, destroyed_resources[.Time], 1)
	testing.expect(t, ecs.world_is_resource_registered(&world, .Time))
	testing.expect(t, ecs.world_is_resource_registered(&world, .Gravity))
	testing.expect_value(t, ecs.world_get_resource(&world, .Time, Time)^, Time{})
	testing.expect_value(t, ecs.world_get_resource(&world, .Gravity, f32)^, 0)
}

@(test)
destroy_runs_resource_destroy_fns :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	ecs.world_register_resource(&world, .Time, Time, count_destroyed_time)

	destroyed_resources = {}
	ecs.world_destroy(&world)

	testing.expect_value(t, destroyed_resources[.Time], 1)
}

// >-------------------------------------------------------------------- Systems

// The thing the command systems below work on.
@(private = "file", thread_local)
system_target: ecs.Thing

@(private = "file")
tag_later_system :: proc(stuff: Stuff) {
	append(&system_log, 10)
	ecs.add_later(stuff, system_target, .Tag)
}

@(private = "file")
check_tag_system :: proc(stuff: Stuff) {
	append(&system_log, ecs.has(stuff, system_target, .Tag) ? 11 : 12)
}

@(test)
run_goes_through_stages_in_order :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	// Scheduled out of stage order on purpose.
	ecs.world_schedule(&world, system_c, .Render, {}, {})
	ecs.world_schedule(&world, system_a, .Update, {}, {.Position})
	ecs.world_schedule(&world, system_b, .Update, {.Position}, {})
	testing.expect_value(t, ecs.world_count_systems(&world), 3)

	clear(&system_log)
	ecs.world_run_sync(&world)

	testing.expect_value(t, len(system_log), 3)
	testing.expect(t, system_log_index(0) < system_log_index(1))
	testing.expect(t, system_log_index(1) < system_log_index(2))
}

@(test)
run_stage_runs_only_that_stage :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	ecs.world_schedule(&world, system_a, .Update, {}, {})
	ecs.world_schedule(&world, system_b, .Render, {}, {})

	clear(&system_log)
	ecs.world_run_stage_sync(&world, .Render)

	testing.expect_value(t, len(system_log), 1)
	testing.expect_value(t, system_log_count(1), 1)
}

@(test)
run_stage_applies_cmds_after_the_stage :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	system_target = ecs.world_spawn(&world)
	ecs.world_schedule(&world, tag_later_system, .Update, {}, {.Tag})
	ecs.world_schedule(&world, check_tag_system, .Update, {.Tag}, {})
	ecs.world_schedule(&world, check_tag_system, .Render, {.Tag}, {})

	clear(&system_log)
	ecs.world_run_sync(&world)

	// Not applied yet within Update, applied by the time Render runs.
	testing.expect_value(t, len(system_log), 3)
	testing.expect_value(t, system_log_count(10), 1)
	testing.expect_value(t, system_log_count(11), 1)
	testing.expect_value(t, system_log_count(12), 1)
	testing.expect(t, system_log_index(12) < system_log_index(11))
	testing.expect_value(t, ecs.world_count_cmds(&world), 0)
	testing.expect(t, ecs.world_has(&world, system_target, .Tag))
}

@(test)
schedule_after_run_rebuilds_the_graph :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	ecs.world_schedule(&world, system_a, .Update, {}, {.Position})
	ecs.world_run_sync(&world)

	ecs.world_schedule(&world, system_b, .Update, {.Position}, {})
	clear(&system_log)
	ecs.world_run_sync(&world)

	testing.expect_value(t, len(system_log), 2)
	testing.expect(t, system_log_index(0) < system_log_index(1))
}

@(test)
reset_keeps_scheduled_systems :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	ecs.world_schedule(&world, system_a, .Update, {}, {})
	ecs.world_reset(&world)
	testing.expect_value(t, ecs.world_count_systems(&world), 1)

	clear(&system_log)
	ecs.world_run_sync(&world)
	testing.expect_value(t, system_log_count(0), 1)
}

// >-------------------------------------------------------------------- Asserts

@(test)
set_later_wrong_type_asserts_when_recording :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(&world, ecs.THING_POOL_MIN_CAPACITY, 64, mem.arena_allocator(&arena))
	ecs.world_register(&world, .Target, Position)
	thing := ecs.world_spawn(&world)

	testing.expect_assert_message(t, "Part kind Target is a Position, not a Velocity.")
	ecs.set_later(&world, thing, .Target, Velocity{1, 2})
	testing.fail_now(t, "The call did not assert.")
}

@(test)
get_resource_wrong_type_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(&world, ecs.THING_POOL_MIN_CAPACITY, 64, mem.arena_allocator(&arena))
	ecs.world_register_resource(&world, .Gravity, f32)

	testing.expect_assert_message(t, "Resource Gravity is a f32, not a f64.")
	ecs.world_get_resource(&world, .Gravity, f64)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
get_resource_unregistered_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(&world, ecs.THING_POOL_MIN_CAPACITY, 64, mem.arena_allocator(&arena))

	testing.expect_assert_message(t, "Resource Time is not registered in the pool.")
	ecs.world_get_resource(&world, .Time, Time)
	testing.fail_now(t, "The call did not assert.")
}
