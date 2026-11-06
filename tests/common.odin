package ecs_tests

import ecs "../ecs"

// >---------------------------------------------------------------------- Parts

Part :: enum {
	Position,
	Velocity,
	Health,
	Tag,
	Target, // shares the Position type
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

Aligned :: struct #align (64) {
	value: int,
}

@(thread_local)
destroyed_count: int

count_destroyed :: proc(part: rawptr) {
	destroyed_count += 1
}

// >------------------------------------------------------------------ Resources

Resource :: enum {
	Time,
	Gravity,
	Flag,
	Big,
	Marker,
}

Time :: struct {
	delta:   f32,
	elapsed: f64,
}

@(thread_local)
destroyed_resources: [Resource]int

count_destroyed_time :: proc(resource: rawptr) {
	destroyed_resources[.Time] += 1
}

count_destroyed_gravity :: proc(resource: rawptr) {
	destroyed_resources[.Gravity] += 1
}

// >-------------------------------------------------------------------- Systems

Stage :: enum {
	Update,
	Render,
}

// Every system appends its id here, so tests can check what ran and in which order.
@(thread_local)
system_log: [dynamic; 64]int

system_a :: proc(stuff: ^Stuff) {append(&system_log, 0)}
system_b :: proc(stuff: ^Stuff) {append(&system_log, 1)}
system_c :: proc(stuff: ^Stuff) {append(&system_log, 2)}
system_d :: proc(stuff: ^Stuff) {append(&system_log, 3)}

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

Part_Pool :: ecs.Part_Pool(Part)
Cmd_Pool :: ecs.Cmd_Pool(Part)
World :: ecs.World(Part, Resource, Stage)
System_Pool :: ecs.System_Pool(Part, Resource, Stage)
System :: ecs.System_Info(Part, Resource, Stage)
Stuff :: ecs.Stuff(Part, Resource, Stage)
