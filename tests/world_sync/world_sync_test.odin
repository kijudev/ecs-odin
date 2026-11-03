package world_sync_tests

import "core:testing"

import ecs "../../ecs"
import world_sync "../../worlds/sync"

Position :: struct {
	x, y: f32,
}

Velocity :: struct {
	x, y: f32,
}

Tag :: struct {}

@(thread_local)
destroyed_count: int

count_destroyed :: proc(part: rawptr) {
	destroyed_count += 1
}

World_Part :: enum {
	Position,
	Velocity,
	Tag,
	Target, // shares the Position type
}

World :: world_sync.World(World_Part)

@(private = "file")
make_world :: proc(world: ^World) {
	world_sync.init(world, ecs.THING_POOL_MIN_CAPACITY)
	world_sync.register(world, .Position, Position)
	world_sync.register(world, .Velocity, Velocity, count_destroyed)
	world_sync.register(world, .Tag, Tag)
	world_sync.register(world, .Target, Position)
}

// >------------------------------------------------------------------ Lifecycle

@(test)
init_creates_empty_world :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	testing.expect_value(t, world_sync.count_alive(&world), 0)
	testing.expect(t, world_sync.is_registered(&world, .Position))
	testing.expect_value(t, world_sync.count_parts(&world, .Position), 0)
}

@(test)
destroy_destroys_parts :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	destroyed_count = 0

	vel := Velocity{1, 1}
	world_sync.set_now(&world, world_sync.spawn(&world), .Velocity, &vel)
	world_sync.set_now(&world, world_sync.spawn(&world), .Velocity, &vel)
	world_sync.destroy(&world)

	testing.expect_value(t, destroyed_count, 2)
}

@(test)
reset_kills_everything_keeps_registrations :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	thing := world_sync.spawn(&world)
	world_sync.set_now(&world, thing, .Position, &Position{1, 2})
	world_sync.reset(&world)

	testing.expect(t, !world_sync.poke(&world, thing))
	testing.expect_value(t, world_sync.count_alive(&world), 0)
	testing.expect_value(t, world_sync.count_parts(&world, .Position), 0)
	testing.expect(t, world_sync.is_registered(&world, .Position))

	// Reused idx must not inherit the old mask.
	again := world_sync.spawn(&world)
	testing.expect_value(t, again.idx, thing.idx)
	testing.expect(t, !world_sync.has(&world, again, .Position))
}

// >---------------------------------------------------------------------- Parts

@(test)
set_now_and_get_part :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	thing := world_sync.spawn(&world)
	world_sync.set_now(&world, thing, .Position, &Position{1, 2})

	testing.expect(t, world_sync.has(&world, thing, .Position))
	testing.expect(t, !world_sync.has(&world, thing, .Velocity))
	testing.expect_value(
		t,
		world_sync.get_part(&world, thing, .Position, Position)^,
		Position{1, 2},
	)
	testing.expect(t, world_sync.get_part(&world, thing, .Velocity, Velocity) == nil)
}

@(test)
set_now_overloads :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	a := world_sync.spawn(&world)
	b := world_sync.spawn(&world)
	c := world_sync.spawn(&world)
	d := world_sync.spawn(&world)

	position := Position{3, 4}
	by_value := world_sync.set_now(&world, a, .Position, Position{1, 2})
	by_pointer := world_sync.set_now(&world, b, .Position, &position)
	zeroed := world_sync.set_now(&world, c, .Position, Position)
	from_nil := world_sync.set_now(&world, d, .Position, (^Position)(nil))

	testing.expect_value(t, by_value^, Position{1, 2})
	testing.expect_value(t, by_pointer^, Position{3, 4})
	testing.expect_value(t, zeroed^, Position{})
	testing.expect_value(t, from_nil^, Position{})
	testing.expect_value(t, world_sync.count_parts(&world, .Position), 4)
}

