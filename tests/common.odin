package ecs_tests

import ecs "../ecs"

// >---------------------------------------------------------------------- Kinds

// Parts, stashes and hierarchies share one enum. Which one a kind is depends on how it gets registered.
Kind :: enum {
	// Parts
	Position,
	Velocity,
	Health,
	Tag,
	Target, // shares the Position type

	// Stashes
	Time,
	Gravity,
	Flag,
	Big,
	Marker,

	// Hierarchies
	Transform,
	Inside,
}

PARTS :: bit_set[Kind]{.Position, .Velocity, .Health, .Tag, .Target}
STASHES :: bit_set[Kind]{.Time, .Gravity, .Flag, .Big, .Marker}
HIERARCHIES :: bit_set[Kind]{.Transform, .Inside}

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

Tag :: struct {}

Aligned :: struct #align (64) {
	value: int,
}

@(thread_local)
destroyed_count: int

count_destroyed :: proc(part: rawptr) {
	destroyed_count += 1
}

// >-------------------------------------------------------------------- Stashes

Time :: struct {
	delta:   f32,
	elapsed: f64,
}

@(thread_local)
destroyed_stashes: [Kind]int

count_destroyed_time :: proc(stash: rawptr) {
	destroyed_stashes[.Time] += 1
}

count_destroyed_gravity :: proc(stash: rawptr) {
	destroyed_stashes[.Gravity] += 1
}

// >-------------------------------------------------------------------- Systems

Stage :: enum {
	Update,
	Render,
}

// Every system appends its id here, so tests can check what ran and in which order.
@(thread_local)
system_log: [dynamic; 64]int

system_a :: proc(stuff: Stuff) {append(&system_log, 0)}
system_b :: proc(stuff: Stuff) {append(&system_log, 1)}
system_c :: proc(stuff: Stuff) {append(&system_log, 2)}
system_d :: proc(stuff: Stuff) {append(&system_log, 3)}

// Position of a system id in the log, or -1 if it never ran.
system_log_index :: proc(id: int) -> int {
	for logged, i in system_log do if logged == id do return i
	return -1
}

system_log_count :: proc(id: int) -> int {
	count := 0
	for logged in system_log do if logged == id do count += 1
	return count
}

// >------------------------------------------------------------------- Typedefs

Part_Pool :: ecs.Part_Pool(Kind)
Cmd_Buffer :: ecs.Cmd_Buffer(Kind)
World :: ecs.World(Kind, Stage)
System_Pool :: ecs.System_Pool(Kind, Stage)
System :: ecs.System_Info(Kind, Stage)
Stuff :: ecs.Stuff(Kind, Stage)
