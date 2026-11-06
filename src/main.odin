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

World :: ecs.World(Part, Resource, Stage)

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
	world: ecs.World(Part, Resource, Stage)
	ecs.world_init(&world)
	defer ecs.world_destroy(&world)

	setup(&world)
	seed(&world)

	stuff := ecs.stuff_make(&world)
	query := ecs.query_make(stuff, {.Position, .Velocity}, {.Health})

	for ecs.query_next(&query) {
		thing := ecs.get_thing(&query)
		pos := ecs.get_part(&query, .Position, Position)
		vel := ecs.get_part(&query, .Velocity, Velocity)

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

setup :: proc(w: ^World) {
	ecs.register(w, .Position, Position)
	ecs.register(w, .Velocity, Velocity)
	ecs.register(w, .Health, Health)
	ecs.register(w, .Tag, Tag)
}

seed :: proc(w: ^World) {
	a := ecs.spawn(w)
	b := ecs.spawn(w)

	ecs.set_later(w, a, .Position, Position{3, 4})
	ecs.set_later(w, a, .Velocity, Velocity{1, 2})

	ecs.set_later(w, b, .Position, Position{5, 6})
	ecs.set_later(w, b, .Velocity, Velocity{7, 8})
	ecs.set_later(w, b, .Health, Health{100})

	ecs.world_apply_self(w)
}
