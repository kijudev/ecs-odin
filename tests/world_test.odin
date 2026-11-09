package ecs_tests

import "core:mem"
import "core:testing"

import ecs "../ecs"

@(private = "file")
make_world :: proc(world: ^World) {
	ecs.world_init(world, {capacity = ecs.THING_POOL_MIN_CAPACITY})
	ecs.world_register_part(world, .Position, Position)
	ecs.world_register_part(world, .Velocity, Velocity, count_destroyed)
	ecs.world_register_part(world, .Tag, Tag)
	ecs.world_register_part(world, .Target, Position)
	ecs.world_register_hierarchy(world, .Transform)
}

// >------------------------------------------------------------------ Lifecycle

@(test)
init_creates_empty_world :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	testing.expect_value(t, ecs.world_count_alive(&world), 0)
	testing.expect(t, ecs.world_is_part_registered(&world, .Position))
	testing.expect_value(t, ecs.world_count_parts(&world, .Position), 0)
}

@(test)
static_allocator_is_only_used_in_setup_and_destroy :: proc(t: ^testing.T) {
	static_track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&static_track, context.allocator)
	defer mem.tracking_allocator_destroy(&static_track)

	dynamic_track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&dynamic_track, context.allocator)
	defer mem.tracking_allocator_destroy(&dynamic_track)

	// Anything that bypasses both allocators panics.
	context.allocator = mem.panic_allocator()

	world: World
	ecs.world_init(
		&world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			static_allocator = mem.tracking_allocator(&static_track),
			dynamic_allocator = mem.tracking_allocator(&dynamic_track),
		},
	)
	ecs.world_register_part(&world, .Position, Position)
	ecs.world_register_part(&world, .Velocity, Velocity)
	ecs.world_register_stash(&world, .Time, Time)
	ecs.world_register_hierarchy(&world, .Transform)
	ecs.world_schedule(&world, system_a, "system_a", .Update, {}, {.Position})

	static_allocated := static_track.total_memory_allocated
	static_frees := static_track.total_free_count
	dynamic_allocations := dynamic_track.total_allocation_count

	// Grow the part sets, their pages and the command buffer past their first allocation, and
	// change the hierarchy.
	root := ecs.world_spawn(&world)
	for _ in 0 ..< 32 {
		thing := ecs.world_spawn(&world)
		ecs.set_now(&world, thing, .Position, Position{1, 2})
		ecs.set_later(&world, thing, .Velocity, Velocity{3, 4})
		ecs.attach_later(&world, .Transform, thing, root)
	}
	clear(&system_log)
	ecs.world_run_sync(&world)
	ecs.world_apply(&world)
	ecs.world_rebuild_hierarchies(&world)
	testing.expect_value(t, ecs.world_count_parts(&world, .Velocity), 32)
	testing.expect_value(t, len(ecs.get_hierarchy_order(&world, .Transform)), 33)

	testing.expect_value(t, static_track.total_memory_allocated, static_allocated)
	testing.expect_value(t, static_track.total_free_count, static_frees)
	testing.expect(t, dynamic_track.total_allocation_count > dynamic_allocations)

	ecs.world_destroy(&world)
	testing.expect_value(t, len(static_track.allocation_map), 0)
	testing.expect_value(t, len(static_track.bad_free_array), 0)
	testing.expect_value(t, len(dynamic_track.allocation_map), 0)
	testing.expect_value(t, len(dynamic_track.bad_free_array), 0)
}

@(test)
init_fills_zero_params_with_defaults :: proc(t: ^testing.T) {
	world: World
	ecs.world_init(&world, {system_capacity = 8})
	defer ecs.world_destroy(&world)

	testing.expect_value(t, len(world.thing_pool.slots), ecs.THING_POOL_DEFAULT_CAPACITY)
	testing.expect_value(t, len(world.archetype_pool.slots), ecs.THING_POOL_DEFAULT_CAPACITY)
	testing.expect_value(t, world.stash_pool.stashes_capacity, ecs.STASH_POOL_DEFAULT_CAPACITY)
	testing.expect_value(t, cap(world.cmd_buffer.cmds), ecs.CMD_BUFFER_DEFAULT_CAPACITY)
	testing.expect_value(t, cap(world.cmd_buffer.parts), ecs.CMD_BUFFER_DEFAULT_PARTS_CAPACITY)
	testing.expect(t, world.thing_pool.allocator == context.allocator)
	testing.expect(t, world.part_pool.allocator == context.allocator)

	// A field that is set is kept.
	testing.expect_value(t, world.system_pool.capacity, 8)
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
	testing.expect(t, ecs.world_is_part_registered(&world, .Position))

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
	expect_part(t, &world, thing, .Position, Position{1, 2})
	_, has_velocity := ecs.world_get_part(&world, thing, .Velocity, Velocity)
	testing.expect(t, !has_velocity)
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
	expect_part(t, &world, thing, .Position, Position{3, 4})
}

