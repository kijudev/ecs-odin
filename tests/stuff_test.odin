package ecs_tests

import "core:testing"

import ecs "../ecs"

@(private = "file")
make_world :: proc(world: ^World) {
	ecs.world_init(world, ecs.THING_POOL_MIN_CAPACITY)
	ecs.register(world, .Position, Position)
	ecs.register(world, .Velocity, Velocity)
	ecs.register(world, .Tag, Tag)
	ecs.register_resource(world, .Time, Time)
}

// Every call goes through the short names with a Stuff, so this also checks that the groups
// pick the stuff procs.

// >--------------------------------------------------------------------- Things

@(test)
stuff_spawns_and_kills_in_the_world :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	stuff := ecs.stuff_make(&world)

	a := ecs.spawn(stuff)
	b := ecs.spawn(stuff)
	testing.expect(t, ecs.poke(stuff, a))
	testing.expect(t, ecs.world_poke(&world, b))
	testing.expect_value(t, ecs.count_alive(stuff), 2)

	testing.expect(t, ecs.kill_now(stuff, a))
	testing.expect(t, !ecs.kill_now(stuff, a))
	testing.expect(t, !ecs.poke(stuff, a))
	testing.expect_value(t, ecs.count_free(stuff), 1)

	ecs.kill_later(stuff, b)
	testing.expect(t, ecs.poke(stuff, b))
	ecs.world_apply_self(&world)
	testing.expect(t, !ecs.poke(stuff, b))
	testing.expect_value(t, ecs.count_alive(stuff), 0)
	testing.expect_value(t, ecs.count_free(stuff), 2)
}

// >---------------------------------------------------------------------- Parts

@(test)
stuff_now_procs_change_the_world :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	stuff := ecs.stuff_make(&world)

	thing := ecs.spawn(stuff)
	pos := ecs.set_now(stuff, thing, .Position, Position{1, 2})
	testing.expect(t, pos == ecs.world_get_part(&world, thing, .Position, Position))
	testing.expect(t, pos == ecs.get_part(stuff, thing, .Position, Position))

	vel := Velocity{3, 4}
	testing.expect_value(t, ecs.set_now(stuff, thing, .Velocity, &vel)^, vel)
	testing.expect_value(t, ecs.set_now(stuff, thing, .Velocity, Velocity)^, Velocity{})

	testing.expect(t, ecs.add_now(stuff, thing, .Tag))
	testing.expect(t, ecs.has(stuff, thing, .Tag))
	testing.expect(t, ecs.remove_now(stuff, thing, .Tag))
	testing.expect(t, !ecs.world_has(&world, thing, .Tag))

	testing.expect_value(t, ecs.count_parts(stuff, .Position), 1)
	testing.expect_value(t, len(ecs.get_parts(stuff, .Position, Position)), 1)
	testing.expect_value(t, ecs.get_parts(stuff, .Position, Position)[0], Position{1, 2})
	testing.expect_value(t, ecs.get_things(stuff, .Position)[0], thing)
}

@(test)
stuff_later_procs_record_into_the_world :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	stuff := ecs.stuff_make(&world)

	a := ecs.spawn(stuff)
	b := ecs.spawn(stuff)
	ecs.add_now(stuff, b, .Tag)

	vel := Velocity{3, 4}
	ecs.set_later(stuff, a, .Position, Position{1, 2})
	ecs.set_later(stuff, a, .Velocity, &vel)
	ecs.set_later(stuff, b, .Position, Position)
	ecs.add_later(stuff, a, .Tag)
	ecs.remove_later(stuff, b, .Tag)

	testing.expect_value(t, ecs.world_count_commands(&world), 5)
	testing.expect(t, !ecs.has(stuff, a, .Position))

	ecs.world_apply_self(&world)
	testing.expect_value(t, ecs.get_part(stuff, a, .Position, Position)^, Position{1, 2})
	testing.expect_value(t, ecs.get_part(stuff, a, .Velocity, Velocity)^, vel)
	testing.expect_value(t, ecs.get_part(stuff, b, .Position, Position)^, Position{})
	testing.expect(t, ecs.has(stuff, a, .Tag))
	testing.expect(t, !ecs.has(stuff, b, .Tag))
}

// >------------------------------------------------------------------ Resources

@(test)
stuff_get_resource_is_the_worlds :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	stuff := ecs.stuff_make(&world)

	time := ecs.get_resource(stuff, .Time, Time)
	testing.expect(t, time == ecs.get_resource(&world, .Time, Time))
}
