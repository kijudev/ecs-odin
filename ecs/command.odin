package ecs

import "core:mem"
// >-------------------------------------------------------- Constants and Types

Cmd_Part :: u32
Cmd_Idx :: u32

Cmd_Kill :: struct {
	thing: Thing,
}

Cmd_Set_Value :: struct {
	thing: Thing,
	idx:   Cmd_Idx,
	part:  Cmd_Part,
}

Cmd_Set_Zero :: struct {
	thing: Thing,
	part:  Cmd_Part,
}

Cmd_Remove :: struct {
	thing: Thing,
	part:  Cmd_Part,
}

Cmd :: union {
	Cmd_Kill,
	Cmd_Set_Value,
	Cmd_Set_Zero,
}

Cmd_Pool :: struct {
	commands:    [dynamic]Cmd,
	parts:       [dynamic]byte,
	parts_next:  int,
	parts_count: int,
	allocator:   mem.Allocator,
}

// >------------------------------------------------------------------- Cmd_Pool

cmd_pool_init :: proc(pool: ^Cmd_Pool, allocator := context.allocator) {
	pool^ = {
		commands    = make([dynamic]Cmd, allocator),
		parts       = make([dynamic]byte, allocator),
		parts_next  = 0,
		parts_count = 0,
		allocator   = allocator,
	}
}

cmd_pool_destroy :: proc(pool: ^Cmd_Pool) {
	delete(pool.commands)
	delete(pool.parts)
	pool^ = {}
}

cmd_pool_reset :: proc(pool: ^Cmd_Pool) {
	clear(&pool.commands)
	clear(&pool.parts)
	pool.parts_next = 0
	pool.parts_count = 0
}

cmd_pool_record_kill :: proc(pool: ^Cmd_Pool, thing: Thing) {
	append(&pool.commands, Cmd_Kill{thing = thing})
}

cmd_pool_record_set_value :: proc(pool: ^Cmd_Pool, thing: Thing, part: rawptr, size: int) {
	if pool.parts_next + size > pool.parts_count {
		new_size := max(pool.parts_count * 2, pool.parts_next + size)
		resize(&pool.parts, new_size)
		pool.parts_count = new_size
	}

	part_offset := pool.parts_next
	mem.copy(&pool.parts[part_offset], part, size)
	pool.parts_next += size

	append(
		&pool.commands,
		Cmd_Set_Value{thing = thing, idx = Cmd_Idx(part_offset), part = Cmd_Part(size)},
	)
}

cmd_pool_record_set_zero :: proc(pool: ^Cmd_Pool, thing: Thing, part: rawptr, size: int) {
	append(&pool.commands, Cmd_Set_Zero{thing = thing, part = Cmd_Part(size)})
}