@(test)
kinds_can_share_a_type :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	thing := ecs.world_spawn(&world)
	ecs.set_now(&world, thing, .Position, Position{1, 2})
	ecs.set_now(&world, thing, .Target, Position{5, 6})

	expect_part(t, &world, thing, .Position, Position{1, 2})
	expect_part(t, &world, thing, .Target, Position{5, 6})

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
	expect_part(t, &world, b, .Position, Position{2, 2})

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
	expect_part(t, &world, thing, .Position, Position{})
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
		expect_part(t, &world, thing, .Position, parts[i])
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
	expect_part(t, &world, thing, .Position, Position{1, 2})
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

	expect_part(t, &world, a, .Position, Position{1, 2})
	expect_part(t, &world, b, .Position, Position{3, 4})
	expect_part(t, &world, c, .Position, Position{})
	expect_part(t, &world, d, .Position, Position{})
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
	expect_part(t, &world, thing, .Velocity, Velocity{3, 4})
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
	expect_part(t, &world, c, .Position, Position{7, 8})
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

	expect_part(t, &world, a, .Position, Position{1, 2})
	expect_part(t, &world, a, .Velocity, Velocity{})
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

	expect_part(t, &first, thing, .Position, Position{1, 2})
	expect_part(t, &second, thing, .Position, Position{1, 2})
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

// >-------------------------------------------------------------------- Stashes

@(test)
register_stash_and_get :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	testing.expect(t, !ecs.world_is_stash_registered(&world, .Time))
	ecs.world_register_stash(&world, .Time, Time)
	testing.expect(t, ecs.world_is_stash_registered(&world, .Time))

	testing.expect_value(t, ecs.world_get_stash(&world, .Time, Time), Time{})

	ecs.world_write_stash(&world, .Time, Time).delta = 0.5
	testing.expect_value(t, ecs.world_get_stash(&world, .Time, Time), Time{0.5, 0})
}

@(test)
reset_zeroes_stashes_keeps_registrations :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	ecs.world_register_stash(&world, .Time, Time, count_destroyed_time)
	ecs.world_register_stash(&world, .Gravity, f32)
	ecs.world_write_stash(&world, .Time, Time)^ = {1, 2}
	ecs.world_write_stash(&world, .Gravity, f32)^ = 9.81

	destroyed_stashes = {}
	ecs.world_reset(&world)

	testing.expect_value(t, destroyed_stashes[.Time], 1)
	testing.expect(t, ecs.world_is_stash_registered(&world, .Time))
	testing.expect(t, ecs.world_is_stash_registered(&world, .Gravity))
	testing.expect_value(t, ecs.world_get_stash(&world, .Time, Time), Time{})
	testing.expect_value(t, ecs.world_get_stash(&world, .Gravity, f32), 0)
}

@(test)
destroy_runs_stash_destroy_fns :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	ecs.world_register_stash(&world, .Time, Time, count_destroyed_time)

	destroyed_stashes = {}
	ecs.world_destroy(&world)

	testing.expect_value(t, destroyed_stashes[.Time], 1)
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
	ecs.world_schedule(&world, system_c, "system_c", .Render, {}, {})
	ecs.world_schedule(&world, system_a, "system_a", .Update, {}, {.Position})
	ecs.world_schedule(&world, system_b, "system_b", .Update, {.Position}, {})
	testing.expect_value(t, ecs.world_count_systems(&world), 3)

	clear(&system_log)
	ecs.world_run_sync(&world)

	testing.expect_value(t, len(system_log), 3)
	testing.expect(t, system_log_index(0) < system_log_index(1))
	testing.expect(t, system_log_index(1) < system_log_index(2))
}

@(test)
run_orders_systems_on_stashes :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	ecs.world_register_stash(&world, .Time, Time)

	// Without a conflict b would run first, the stash kind is the only thing ordering them.
	ecs.world_schedule(&world, system_a, "system_a", .Update, {}, {.Time})
	ecs.world_schedule(&world, system_b, "system_b", .Update, {.Time}, {})

	clear(&system_log)
	ecs.world_run_stage_sync(&world, .Update)

	testing.expect_value(t, len(system_log), 2)
	testing.expect(t, system_log_index(0) < system_log_index(1), "a before b")
}

@(test)
run_stage_runs_only_that_stage :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	ecs.world_schedule(&world, system_a, "system_a", .Update, {}, {})
	ecs.world_schedule(&world, system_b, "system_b", .Render, {}, {})

	clear(&system_log)
	ecs.world_run_stage_sync(&world, .Render)

	testing.expect_value(t, len(system_log), 1)
	testing.expect_value(t, system_log_count(1), 1)
}

@(test)
run_leaves_cmds_for_apply :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	system_target = ecs.world_spawn(&world)
	ecs.world_schedule(&world, tag_later_system, "tag_later_system", .Update, {}, {.Tag})
	ecs.world_schedule(&world, check_tag_system, "check_tag_system", .Update, {.Tag}, {})
	ecs.world_schedule(&world, check_tag_system, "check_tag_system", .Render, {.Tag}, {})

	clear(&system_log)
	ecs.world_run_sync(&world)

	// Not applied within Update nor between the stages, only by the explicit apply.
	testing.expect_value(t, len(system_log), 3)
	testing.expect_value(t, system_log_count(10), 1)
	testing.expect_value(t, system_log_count(11), 0)
	testing.expect_value(t, system_log_count(12), 2)
	testing.expect_value(t, ecs.world_count_cmds(&world), 1)
	testing.expect(t, !ecs.world_has(&world, system_target, .Tag))

	ecs.world_apply(&world)
	testing.expect_value(t, ecs.world_count_cmds(&world), 0)
	testing.expect(t, ecs.world_has(&world, system_target, .Tag))
}

