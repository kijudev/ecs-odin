package main

import ecs "../ecs"
import "core:fmt"

// >---------------------------------------------------------------------- Kinds

Kind :: enum {
	// Parts
	Position,
	Velocity,
	Health,
	Poisoned,

	// Stashes
	Time,
	Gravity,
}

Kinds :: bit_set[Kind]

// >---------------------------------------------------------------------- Parts

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

// >-------------------------------------------------------------------- Stashes

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

World :: ecs.World(Kind, Stage)
Stuff :: ecs.Stuff(Kind, Stage)

// >----------------------------------------------------------------------- Main

main :: proc() {
	world: World
	ecs.world_init(&world)
	defer ecs.world_destroy(&world)

	setup(&world)
	seed(&world)

	for _ in 0 ..< 5 {
		for stage in Stage {
			ecs.world_run_stage_sync(&world, stage)
			ecs.world_apply(&world)
		}
	}
}

setup :: proc(w: ^World) {
	ecs.register_part(w, .Position, Position)
	ecs.register_part(w, .Velocity, Velocity)
	ecs.register_part(w, .Health, Health)
	ecs.register_part(w, .Poisoned, Poisoned)

	ecs.register_stash(w, .Time, Time)
	ecs.register_stash(w, .Gravity, Gravity)
	ecs.get_stash(w, .Time, Time).delta = 0.5
	ecs.get_stash(w, .Gravity, Gravity).y = -10

	ecs.world_schedule(w, system_tick, .PreUpdate, {}, {.Time})

	ecs.world_schedule(w, system_fall, .Update, {.Time, .Gravity}, {.Velocity})
	ecs.world_schedule(w, system_move, .Update, {.Time, .Velocity}, {.Position})
	ecs.world_schedule(w, system_poison, .Update, {.Poisoned}, {.Health})

	ecs.world_schedule(w, system_reap, .PostUpdate, {.Health}, {})
	ecs.world_schedule(w, system_report, .PostUpdate, {.Time, .Position, .Health}, {})
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
	ecs.get_stash(stuff, .Time, Time).frame += 1
}

system_fall :: proc(stuff: Stuff) {
	dt := ecs.get_stash(stuff, .Time, Time).delta
	gravity := ecs.get_stash(stuff, .Gravity, Gravity)

	query := ecs.query_make(stuff, {.Velocity}, {})
	for ecs.query_next(&query) {
		vel := ecs.get_part(&query, .Velocity, Velocity)
		vel.y += gravity.y * dt
	}
}

system_move :: proc(stuff: Stuff) {
	dt := ecs.get_stash(stuff, .Time, Time).delta

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
	frame := ecs.get_stash(stuff, .Time, Time).frame
	fmt.printfln("frame %v, %v alive", frame, ecs.count_alive(stuff))

	query := ecs.query_make(stuff, {.Position, .Health}, {})
	for ecs.query_next(&query) {
		thing := ecs.get_thing(&query)
		pos := ecs.get_part(&query, .Position, Position)
		hp := ecs.get_part(&query, .Health, Health)
		fmt.printfln("  thing %v: pos (%.1f, %.1f), hp %v", thing.idx, pos.x, pos.y, hp.value)
	}
}