@(test)
set_now_existing_overwrites :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	thing := world_sync.spawn(&world)
	world_sync.set_now(&world, thing, .Position, Position{1, 2})
	world_sync.set_now(&world, thing, .Position, Position{3, 4})

	testing.expect_value(t, world_sync.count_parts(&world, .Position), 1)
	testing.expect_value(
		t,
		world_sync.get_part(&world, thing, .Position, Position)^,
		Position{3, 4},
	)
}

@(test)
kinds_can_share_a_type :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	thing := world_sync.spawn(&world)
	world_sync.set_now(&world, thing, .Position, Position{1, 2})
	world_sync.set_now(&world, thing, .Target, Position{5, 6})

	testing.expect_value(
		t,
		world_sync.get_part(&world, thing, .Position, Position)^,
		Position{1, 2},
	)
	testing.expect_value(t, world_sync.get_part(&world, thing, .Target, Position)^, Position{5, 6})

	world_sync.remove_now(&world, thing, .Target)
	testing.expect(t, world_sync.has(&world, thing, .Position))
	testing.expect(t, !world_sync.has(&world, thing, .Target))
}

@(test)
remove_now_removes_part :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	thing := world_sync.spawn(&world)
	world_sync.set_now(&world, thing, .Position, &Position{1, 2})
	world_sync.set_now(&world, thing, .Tag, Tag{})

	testing.expect(t, world_sync.remove_now(&world, thing, .Position))
	testing.expect(t, !world_sync.remove_now(&world, thing, .Position))
	testing.expect(t, !world_sync.has(&world, thing, .Position))
	testing.expect(t, world_sync.has(&world, thing, .Tag))

	// Killing after a remove must not touch the removed part.
	world_sync.kill_now(&world, thing)
	testing.expect_value(t, world_sync.count_parts(&world, .Tag), 0)
}

@(test)
kill_now_removes_all_parts :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)
	destroyed_count = 0

	a := world_sync.spawn(&world)
	b := world_sync.spawn(&world)
	world_sync.set_now(&world, a, .Position, &Position{1, 1})
	world_sync.set_now(&world, a, .Velocity, &Velocity{1, 1})
	world_sync.set_now(&world, b, .Position, &Position{2, 2})

	testing.expect(t, world_sync.kill_now(&world, a))

	testing.expect(t, !world_sync.poke(&world, a))
	testing.expect_value(t, destroyed_count, 1)
	testing.expect_value(t, world_sync.count_parts(&world, .Position), 1)
	testing.expect_value(t, world_sync.count_parts(&world, .Velocity), 0)
	testing.expect_value(t, world_sync.get_part(&world, b, .Position, Position)^, Position{2, 2})

	// Reused idx starts with no parts.
	c := world_sync.spawn(&world)
	testing.expect_value(t, c.idx, a.idx)
	testing.expect(t, !world_sync.has(&world, c, .Position))
	testing.expect(t, !world_sync.has(&world, c, .Velocity))
}

@(test)
kill_now_fails_for_dead_things :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	old := world_sync.spawn(&world)
	testing.expect(t, world_sync.kill_now(&world, old))
	testing.expect(t, !world_sync.kill_now(&world, old))

	// A stale thing must not kill the thing reusing its idx.
	new := world_sync.spawn(&world)
	world_sync.set_now(&world, new, .Position, Position{1, 2})
	testing.expect(t, !world_sync.kill_now(&world, old))
	testing.expect(t, world_sync.poke(&world, new))
	testing.expect(t, world_sync.has(&world, new, .Position))

	testing.expect(t, !world_sync.kill_now(&world, ecs.THING_NIL))
}

@(test)
set_now_on_dead_thing_returns_nil :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	old := world_sync.spawn(&world)
	world_sync.kill_now(&world, old)
	new := world_sync.spawn(&world)

	testing.expect(t, world_sync.set_now(&world, old, .Position, Position{1, 2}) == nil)
	testing.expect(t, world_sync.set_now(&world, ecs.THING_NIL, .Position, Position) == nil)
	testing.expect(t, !world_sync.add_now(&world, old, .Tag))
	testing.expect_value(t, world_sync.count_parts(&world, .Position), 0)
	testing.expect_value(t, world_sync.count_parts(&world, .Tag), 0)
	testing.expect(t, !world_sync.has(&world, new, .Position))
}