@(test)
schedule_after_run_rebuilds_the_graph :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	ecs.world_schedule(&world, system_a, "system_a", .Update, {}, {.Position})
	ecs.world_run_sync(&world)

	ecs.world_schedule(&world, system_b, "system_b", .Update, {.Position}, {})
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

	ecs.world_schedule(&world, system_a, "system_a", .Update, {}, {})
	ecs.world_reset(&world)
	testing.expect_value(t, ecs.world_count_systems(&world), 1)

	clear(&system_log)
	ecs.world_run_sync(&world)
	testing.expect_value(t, system_log_count(0), 1)
}

// >------------------------------------------------------------------ Hierarchy

@(private = "file")
expect_things :: proc(
	t: ^testing.T,
	got: []ecs.Thing,
	want: []ecs.Thing,
	loc := #caller_location,
) {
	if !testing.expect_value(t, len(got), len(want), loc) do return
	for thing, i in got do testing.expect_value(t, thing, want[i], loc)
}

@(private = "file")
collect_iter :: proc(it: ^ecs.Hierarchy_Children_Iter, buffer: []ecs.Thing) -> []ecs.Thing {
	n := 0
	for thing in ecs.hierarchy_children_iter(it) {
		buffer[n] = thing
		n += 1
	}
	return buffer[:n]
}

@(test)
attach_now_links_live_things :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a, b, c := ecs.spawn(&world), ecs.spawn(&world), ecs.spawn(&world)
	testing.expect(t, ecs.attach_now(&world, .Transform, b, a))
	testing.expect(t, ecs.attach_now(&world, .Transform, c, a))

	testing.expect_value(t, ecs.get_parent(&world, .Transform, b), a)
	testing.expect_value(t, ecs.get_parent(&world, .Transform, a), ecs.THING_NIL)
	testing.expect_value(t, ecs.get_first_child(&world, .Transform, a), b)
	testing.expect_value(t, ecs.get_next_sibling(&world, .Transform, b), c)
	testing.expect_value(t, ecs.get_next_sibling(&world, .Transform, c), ecs.THING_NIL)

	buffer: [4]ecs.Thing
	children := ecs.iter_children(&world, .Transform, a)
	expect_things(t, collect_iter(&children, buffer[:]), {b, c})
	roots := ecs.iter_roots(&world, .Transform)
	expect_things(t, collect_iter(&roots, buffer[:]), {a})
}

@(test)
attach_now_dead_thing_returns_false :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a, b := ecs.spawn(&world), ecs.spawn(&world)
	ecs.kill_now(&world, b)

	testing.expect(t, !ecs.attach_now(&world, .Transform, b, a))
	testing.expect(t, !ecs.attach_now(&world, .Transform, a, b))
	testing.expect(t, !ecs.attach_now(&world, .Transform, ecs.THING_NIL, a))
	testing.expect_value(t, ecs.get_first_child(&world, .Transform, a), ecs.THING_NIL)
	testing.expect(t, !ecs.world_is_hierarchy_dirty(&world, .Transform))
}

@(test)
detach_now_prunes_lonely_things :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a, b, c := ecs.spawn(&world), ecs.spawn(&world), ecs.spawn(&world)
	ecs.attach_now(&world, .Transform, b, a)
	ecs.attach_now(&world, .Transform, c, b)

	// b keeps c, so it becomes a root. a has no children left, so it drops out.
	testing.expect(t, ecs.detach_now(&world, .Transform, b))
	testing.expect(t, !ecs.detach_now(&world, .Transform, b))
	testing.expect_value(t, ecs.get_parent(&world, .Transform, b), ecs.THING_NIL)
	testing.expect_value(t, ecs.get_first_child(&world, .Transform, b), c)

	buffer: [4]ecs.Thing
	roots := ecs.iter_roots(&world, .Transform)
	expect_things(t, collect_iter(&roots, buffer[:]), {b})

	ecs.kill_now(&world, a)
	testing.expect(t, !ecs.detach_now(&world, .Transform, a))
}

@(test)
kill_now_makes_children_roots :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a, b, c, d := ecs.spawn(&world), ecs.spawn(&world), ecs.spawn(&world), ecs.spawn(&world)
	ecs.attach_now(&world, .Transform, b, a)
	ecs.attach_now(&world, .Transform, c, b)
	ecs.attach_now(&world, .Transform, d, a)

	ecs.kill_now(&world, a)
	ecs.world_rebuild_hierarchy(&world, .Transform)

	testing.expect(t, ecs.is_alive(&world, b))
	testing.expect(t, ecs.is_alive(&world, d))
	testing.expect_value(t, ecs.get_parent(&world, .Transform, b), ecs.THING_NIL)
	expect_things(t, ecs.get_hierarchy_order(&world, .Transform), {b, c})

	// The slot of a is reused, the new thing starts outside the hierarchy.
	e := ecs.spawn(&world)
	testing.expect_value(t, e.idx, a.idx)
	testing.expect_value(t, ecs.get_first_child(&world, .Transform, e), ecs.THING_NIL)
	testing.expect(t, ecs.attach_now(&world, .Transform, e, c))
}

