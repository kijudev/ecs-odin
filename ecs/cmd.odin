package ecs

import "base:intrinsics"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

Cmd_Offset :: u32
Cmd_Size :: u32

CMD_POOL_MAX_PARTS_SIZE :: int(max(Cmd_Offset))
CMD_PART_MAX_SIZE :: int(max(Cmd_Size))

CMD_POOL_DEFAULT_CAPACITY :: 1 << 8
CMD_POOL_DEFAULT_PARTS_CAPACITY :: 1 << 12

Cmd_Kill :: struct {
	thing: Thing,
}

Cmd_Set_Value :: struct($P: typeid) where intrinsics.type_is_enum(P) {
	thing:  Thing,
	kind:   P,
	offset: Cmd_Offset,
	size:   Cmd_Size,
}

Cmd_Set_Zero :: struct($P: typeid) where intrinsics.type_is_enum(P) {
	thing: Thing,
	kind:  P,
}

Cmd_Remove :: struct($P: typeid) where intrinsics.type_is_enum(P) {
	thing: Thing,
	kind:  P,
}

Cmd :: union($P: typeid) where intrinsics.type_is_enum(P) {
	Cmd_Kill,
	Cmd_Set_Value(P),
	Cmd_Set_Zero(P),
	Cmd_Remove(P),
}

Cmd_Pool :: struct($P: typeid) where intrinsics.type_is_enum(P) {
	commands:  [dynamic]Cmd(P),
	parts:     [dynamic]byte,
	allocator: mem.Allocator,
}

// >------------------------------------------------------------------- Cmd_Pool

cmd_pool_init :: proc(
	pool: ^Cmd_Pool($P),
	capacity: int = CMD_POOL_DEFAULT_CAPACITY,
	parts_capacity: int = CMD_POOL_DEFAULT_PARTS_CAPACITY,
	allocator: mem.Allocator = context.allocator,
) {
	assert(capacity >= 0, "Command pool capacity cannot be negative.")
	assert(parts_capacity >= 0, "Command pool parts capacity cannot be negative.")
	assert(
		parts_capacity <= CMD_POOL_MAX_PARTS_SIZE,
		"Command pool parts capacity has to be less or equal to CMD_POOL_MAX_PARTS_SIZE.",
	)

	commands, commands_err := make([dynamic]Cmd(P), 0, capacity, allocator)
	if commands_err != nil do panic("Failed to allocate memory for command pool.")

	parts, parts_err := make([dynamic]byte, 0, parts_capacity, allocator)
	if parts_err != nil do panic("Failed to allocate memory for command pool.")

	pool^ = Cmd_Pool(P) {
		commands  = commands,
		parts     = parts,
		allocator = allocator,
	}
}

cmd_pool_destroy :: proc(pool: ^Cmd_Pool($P)) {
	delete(pool.commands)
	delete(pool.parts)
	pool^ = Cmd_Pool(P){}
}

cmd_pool_reset :: proc(pool: ^Cmd_Pool($P)) {
	clear(&pool.commands)
	clear(&pool.parts)
}

cmd_pool_record_kill :: proc(pool: ^Cmd_Pool($P), thing: Thing) {
	assert(thing != THING_NIL, "Cannot record a command for THING_NIL.")
	record(pool, Cmd_Kill{thing = thing})
}

cmd_pool_record_set_value :: proc(
	pool: ^Cmd_Pool($P),
	thing: Thing,
	kind: P,
	part: rawptr,
	size: int,
) {
	assert(thing != THING_NIL, "Cannot record a command for THING_NIL.")
	assert(size >= 0, "Part size cannot be negative.")
	assert(size <= CMD_PART_MAX_SIZE, "Part size has to be less or equal to CMD_PART_MAX_SIZE.")
	assert(part != nil || size == 0, "Cannot record a nil part, use cmd_pool_record_set_zero.")
	if len(pool.parts) + size > CMD_POOL_MAX_PARTS_SIZE {
		panic("Command pool parts size would exceed CMD_POOL_MAX_PARTS_SIZE.")
	}

	offset := len(pool.parts)
	if size > 0 {
		if _, err := append(&pool.parts, ..mem.byte_slice(part, size)); err != nil do panic("Failed to allocate memory for command pool.")
	}

	record(
		pool,
		Cmd_Set_Value(P) {
			thing = thing,
			kind = kind,
			offset = Cmd_Offset(offset),
			size = Cmd_Size(size),
		},
	)
}

cmd_pool_record_set_zero :: proc(pool: ^Cmd_Pool($P), thing: Thing, kind: P) {
	assert(thing != THING_NIL, "Cannot record a command for THING_NIL.")
	record(pool, Cmd_Set_Zero(P){thing = thing, kind = kind})
}

cmd_pool_record_remove :: proc(pool: ^Cmd_Pool($P), thing: Thing, kind: P) {
	assert(thing != THING_NIL, "Cannot record a command for THING_NIL.")
	record(pool, Cmd_Remove(P){thing = thing, kind = kind})
}

cmd_pool_get_bytes :: proc(pool: ^Cmd_Pool($P), offset: Cmd_Offset, size: Cmd_Size) -> []byte {
	assert(
		int(offset) + int(size) <= len(pool.parts),
		"Command part range is out of the parts buffer bounds.",
	)

	return pool.parts[offset:][:size]
}

cmd_pool_get_part :: proc(pool: ^Cmd_Pool($P), offset: Cmd_Offset, $T: typeid) -> T {
	when size_of(T) == 0 {
		return {}
	} else {
		bytes := cmd_pool_get_bytes(pool, offset, Cmd_Size(size_of(T)))
		return intrinsics.unaligned_load((^T)(raw_data(bytes)))
	}
}

// >------------------------------------------------------------------ Internals

@(private = "file")
record :: proc(pool: ^Cmd_Pool($P), cmd: Cmd(P)) {
	if _, err := append(&pool.commands, cmd); err != nil {
		panic("Failed to allocate memory for command pool.")
	}
}