@(test)
add_now_inserts_zeroed_part :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	thing := world_sync.spawn(&world)
	testing.expect(t, world_sync.add_now(&world, thing, .Tag))
	testing.expect(t, world_sync.has(&world, thing, .Tag))

	world_sync.set_now(&world, thing, .Position, Position{1, 2})
	testing.expect(t, world_sync.add_now(&world, thing, .Position))
	testing.expect_value(t, world_sync.get_part(&world, thing, .Position, Position)^, Position{})
	testing.expect_value(t, world_sync.count_parts(&world, .Position), 1)

	// Killing removes added parts like any other.
	world_sync.kill_now(&world, thing)
	testing.expect_value(t, world_sync.count_parts(&world, .Tag), 0)
}

// >--------------------------------------------------------------------- Slices

@(test)
get_parts_and_things_match_up :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	spawned: [4]ecs.Thing
	for &thing, i in spawned {
		thing = world_sync.spawn(&world)
		world_sync.set_now(&world, thing, .Position, &Position{f32(i), 0})
	}
	world_sync.kill_now(&world, spawned[1])

	parts := world_sync.get_parts(&world, .Position, Position)
	things := world_sync.get_things(&world, .Position)

	testing.expect_value(t, len(parts), 3)
	testing.expect_value(t, len(things), 3)
	for thing, i in things {
		testing.expect_value(t, world_sync.get_part(&world, thing, .Position, Position)^, parts[i])
	}
}

@(test)
get_parts_of_tags_has_length :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	world_sync.set_now(&world, world_sync.spawn(&world), .Tag, Tag{})
	world_sync.set_now(&world, world_sync.spawn(&world), .Tag, Tag{})

	testing.expect_value(t, len(world_sync.get_parts(&world, .Tag, Tag)), 2)
	testing.expect_value(t, len(world_sync.get_things(&world, .Tag)), 2)
}

// >------------------------------------------------------------------- Commands

@(test)
later_waits_for_apply_self :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	thing := world_sync.spawn(&world)
	world_sync.set_later(&world, thing, .Position, Position{1, 2})
	world_sync.add_later(&world, thing, .Tag)

	testing.expect_value(t, world_sync.count_cmds(&world), 2)
	testing.expect(t, !world_sync.has(&world, thing, .Position))
	testing.expect(t, !world_sync.has(&world, thing, .Tag))

	world_sync.apply_self(&world)

	testing.expect_value(t, world_sync.count_cmds(&world), 0)
	testing.expect_value(
		t,
		world_sync.get_part(&world, thing, .Position, Position)^,
		Position{1, 2},
	)
	testing.expect(t, world_sync.has(&world, thing, .Tag))
}

@(test)
set_later_overloads :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	a := world_sync.spawn(&world)
	b := world_sync.spawn(&world)
	c := world_sync.spawn(&world)
	d := world_sync.spawn(&world)

	position := Position{3, 4}
	world_sync.set_later(&world, a, .Position, Position{1, 2})
	world_sync.set_later(&world, b, .Position, &position)
	world_sync.set_later(&world, c, .Position, Position)
	world_sync.set_later(&world, d, .Position, (^Position)(nil))

	// The part is copied when recorded.
	position = Position{9, 9}

	world_sync.apply_self(&world)

	testing.expect_value(t, world_sync.get_part(&world, a, .Position, Position)^, Position{1, 2})
	testing.expect_value(t, world_sync.get_part(&world, b, .Position, Position)^, Position{3, 4})
	testing.expect_value(t, world_sync.get_part(&world, c, .Position, Position)^, Position{})
	testing.expect_value(t, world_sync.get_part(&world, d, .Position, Position)^, Position{})
	testing.expect_value(t, world_sync.count_parts(&world, .Position), 4)
}