@(test)
kill_tree_now_kills_descendants :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a, b, c, d, e :=
		ecs.spawn(&world),
		ecs.spawn(&world),
		ecs.spawn(&world),
		ecs.spawn(&world),
		ecs.spawn(&world)
	ecs.attach_now(&world, .Transform, b, a)
	ecs.attach_now(&world, .Transform, c, b)
	ecs.attach_now(&world, .Transform, d, b)
	ecs.attach_now(&world, .Transform, e, a)
	for thing in ([]ecs.Thing{a, b, c, d, e}) do ecs.set_now(&world, thing, .Velocity, Velocity{})

	destroyed_count = 0
	testing.expect(t, ecs.kill_tree_now(&world, .Transform, b))
	ecs.world_rebuild_hierarchy(&world, .Transform)

	for thing in ([]ecs.Thing{b, c, d}) do testing.expect(t, !ecs.is_alive(&world, thing))
	testing.expect_value(t, ecs.count_alive(&world), 2)
	testing.expect_value(t, ecs.count_parts(&world, .Velocity), 2)
	testing.expect_value(t, destroyed_count, 3)
	expect_things(t, ecs.get_hierarchy_order(&world, .Transform), {a, e})

	testing.expect(t, !ecs.kill_tree_now(&world, .Transform, b))
}

@(test)
kill_tree_now_kills_a_deep_subtree_only :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	//   a
	//   ├─ b
	//   │  ├─ c
	//   │  │  ├─ d
	//   │  │  └─ e
	//   │  └─ f
	//   └─ g
	things: [7]ecs.Thing
	for &thing in things do thing = ecs.spawn(&world)
	a, b, c, d, e, f, g :=
		things[0], things[1], things[2], things[3], things[4], things[5], things[6]
	ecs.attach_now(&world, .Transform, b, a)
	ecs.attach_now(&world, .Transform, c, b)
	ecs.attach_now(&world, .Transform, d, c)
	ecs.attach_now(&world, .Transform, e, c)
	ecs.attach_now(&world, .Transform, f, b)
	ecs.attach_now(&world, .Transform, g, a)

	testing.expect(t, ecs.kill_tree_now(&world, .Transform, b))
	ecs.world_rebuild_hierarchy(&world, .Transform)

	for thing in ([]ecs.Thing{b, c, d, e, f}) do testing.expect(t, !ecs.is_alive(&world, thing))
	testing.expect_value(t, ecs.count_alive(&world), 2)
	expect_things(t, ecs.get_hierarchy_order(&world, .Transform), {a, g})
}

@(test)
kill_tree_now_without_hierarchy_kills_the_thing :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a, b := ecs.spawn(&world), ecs.spawn(&world)
	testing.expect(t, ecs.kill_tree_now(&world, .Transform, a))

	testing.expect(t, !ecs.is_alive(&world, a))
	testing.expect(t, ecs.is_alive(&world, b))
}

@(test)
rebuild_hierarchy_is_explicit :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a, b, c, d := ecs.spawn(&world), ecs.spawn(&world), ecs.spawn(&world), ecs.spawn(&world)
	ecs.attach_now(&world, .Transform, b, a)
	ecs.attach_now(&world, .Transform, c, b)
	ecs.attach_now(&world, .Transform, d, a)

	testing.expect(t, ecs.world_is_hierarchy_dirty(&world, .Transform))
	testing.expect_value(t, len(ecs.get_hierarchy_order(&world, .Transform)), 0)
	testing.expect(t, ecs.get_subtree(&world, .Transform, a) == nil)
	testing.expect(t, !ecs.is_ancestor(&world, .Transform, a, c))

	ecs.world_rebuild_hierarchy(&world, .Transform)

	testing.expect(t, !ecs.world_is_hierarchy_dirty(&world, .Transform))
	expect_things(t, ecs.get_hierarchy_order(&world, .Transform), {a, b, c, d})
	expect_things(t, ecs.get_subtree(&world, .Transform, b), {b, c})

	depths := ecs.get_hierarchy_depths(&world, .Transform)
	ends := ecs.get_hierarchy_ends(&world, .Transform)
	want_depths := []ecs.Hierarchy_Depth{0, 1, 2, 1}
	want_ends := []ecs.Hierarchy_Pos{4, 3, 3, 4}
	if testing.expect_value(t, len(depths), 4) && testing.expect_value(t, len(ends), 4) {
		for i in 0 ..< 4 {
			testing.expect_value(t, depths[i], want_depths[i])
			testing.expect_value(t, ends[i], want_ends[i])
		}
	}

	testing.expect(t, ecs.is_ancestor(&world, .Transform, a, c))
	testing.expect(t, !ecs.is_ancestor(&world, .Transform, b, d))
}

