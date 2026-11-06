package main

import ecs "../ecs"
import "core:fmt"

// >---------------------------------------------------------------------- Parts

Part :: enum {
	Position,
	Velocity,
	Health,
	Poisoned,
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

Poisoned :: struct {}

// >------------------------------------------------------------------ Resources

Resource :: enum {
	Time,
	Gravity,
}

Time :: struct {
	delta: f32,
	frame: int,
}

Gravity :: struct {
	y: f32,
}

// >--------------------------------------------------------------------- Stages

Stage :: enum {
	PreUpdate,
	Update,
	PostUpdate,
}

World :: ecs.World(Part, Resource, Stage)
Stuff :: ecs.Stuff(Part, Resource, Stage)

// >----------------------------------------------------------------------- Main

main :: proc() {
	world: World
	ecs.world_init(&world)
	defer ecs.world_destroy(&world)

	setup(&world)
	seed(&world)

	for _ in 0 ..< 5 {
		ecs.world_run_sync(&world)
	}
}

setup :: proc(w: ^World) {
	ecs.register(w, .Position, Position)
	ecs.register(w, .Velocity, Velocity)
	ecs.register(w, .Health, Health)
	ecs.register(w, .Poisoned, Poisoned)

	ecs.register_resource(w, .Time, Time)
	ecs.register_resource(w, .Gravity, Gravity)
	ecs.get_resource(w, .Time, Time).delta = 0.5
	ecs.get_resource(w, .Gravity, Gravity).y = -10

	ecs.world_schedule(w, system_tick, .PreUpdate, {}, {})

	ecs.world_schedule(w, system_fall, .Update, {}, {.Velocity})
	ecs.world_schedule(w, system_move, .Update, {.Velocity}, {.Position})
	ecs.world_schedule(w, system_poison, .Update, {.Poisoned}, {.Health})

	ecs.world_schedule(w, system_reap, .PostUpdate, {.Health}, {})
	ecs.world_schedule(w, system_report, .PostUpdate, {.Position, .Health}, {})
}

seed :: proc(w: ^World) {
	ball := ecs.spawn(w)
	ecs.set_now(w, ball, .Position, Position{0, 100})
	ecs.set_now(w, ball, .Velocity, Velocity{2, 0})
	ecs.set_now(w, ball, .Health, Health{10})

	sick := ecs.spawn(w)
	ecs.set_now(w, sick, .Position, Position{5, 5})
	ecs.set_now(w, sick, .Health, Health{3})
	ecs.add_now(w, sick, .Poisoned)
}

// >-------------------------------------------------------------------- Systems

system_tick :: proc(stuff: Stuff) {
	ecs.get_resource(stuff, .Time, Time).frame += 1
}

system_fall :: proc(stuff: Stuff) {
	dt := ecs.get_resource(stuff, .Time, Time).delta
	gravity := ecs.get_resource(stuff, .Gravity, Gravity)

	query := ecs.query_make(stuff, {.Velocity}, {})
	for ecs.query_next(&query) {
		vel := ecs.get_part(&query, .Velocity, Velocity)
		vel.y += gravity.y * dt
	}
}

system_move :: proc(stuff: Stuff) {
	dt := ecs.get_resource(stuff, .Time, Time).delta

	query := ecs.query_make(stuff, {.Position, .Velocity}, {})
	for ecs.query_next(&query) {
		pos := ecs.get_part(&query, .Position, Position)
		vel := ecs.get_part(&query, .Velocity, Velocity)

		pos.x += vel.x * dt
		pos.y += vel.y * dt
	}
}

system_poison :: proc(stuff: Stuff) {
	query := ecs.query_make(stuff, {.Health, .Poisoned}, {})

	for ecs.query_next(&query) {
		ecs.get_part(&query, .Health, Health).value -= 1
	}
}

system_reap :: proc(stuff: Stuff) {
	query := ecs.query_make(stuff, {.Health}, {})
	for ecs.query_next(&query) {
		if ecs.get_part(&query, .Health, Health).value <= 0 {
			ecs.kill_later(stuff, ecs.get_thing(&query))
		}
	}
}

system_report :: proc(stuff: Stuff) {
	frame := ecs.get_resource(stuff, .Time, Time).frame
	fmt.printfln("frame %v, %v alive", frame, ecs.count_alive(stuff))

	query := ecs.query_make(stuff, {.Position, .Health}, {})
	for ecs.query_next(&query) {
		thing := ecs.get_thing(&query)
		pos := ecs.get_part(&query, .Position, Position)
		hp := ecs.get_part(&query, .Health, Health)
		fmt.printfln("  thing %v: pos (%.1f, %.1f), hp %v", thing.idx, pos.x, pos.y, hp.value)
	}
}