@(test)
set_later_overwrites_existing :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)
	destroyed_count = 0

	thing := world_sync.spawn(&world)
	world_sync.set_now(&world, thing, .Velocity, Velocity{1, 2})
	world_sync.set_later(&world, thing, .Velocity, Velocity{3, 4})
	world_sync.apply_self(&world)

	testing.expect_value(t, destroyed_count, 1)
	testing.expect_value(t, world_sync.count_parts(&world, .Velocity), 1)
	testing.expect_value(
		t,
		world_sync.get_part(&world, thing, .Velocity, Velocity)^,
		Velocity{3, 4},
	)
}

@(test)
later_supports_zero_sized_parts :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	thing := world_sync.spawn(&world)
	world_sync.set_later(&world, thing, .Tag, Tag{})
	world_sync.apply_self(&world)

	testing.expect(t, world_sync.has(&world, thing, .Tag))
}

@(test)
remove_later_removes_part :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	thing := world_sync.spawn(&world)
	world_sync.set_now(&world, thing, .Position, Position{1, 2})
	world_sync.set_now(&world, thing, .Tag, Tag{})

	world_sync.remove_later(&world, thing, .Position)
	testing.expect(t, world_sync.has(&world, thing, .Position))

	world_sync.apply_self(&world)
	testing.expect(t, !world_sync.has(&world, thing, .Position))
	testing.expect(t, world_sync.has(&world, thing, .Tag))

	// Removing a missing part is skipped.
	world_sync.remove_later(&world, thing, .Position)
	world_sync.apply_self(&world)
	testing.expect(t, world_sync.has(&world, thing, .Tag))
}

@(test)
kill_later_kills_on_apply :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	thing := world_sync.spawn(&world)
	world_sync.set_now(&world, thing, .Position, Position{1, 2})

	world_sync.kill_later(&world, thing)
	testing.expect(t, world_sync.poke(&world, thing))

	world_sync.apply_self(&world)
	testing.expect(t, !world_sync.poke(&world, thing))
	testing.expect_value(t, world_sync.count_parts(&world, .Position), 0)
}

@(test)
apply_keeps_record_order :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	a := world_sync.spawn(&world)
	b := world_sync.spawn(&world)

	// Set then kill: the set happens, then the kill removes it.
	world_sync.set_later(&world, a, .Position, Position{1, 2})
	world_sync.kill_later(&world, a)

	// Kill then set: the set is skipped, the thing is dead by then.
	world_sync.kill_later(&world, b)
	world_sync.set_later(&world, b, .Position, Position{3, 4})

	// Set twice: the last one wins.
	c := world_sync.spawn(&world)
	world_sync.set_later(&world, c, .Position, Position{5, 6})
	world_sync.set_later(&world, c, .Position, Position{7, 8})

	world_sync.apply_self(&world)

	testing.expect(t, !world_sync.poke(&world, a))
	testing.expect(t, !world_sync.poke(&world, b))
	testing.expect_value(t, world_sync.count_parts(&world, .Position), 1)
	testing.expect_value(t, world_sync.get_part(&world, c, .Position, Position)^, Position{7, 8})
}

@(test)
later_skips_stale_and_nil_things :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	old := world_sync.spawn(&world)
	world_sync.kill_now(&world, old)
	new := world_sync.spawn(&world)

	world_sync.set_later(&world, old, .Position, Position{1, 2})
	world_sync.add_later(&world, old, .Tag)
	world_sync.kill_later(&world, old)

	// THING_NIL is never recorded.
	world_sync.set_later(&world, ecs.THING_NIL, .Position, Position{1, 2})
	world_sync.kill_later(&world, ecs.THING_NIL)
	testing.expect_value(t, world_sync.count_cmds(&world), 3)

	world_sync.apply_self(&world)

	testing.expect(t, world_sync.poke(&world, new))
	testing.expect(t, !world_sync.has(&world, new, .Position))
	testing.expect_value(t, world_sync.count_parts(&world, .Position), 0)
	testing.expect_value(t, world_sync.count_parts(&world, .Tag), 0)
}