@(test)
hierarchy_reads_skip_things_killed_since_rebuild :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a, b := ecs.spawn(&world), ecs.spawn(&world)
	ecs.attach_now(&world, .Transform, b, a)
	ecs.world_rebuild_hierarchy(&world, .Transform)
	ecs.kill_now(&world, b)

	// The order is stale until the next rebuild, the per-thing reads check liveness.
	expect_things(t, ecs.get_hierarchy_order(&world, .Transform), {a, b})
	testing.expect(t, ecs.get_subtree(&world, .Transform, b) == nil)
	testing.expect(t, !ecs.is_ancestor(&world, .Transform, a, b))
	testing.expect_value(t, ecs.get_parent(&world, .Transform, b), ecs.THING_NIL)

	buffer: [4]ecs.Thing
	children := ecs.iter_children(&world, .Transform, b)
	testing.expect_value(t, len(collect_iter(&children, buffer[:])), 0)
}

@(test)
hierarchy_ignores_stale_things :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a, b := ecs.spawn(&world), ecs.spawn(&world)
	ecs.kill_now(&world, b)

	// e reuses the slot of b with a newer gen and is linked, so b must never reach the pool.
	e, x := ecs.spawn(&world), ecs.spawn(&world)
	testing.expect_value(t, e.idx, b.idx)
	ecs.attach_now(&world, .Transform, x, e)
	ecs.attach_now(&world, .Transform, e, a)
	ecs.world_rebuild_hierarchy(&world, .Transform)

	testing.expect_value(t, ecs.get_parent(&world, .Transform, b), ecs.THING_NIL)
	testing.expect_value(t, ecs.get_first_child(&world, .Transform, b), ecs.THING_NIL)
	testing.expect_value(t, ecs.get_next_sibling(&world, .Transform, b), ecs.THING_NIL)
	testing.expect(t, ecs.get_subtree(&world, .Transform, b) == nil)
	testing.expect(t, !ecs.is_ancestor(&world, .Transform, b, x))
	testing.expect(t, !ecs.is_ancestor(&world, .Transform, a, b))
	testing.expect(t, !ecs.detach_now(&world, .Transform, b))
	testing.expect(t, !ecs.attach_now(&world, .Transform, b, a))
	testing.expect(t, !ecs.kill_tree_now(&world, .Transform, b))

	buffer: [4]ecs.Thing
	children := ecs.iter_children(&world, .Transform, b)
	testing.expect_value(t, len(collect_iter(&children, buffer[:])), 0)

	ecs.attach_later(&world, .Transform, b, a)
	ecs.detach_later(&world, .Transform, b)
	ecs.kill_tree_later(&world, .Transform, b)
	ecs.world_apply(&world)

	testing.expect(t, ecs.is_alive(&world, e))
	testing.expect_value(t, ecs.get_parent(&world, .Transform, e), a)
}

@(test)
hierarchy_later_cmds_wait_for_apply :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a, b, c, d := ecs.spawn(&world), ecs.spawn(&world), ecs.spawn(&world), ecs.spawn(&world)
	ecs.attach_later(&world, .Transform, b, a)
	ecs.attach_later(&world, .Transform, c, b)
	ecs.attach_later(&world, .Transform, d, a)
	ecs.detach_later(&world, .Transform, d)
	ecs.attach_later(&world, .Transform, ecs.THING_NIL, a)
	ecs.attach_later(&world, .Transform, a, ecs.THING_NIL)
	ecs.detach_later(&world, .Transform, ecs.THING_NIL)
	ecs.kill_tree_later(&world, .Transform, ecs.THING_NIL)

	testing.expect_value(t, ecs.world_count_cmds(&world), 4)
	testing.expect_value(t, ecs.get_parent(&world, .Transform, b), ecs.THING_NIL)

	ecs.world_apply(&world)

	testing.expect_value(t, ecs.get_parent(&world, .Transform, b), a)
	testing.expect_value(t, ecs.get_parent(&world, .Transform, c), b)
	testing.expect_value(t, ecs.get_parent(&world, .Transform, d), ecs.THING_NIL)

	// The tree is collected on apply, so a child attached after recording is killed too.
	ecs.kill_tree_later(&world, .Transform, b)
	ecs.attach_now(&world, .Transform, d, c)
	ecs.world_apply(&world)

	for thing in ([]ecs.Thing{b, c, d}) do testing.expect(t, !ecs.is_alive(&world, thing))
	testing.expect(t, ecs.is_alive(&world, a))
}

@(test)
attach_later_skips_cycles_and_dead_things :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a, b, c := ecs.spawn(&world), ecs.spawn(&world), ecs.spawn(&world)

	// Both are fine when recorded, the second one would close a cycle when applied.
	ecs.attach_later(&world, .Transform, a, b)
	ecs.attach_later(&world, .Transform, b, a)
	ecs.attach_later(&world, .Transform, c, a)
	ecs.attach_later(&world, .Transform, a, c)
	ecs.world_apply(&world)

	testing.expect_value(t, ecs.get_parent(&world, .Transform, a), b)
	testing.expect_value(t, ecs.get_parent(&world, .Transform, b), ecs.THING_NIL)
	testing.expect_value(t, ecs.get_parent(&world, .Transform, c), a)

	ecs.attach_later(&world, .Transform, c, b)
	ecs.detach_later(&world, .Transform, a)
	ecs.kill_now(&world, c)
	ecs.kill_now(&world, a)
	ecs.world_apply(&world)

	testing.expect_value(t, ecs.get_first_child(&world, .Transform, b), ecs.THING_NIL)
}

