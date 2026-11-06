package ecs

import "base:intrinsics"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

Cmd_Offset :: u32
Cmd_Size :: u32

CMD_BUFFER_MAX_PARTS_SIZE :: int(max(Cmd_Offset))
CMD_PART_MAX_SIZE :: int(max(Cmd_Size))

CMD_BUFFER_DEFAULT_CAPACITY :: 1 << 8
CMD_BUFFER_DEFAULT_PARTS_CAPACITY :: 1 << 12

Cmd_Kill :: struct {
	thing: Thing,
}

Cmd_Set_Value :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	thing:  Thing,
	kind:   K,
	offset: Cmd_Offset,
	size:   Cmd_Size,
}

Cmd_Set_Zero :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	thing: Thing,
	kind:  K,
}

Cmd_Remove :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	thing: Thing,
	kind:  K,
}

Cmd :: union($K: typeid) where intrinsics.type_is_enum(K) {
	Cmd_Kill,
	Cmd_Set_Value(K),
	Cmd_Set_Zero(K),
	Cmd_Remove(K),
}

Cmd_Buffer :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	cmds:      [dynamic]Cmd(K),
	parts:     [dynamic]byte,
	allocator: mem.Allocator,
}

// >----------------------------------------------------------------- Cmd_Buffer

cmd_buffer_init :: proc(
	buffer: ^Cmd_Buffer($K),
	capacity: int = CMD_BUFFER_DEFAULT_CAPACITY,
	parts_capacity: int = CMD_BUFFER_DEFAULT_PARTS_CAPACITY,
	allocator: mem.Allocator = context.allocator,
) {
	assert(capacity >= 0, "Command buffer capacity cannot be negative.")
	assert(parts_capacity >= 0, "Command buffer parts capacity cannot be negative.")
	assert(
		parts_capacity <= CMD_BUFFER_MAX_PARTS_SIZE,
		"Command buffer parts capacity has to be less or equal to CMD_BUFFER_MAX_PARTS_SIZE.",
	)

	cmds, cmds_err := make([dynamic]Cmd(K), 0, capacity, allocator)
	if cmds_err != nil do panic("Failed to allocate memory for command buffer.")

	parts, parts_err := make([dynamic]byte, 0, parts_capacity, allocator)
	if parts_err != nil do panic("Failed to allocate memory for command buffer.")

	buffer^ = Cmd_Buffer(K) {
		cmds      = cmds,
		parts     = parts,
		allocator = allocator,
	}
}

cmd_buffer_destroy :: proc(buffer: ^Cmd_Buffer($K)) {
	delete(buffer.cmds)
	delete(buffer.parts)
	buffer^ = Cmd_Buffer(K){}
}

cmd_buffer_reset :: proc(buffer: ^Cmd_Buffer($K)) {
	clear(&buffer.cmds)
	clear(&buffer.parts)
}

cmd_buffer_record_kill :: proc(buffer: ^Cmd_Buffer($K), thing: Thing) {
	assert(thing != THING_NIL, "Cannot record a command for THING_NIL.")
	record(buffer, Cmd_Kill{thing = thing})
}

cmd_buffer_record_set_value :: proc(
	buffer: ^Cmd_Buffer($K),
	thing: Thing,
	kind: K,
	part: rawptr,
	size: int,
) {
	assert(thing != THING_NIL, "Cannot record a command for THING_NIL.")
	assert(size >= 0, "Part size cannot be negative.")
	assert(size <= CMD_PART_MAX_SIZE, "Part size has to be less or equal to CMD_PART_MAX_SIZE.")
	assert(part != nil || size == 0, "Cannot record a nil part, use cmd_buffer_record_set_zero.")
	if len(buffer.parts) + size > CMD_BUFFER_MAX_PARTS_SIZE {
		panic("Command buffer parts size would exceed CMD_BUFFER_MAX_PARTS_SIZE.")
	}

	offset := len(buffer.parts)
	if size > 0 {
		if _, err := append(&buffer.parts, ..mem.byte_slice(part, size)); err != nil do panic("Failed to allocate memory for command buffer.")
	}

	record(
		buffer,
		Cmd_Set_Value(K) {
			thing = thing,
			kind = kind,
			offset = Cmd_Offset(offset),
			size = Cmd_Size(size),
		},
	)
}

cmd_buffer_record_set_zero :: proc(buffer: ^Cmd_Buffer($K), thing: Thing, kind: K) {
	assert(thing != THING_NIL, "Cannot record a command for THING_NIL.")
	record(buffer, Cmd_Set_Zero(K){thing = thing, kind = kind})
}

cmd_buffer_record_remove :: proc(buffer: ^Cmd_Buffer($K), thing: Thing, kind: K) {
	assert(thing != THING_NIL, "Cannot record a command for THING_NIL.")
	record(buffer, Cmd_Remove(K){thing = thing, kind = kind})
}

cmd_buffer_get_bytes :: proc(
	buffer: ^Cmd_Buffer($K),
	offset: Cmd_Offset,
	size: Cmd_Size,
) -> []byte {
	assert(
		int(offset) + int(size) <= len(buffer.parts),
		"Command part range is out of the parts buffer bounds.",
	)

	return buffer.parts[offset:][:size]
}

cmd_buffer_get_part :: proc(buffer: ^Cmd_Buffer($K), offset: Cmd_Offset, $T: typeid) -> T {
	when size_of(T) == 0 {
		return {}
	} else {
		bytes := cmd_buffer_get_bytes(buffer, offset, Cmd_Size(size_of(T)))
		return intrinsics.unaligned_load((^T)(raw_data(bytes)))
	}
}

// >------------------------------------------------------------------ Internals

@(private = "file")
record :: proc(buffer: ^Cmd_Buffer($K), cmd: Cmd(K)) {
	if _, err := append(&buffer.cmds, cmd); err != nil {
		panic("Failed to allocate memory for command buffer.")
	}
}
