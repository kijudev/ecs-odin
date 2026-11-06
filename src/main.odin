package main

import ecs "../ecs"
import "core:fmt"

// >---------------------------------------------------------------------- Parts

Part :: enum {
	Position,
	Velocity,
	Health,
	Tag,
}

Resource :: enum {}

Stage :: enum {
	PreUpdate,
	Update,
	PostUpdate,
}

Position :: struct {
	x, y: f32,
}

Velocity :: struct {
	x, y: f32,
}

Health :: struct {
	value: int,
}

Tag :: struct {}

main :: proc() {
	world: ecs.World(Part, Resource)
	ecs.world_init(&world)

	setup(&world)
	seed(&world)

	stuff := ecs.stuff_make(&world, Stage)
	query := ecs.query_make(stuff, {.Position, .Velocity}, {.Health})

	for ecs.query_next(&query) {
		thing := ecs.query_get_thing(&query)
		pos := ecs.query_get_part(&query, .Position, Position)
		vel := ecs.query_get_part(&query, .Velocity, Velocity)

		fmt.printf(
			"Thing %v: Position(%v, %v), Velocity(%v, %v)\n",
			thing,
			pos.x,
			pos.y,
			vel.x,
			vel.y,
		)
	}
}

setup :: proc(world: ^ecs.World(Part, Resource)) {
	ecs.register(world, .Position, Position)
	ecs.register(world, .Velocity, Velocity)
	ecs.register(world, .Health, Health)
	ecs.register(world, .Tag, Tag)
}

seed :: proc(world: ^ecs.World(Part, Resource)) {
	a := ecs.spawn(world)
	b := ecs.spawn(world)

	ecs.set_now(world, a, .Position, Position{3, 4})
	ecs.set_now(world, a, .Velocity, Velocity{1, 2})

	ecs.set_now(world, b, .Position, Position{5, 6})
	ecs.set_now(world, b, .Velocity, Velocity{7, 8})
	ecs.set_now(world, b, .Health, Health{100})
}