@(test)
reset_clears_hierarchy :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	a, b := ecs.spawn(&world), ecs.spawn(&world)
	ecs.attach_now(&world, .Transform, b, a)
	ecs.world_rebuild_hierarchy(&world, .Transform)
	ecs.world_reset(&world)

	testing.expect_value(t, len(ecs.get_hierarchy_order(&world, .Transform)), 0)
	testing.expect(t, !ecs.world_is_hierarchy_dirty(&world, .Transform))

	// Same slots and gens as before the reset, but nothing is linked.
	c, d := ecs.spawn(&world), ecs.spawn(&world)
	testing.expect_value(t, ecs.get_first_child(&world, .Transform, c), ecs.THING_NIL)
	testing.expect(t, ecs.attach_now(&world, .Transform, c, d))
}

@(test)
hierarchies_of_different_kinds_are_independent :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	ecs.world_register_hierarchy(&world, .Inside)

	a, b, c := ecs.spawn(&world), ecs.spawn(&world), ecs.spawn(&world)
	ecs.attach_now(&world, .Transform, b, a)
	ecs.attach_now(&world, .Inside, a, b)
	ecs.attach_now(&world, .Inside, c, b)

	testing.expect_value(t, ecs.get_parent(&world, .Transform, b), a)
	testing.expect_value(t, ecs.get_parent(&world, .Inside, b), ecs.THING_NIL)
	testing.expect_value(t, ecs.get_parent(&world, .Inside, a), b)
	testing.expect_value(t, ecs.get_parent(&world, .Transform, c), ecs.THING_NIL)

	// Only the dirty hierarchy is rebuilt.
	ecs.world_rebuild_hierarchy(&world, .Transform)
	ecs.detach_now(&world, .Transform, b)
	testing.expect(t, ecs.world_is_hierarchy_dirty(&world, .Transform))
	testing.expect(t, ecs.world_is_hierarchy_dirty(&world, .Inside))
	expect_things(t, ecs.get_hierarchy_order(&world, .Transform), {a, b})

	ecs.world_rebuild_hierarchies(&world)
	testing.expect(t, !ecs.world_is_hierarchy_dirty(&world, .Transform))
	testing.expect(t, !ecs.world_is_hierarchy_dirty(&world, .Inside))
	testing.expect_value(t, len(ecs.get_hierarchy_order(&world, .Transform)), 0)
	expect_things(t, ecs.get_hierarchy_order(&world, .Inside), {b, a, c})
}

@(test)
kill_now_leaves_every_hierarchy :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	ecs.world_register_hierarchy(&world, .Inside)

	a, b, c, d := ecs.spawn(&world), ecs.spawn(&world), ecs.spawn(&world), ecs.spawn(&world)
	ecs.attach_now(&world, .Transform, b, a)
	ecs.attach_now(&world, .Transform, c, b)
	ecs.attach_now(&world, .Inside, d, b)
	ecs.attach_now(&world, .Inside, a, d)

	ecs.kill_now(&world, b)
	ecs.world_rebuild_hierarchies(&world)

	testing.expect_value(t, ecs.get_parent(&world, .Transform, c), ecs.THING_NIL)
	testing.expect_value(t, ecs.get_first_child(&world, .Transform, a), ecs.THING_NIL)
	testing.expect_value(t, ecs.get_parent(&world, .Inside, d), ecs.THING_NIL)
	testing.expect_value(t, len(ecs.get_hierarchy_order(&world, .Transform)), 0)
	expect_things(t, ecs.get_hierarchy_order(&world, .Inside), {d, a})
}

@(test)
kill_tree_now_follows_one_hierarchy :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	ecs.world_register_hierarchy(&world, .Inside)

	a, b, c, d := ecs.spawn(&world), ecs.spawn(&world), ecs.spawn(&world), ecs.spawn(&world)
	ecs.attach_now(&world, .Transform, b, a)
	ecs.attach_now(&world, .Inside, c, a)
	ecs.attach_now(&world, .Inside, d, c)

	ecs.kill_tree_now(&world, .Transform, a)

	// Only the Transform subtree dies, c becomes an Inside root and keeps d.
	testing.expect(t, !ecs.is_alive(&world, a))
	testing.expect(t, !ecs.is_alive(&world, b))
	testing.expect(t, ecs.is_alive(&world, c))
	testing.expect(t, ecs.is_alive(&world, d))
	testing.expect_value(t, ecs.get_parent(&world, .Inside, c), ecs.THING_NIL)
	testing.expect_value(t, ecs.get_parent(&world, .Inside, d), c)
}

@(private = "file")
hierarchy_order_system_a :: proc(stuff: Stuff) {
	append(&system_log, 30)
	ecs.attach_now(stuff, .Transform, hierarchy_things[1], hierarchy_things[0])
}

@(private = "file")
hierarchy_order_system_b :: proc(stuff: Stuff) {
	parent := ecs.get_parent(stuff, .Transform, hierarchy_things[1])
	append(&system_log, parent == hierarchy_things[0] ? 31 : 32)
}