@(test)
reset_drops_recorded_cmds :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)

	thing := world_sync.spawn(&world)
	world_sync.set_later(&world, thing, .Position, Position{1, 2})
	world_sync.reset(&world)

	testing.expect_value(t, world_sync.count_cmds(&world), 0)

	again := world_sync.spawn(&world)
	world_sync.apply_self(&world)
	testing.expect(t, !world_sync.has(&world, again, .Position))
}

@(test)
destroy_frees_recorded_cmds :: proc(t: ^testing.T) {
	world: World
	make_world(&world)

	// Leaks would be reported by the test runner's tracking allocator.
	thing := world_sync.spawn(&world)
	world_sync.set_later(&world, thing, .Position, Position{1, 2})
	world_sync.destroy(&world)
}

@(test)
apply_other_applies_and_keeps_buffer :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)
	cmds: ecs.Cmd_Pool(World_Part)
	ecs.cmd_pool_init(&cmds)
	defer ecs.cmd_pool_destroy(&cmds)

	a := world_sync.spawn(&world)
	b := world_sync.spawn(&world)
	world_sync.set_now(&world, b, .Tag, Tag{})

	position := Position{1, 2}
	ecs.cmd_pool_record_set_value(&cmds, a, .Position, &position, size_of(Position))
	ecs.cmd_pool_record_set_zero(&cmds, a, .Velocity)
	ecs.cmd_pool_record_remove(&cmds, b, .Tag)

	world_sync.apply_other(&world, &cmds)

	testing.expect_value(t, world_sync.get_part(&world, a, .Position, Position)^, Position{1, 2})
	testing.expect_value(t, world_sync.get_part(&world, a, .Velocity, Velocity)^, Velocity{})
	testing.expect(t, !world_sync.has(&world, b, .Tag))
	testing.expect_value(t, ecs.cmd_pool_count_cmds(&cmds), 3)
	testing.expect_value(t, world_sync.count_cmds(&world), 0)
}

@(test)
apply_other_replays_into_many_worlds :: proc(t: ^testing.T) {
	first, second: World
	make_world(&first)
	defer world_sync.destroy(&first)
	make_world(&second)
	defer world_sync.destroy(&second)
	cmds: ecs.Cmd_Pool(World_Part)
	ecs.cmd_pool_init(&cmds)
	defer ecs.cmd_pool_destroy(&cmds)

	// Worlds spawned the same way hand out the same things.
	thing := world_sync.spawn(&first)
	testing.expect_value(t, world_sync.spawn(&second), thing)

	position := Position{1, 2}
	ecs.cmd_pool_record_set_value(&cmds, thing, .Position, &position, size_of(Position))

	world_sync.apply_other(&first, &cmds)
	world_sync.apply_other(&second, &cmds)

	testing.expect_value(
		t,
		world_sync.get_part(&first, thing, .Position, Position)^,
		Position{1, 2},
	)
	testing.expect_value(
		t,
		world_sync.get_part(&second, thing, .Position, Position)^,
		Position{1, 2},
	)
}

@(test)
apply_other_leaves_own_cmds_pending :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer world_sync.destroy(&world)
	cmds: ecs.Cmd_Pool(World_Part)
	ecs.cmd_pool_init(&cmds)
	defer ecs.cmd_pool_destroy(&cmds)

	thing := world_sync.spawn(&world)
	world_sync.add_later(&world, thing, .Tag)
	ecs.cmd_pool_record_set_zero(&cmds, thing, .Position)

	world_sync.apply_other(&world, &cmds)

	testing.expect(t, world_sync.has(&world, thing, .Position))
	testing.expect(t, !world_sync.has(&world, thing, .Tag))
	testing.expect_value(t, world_sync.count_cmds(&world), 1)
}