@(test)
run_orders_systems_on_hierarchies :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	hierarchy_things[0] = ecs.spawn(&world)
	hierarchy_things[1] = ecs.spawn(&world)

	// Without a conflict b would run first, the hierarchy kind is the only thing ordering them.
	ecs.world_schedule(
		&world,
		hierarchy_order_system_a,
		"hierarchy_order_system_a",
		.Update,
		{},
		{.Transform},
	)
	ecs.world_schedule(
		&world,
		hierarchy_order_system_b,
		"hierarchy_order_system_b",
		.Update,
		{.Transform},
		{},
	)

	clear(&system_log)
	ecs.world_run_stage_sync(&world, .Update)

	if testing.expect_value(t, len(system_log), 2) {
		testing.expect_value(t, system_log[0], 30)
		testing.expect_value(t, system_log[1], 31)
	}
}

// The things the hierarchy systems below work on.
@(private = "file", thread_local)
hierarchy_things: [4]ecs.Thing

@(private = "file")
hierarchy_system :: proc(stuff: Stuff) {
	a, b, c, d :=
		hierarchy_things[0], hierarchy_things[1], hierarchy_things[2], hierarchy_things[3]

	ecs.attach_now(stuff, .Transform, b, a)
	ecs.attach_later(stuff, .Transform, c, a)
	ecs.attach_now(stuff, .Transform, d, b)
	ecs.detach_now(stuff, .Transform, d)
	ecs.detach_later(stuff, .Transform, b)
	ecs.kill_tree_later(stuff, .Transform, c)
	ecs.kill_tree_now(stuff, .Transform, ecs.spawn(stuff))

	if ecs.get_parent(stuff, .Transform, b) == a do append(&system_log, 20)
	if ecs.get_first_child(stuff, .Transform, a) == b do append(&system_log, 21)
	if ecs.get_next_sibling(stuff, .Transform, b) == ecs.THING_NIL do append(&system_log, 22)

	children := ecs.iter_children(stuff, .Transform, a)
	for _ in ecs.hierarchy_children_iter(&children) do append(&system_log, 23)
	roots := ecs.iter_roots(stuff, .Transform)
	for _ in ecs.hierarchy_children_iter(&roots) do append(&system_log, 24)

	// Reads the order of the rebuild before the stage.
	if ecs.is_ancestor(stuff, .Transform, b, c) do append(&system_log, 25)
	if len(ecs.get_hierarchy_order(stuff, .Transform)) == 2 do append(&system_log, 26)
	if len(ecs.get_hierarchy_depths(stuff, .Transform)) == 2 do append(&system_log, 27)
	if len(ecs.get_hierarchy_ends(stuff, .Transform)) == 2 do append(&system_log, 28)
	if len(ecs.get_subtree(stuff, .Transform, b)) == 2 do append(&system_log, 29)
}

@(test)
systems_reach_the_hierarchy_through_stuff :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)

	for &thing in hierarchy_things do thing = ecs.spawn(&world)
	a, b, c := hierarchy_things[0], hierarchy_things[1], hierarchy_things[2]
	ecs.attach_now(&world, .Transform, c, b)
	ecs.world_rebuild_hierarchy(&world, .Transform)

	ecs.world_schedule(&world, hierarchy_system, "hierarchy_system", .Update, {}, {.Transform})
	clear(&system_log)
	ecs.world_run_sync(&world)

	want := []int{20, 21, 22, 23, 24, 25, 26, 27, 28, 29}
	if testing.expect_value(t, len(system_log), len(want)) {
		for id, i in system_log do testing.expect_value(t, id, want[i])
	}

	// The recorded attach, detach and kill_tree only land on apply.
	testing.expect_value(t, ecs.world_count_cmds(&world), 3)
	ecs.world_apply(&world)
	testing.expect(t, !ecs.is_alive(&world, c))
	testing.expect_value(t, ecs.get_parent(&world, .Transform, b), ecs.THING_NIL)
	testing.expect_value(t, ecs.get_first_child(&world, .Transform, a), ecs.THING_NIL)
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
	ecs.world_init(
		&world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = mem.arena_allocator(&arena),
			dynamic_allocator = mem.arena_allocator(&arena),
		},
	)
	ecs.world_register_part(&world, .Target, Position)
	thing := ecs.world_spawn(&world)

	testing.expect_assert_message(t, "Part kind Target is a Position, not a Velocity.")
	ecs.set_later(&world, thing, .Target, Velocity{1, 2})
	testing.fail_now(t, "The call did not assert.")
}

@(test)
get_stash_wrong_type_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(
		&world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = mem.arena_allocator(&arena),
			dynamic_allocator = mem.arena_allocator(&arena),
		},
	)
	ecs.world_register_stash(&world, .Gravity, f32)

	testing.expect_assert_message(t, "Stash kind Gravity is a f32, not a f64.")
	ecs.world_get_stash(&world, .Gravity, f64)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
get_stash_unregistered_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(
		&world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = mem.arena_allocator(&arena),
			dynamic_allocator = mem.arena_allocator(&arena),
		},
	)

	testing.expect_assert_message(t, "Stash kind Time is not registered.")
	ecs.world_get_stash(&world, .Time, Time)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
register_stash_kind_as_part_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(
		&world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = mem.arena_allocator(&arena),
			dynamic_allocator = mem.arena_allocator(&arena),
		},
	)
	ecs.world_register_stash(&world, .Time, Time)

	testing.expect_assert_message(t, "Kind Time is already registered as a stash.")
	ecs.world_register_part(&world, .Time, Time)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
register_part_kind_as_stash_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(
		&world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = mem.arena_allocator(&arena),
			dynamic_allocator = mem.arena_allocator(&arena),
		},
	)
	ecs.world_register_part(&world, .Position, Position)

	testing.expect_assert_message(t, "Kind Position is already registered as a part.")
	ecs.world_register_stash(&world, .Position, Position)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
attach_now_to_descendant_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(
		&world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = mem.arena_allocator(&arena),
			dynamic_allocator = mem.arena_allocator(&arena),
		},
	)
	ecs.world_register_hierarchy(&world, .Transform)
	a, b := ecs.world_spawn(&world), ecs.world_spawn(&world)
	ecs.attach_now(&world, .Transform, b, a)

	testing.expect_assert_message(t, "Hierarchy thing 1 can't be attached to its descendant 2.")
	ecs.attach_now(&world, .Transform, a, b)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
attach_later_to_self_asserts_when_recording :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(
		&world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = mem.arena_allocator(&arena),
			dynamic_allocator = mem.arena_allocator(&arena),
		},
	)
	ecs.world_register_hierarchy(&world, .Transform)
	a := ecs.world_spawn(&world)

	testing.expect_assert_message(t, "Hierarchy thing 1 can't be attached to itself.")
	ecs.attach_later(&world, .Transform, a, a)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
register_hierarchy_twice_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(
		&world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = mem.arena_allocator(&arena),
			dynamic_allocator = mem.arena_allocator(&arena),
		},
	)
	ecs.world_register_hierarchy(&world, .Transform)

	testing.expect_assert_message(t, "Hierarchy kind Transform is already registered.")
	ecs.world_register_hierarchy(&world, .Transform)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
register_hierarchy_on_part_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(
		&world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = mem.arena_allocator(&arena),
			dynamic_allocator = mem.arena_allocator(&arena),
		},
	)
	ecs.world_register_part(&world, .Position, Position)

	testing.expect_assert_message(t, "Kind Position is already registered as a part.")
	ecs.world_register_hierarchy(&world, .Position)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
register_hierarchy_on_stash_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(
		&world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = mem.arena_allocator(&arena),
			dynamic_allocator = mem.arena_allocator(&arena),
		},
	)
	ecs.world_register_stash(&world, .Time, Time)

	testing.expect_assert_message(t, "Kind Time is already registered as a stash.")
	ecs.world_register_hierarchy(&world, .Time)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
register_part_on_hierarchy_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(
		&world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = mem.arena_allocator(&arena),
			dynamic_allocator = mem.arena_allocator(&arena),
		},
	)
	ecs.world_register_hierarchy(&world, .Transform)

	testing.expect_assert_message(t, "Kind Transform is already registered as a hierarchy.")
	ecs.world_register_part(&world, .Transform, Position)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
register_stash_on_hierarchy_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(
		&world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = mem.arena_allocator(&arena),
			dynamic_allocator = mem.arena_allocator(&arena),
		},
	)
	ecs.world_register_hierarchy(&world, .Transform)

	testing.expect_assert_message(t, "Kind Transform is already registered as a hierarchy.")
	ecs.world_register_stash(&world, .Transform, Time)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_now_unregistered_kind_asserts_for_dead_thing :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(
		&world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = mem.arena_allocator(&arena),
			dynamic_allocator = mem.arena_allocator(&arena),
		},
	)
	thing := ecs.world_spawn(&world)
	ecs.world_kill_now(&world, thing)

	// Asserts before checking liveness, so a dead thing doesn't hide the misuse.
	testing.expect_assert_message(t, "Hierarchy kind Inside is not registered.")
	ecs.get_parent(&world, .Inside, thing)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
attach_later_unregistered_kind_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(
		&world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = mem.arena_allocator(&arena),
			dynamic_allocator = mem.arena_allocator(&arena),
		},
	)
	thing := ecs.world_spawn(&world)

	testing.expect_assert_message(t, "Hierarchy kind Inside is not registered.")
	ecs.attach_later(&world, .Inside, thing, ecs.THING_NIL)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
kill_tree_later_unregistered_kind_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(
		&world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = mem.arena_allocator(&arena),
			dynamic_allocator = mem.arena_allocator(&arena),
		},
	)
	testing.expect_assert_message(t, "Hierarchy kind Inside is not registered.")
	ecs.kill_tree_later(&world, .Inside, ecs.THING_NIL)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
apply_unregistered_hierarchy_kind_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	ecs.world_init(
		&world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = mem.arena_allocator(&arena),
			dynamic_allocator = mem.arena_allocator(&arena),
		},
	)
	thing := ecs.world_spawn(&world)
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer, allocator = mem.arena_allocator(&arena))
	ecs.cmd_buffer_record_detach(&buffer, .Inside, thing)

	testing.expect_assert_message(t, "Hierarchy kind Inside is not registered.")
	ecs.world_apply_buffer(&world, &buffer)
	testing.fail_now(t, "The call did not assert.")
}
