package ecs

import "base:intrinsics"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

Cmd_Offset :: u32
Cmd_Size :: u32

/* Kills `thing`. */
Cmd_Kill :: struct {
	thing: Thing,
}

/* Sets `thing`'s part of `kind` to the `size` bytes at `offset` in the buffer's `parts`. */
Cmd_Set_Value :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	thing:  Thing,
	kind:   K,
	offset: Cmd_Offset,
	size:   Cmd_Size,
}

/* Sets `thing`'s part of `kind` to zero. */
Cmd_Set_Zero :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	thing: Thing,
	kind:  K,
}

/* Removes `thing`'s part of `kind`. */
Cmd_Remove :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	thing: Thing,
	kind:  K,
}

/* Attaches `child` as the last child of `parent` in the hierarchy of `kind`. */
Cmd_Attach :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	kind:   K,
	child:  Thing,
	parent: Thing,
}

/* Detaches `child` from its parent in the hierarchy of `kind`. */
Cmd_Detach :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	kind:  K,
	child: Thing,
}

/* Kills `thing` and all its descendants in the hierarchy of `kind`. */
Cmd_Kill_Tree :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	kind:  K,
	thing: Thing,
}

/* A recorded change to the world. */
Cmd :: union($K: typeid) where intrinsics.type_is_enum(K) {
	Cmd_Kill,
	Cmd_Set_Value(K),
	Cmd_Set_Zero(K),
	Cmd_Remove(K),
	Cmd_Attach(K),
	Cmd_Detach(K),
	Cmd_Kill_Tree(K),
}

/*
Records changes to apply to the world later, in order. Values to set are copied into `parts` and
the commands refer to them by offset, so parts of any type share one buffer.
*/
Cmd_Buffer :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	cmds:      [dynamic]Cmd(K),
	parts:     [dynamic]byte,
	allocator: mem.Allocator,
}

// >----------------------------------------------------------------- Cmd_Buffer

/*
Initializes the buffer with room for `capacity` commands and `parts_capacity` bytes of parts,
allocated up front with `allocator`. Both grow as needed.

Asserts:
- `capacity` is not negative.
- `parts_capacity` is between 0 and CMD_BUFFER_MAX_PARTS_CAPACITY.
*/
cmd_buffer_init :: proc(
	buffer: ^Cmd_Buffer($K),
	capacity: int = CMD_BUFFER_DEFAULT_CAPACITY,
	parts_capacity: int = CMD_BUFFER_DEFAULT_PARTS_CAPACITY,
	allocator: mem.Allocator = context.allocator,
) {
	assert(capacity >= 0, "Command buffer capacity cannot be negative.")
	assert(parts_capacity >= 0, "Command buffer parts capacity cannot be negative.")
	assert(
		parts_capacity <= CMD_BUFFER_MAX_PARTS_CAPACITY,
		"Command buffer parts capacity has to be less or equal to CMD_BUFFER_MAX_PARTS_CAPACITY.",
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

/* Frees the buffer and zeroes it. */
cmd_buffer_destroy :: proc(buffer: ^Cmd_Buffer($K)) {
	delete(buffer.cmds)
	delete(buffer.parts)
	buffer^ = Cmd_Buffer(K){}
}

/* Drops every recorded command and part, keeping the allocated memory. */
cmd_buffer_reset :: proc(buffer: ^Cmd_Buffer($K)) {
	clear(&buffer.cmds)
	clear(&buffer.parts)
}

/*
Records killing the thing.

Asserts:
- `thing` is not THING_NIL.
*/
cmd_buffer_record_kill :: proc(buffer: ^Cmd_Buffer($K), thing: Thing) {
	assert(thing != THING_NIL, "Cannot record a command for THING_NIL.")
	record(buffer, Cmd_Kill{thing = thing})
}

/*
Records setting the thing's part of `kind` to a copy of the `size` bytes at `part`.

Asserts:
- `thing` is not THING_NIL.
- `size` is between 0 and CMD_BUFFER_MAX_PART_SIZE.
- `part` is not nil, unless `size` is 0.

Panics:
- the parts would grow past CMD_BUFFER_MAX_PARTS_CAPACITY.
*/
cmd_buffer_record_set_value :: proc(
	buffer: ^Cmd_Buffer($K),
	thing: Thing,
	kind: K,
	part: rawptr,
	size: int,
) {
	assert(thing != THING_NIL, "Cannot record a command for THING_NIL.")
	assert(size >= 0, "Part size cannot be negative.")
	assert(
		size <= CMD_BUFFER_MAX_PART_SIZE,
		"Part size has to be less or equal to CMD_BUFFER_MAX_PART_SIZE.",
	)
	assert(part != nil || size == 0, "Cannot record a nil part, use cmd_buffer_record_set_zero.")
	if len(buffer.parts) + size > CMD_BUFFER_MAX_PARTS_CAPACITY {
		panic("Command buffer parts size would exceed CMD_BUFFER_MAX_PARTS_CAPACITY.")
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

/*
Records setting the thing's part of `kind` to zero.

Asserts:
- `thing` is not THING_NIL.
*/
cmd_buffer_record_set_zero :: proc(buffer: ^Cmd_Buffer($K), thing: Thing, kind: K) {
	assert(thing != THING_NIL, "Cannot record a command for THING_NIL.")
	record(buffer, Cmd_Set_Zero(K){thing = thing, kind = kind})
}

/*
Records removing the thing's part of `kind`.

Asserts:
- `thing` is not THING_NIL.
*/
cmd_buffer_record_remove :: proc(buffer: ^Cmd_Buffer($K), thing: Thing, kind: K) {
	assert(thing != THING_NIL, "Cannot record a command for THING_NIL.")
	record(buffer, Cmd_Remove(K){thing = thing, kind = kind})
}

/*
Records attaching `child` to `parent` in the hierarchy of `kind`.

Asserts:
- `child` and `parent` are not THING_NIL.
*/
cmd_buffer_record_attach :: proc(buffer: ^Cmd_Buffer($K), kind: K, child, parent: Thing) {
	assert(child != THING_NIL && parent != THING_NIL, "Cannot record a command for THING_NIL.")
	record(buffer, Cmd_Attach(K){kind = kind, child = child, parent = parent})
}

/*
Records detaching `child` from its parent in the hierarchy of `kind`.

Asserts:
- `child` is not THING_NIL.
*/
cmd_buffer_record_detach :: proc(buffer: ^Cmd_Buffer($K), kind: K, child: Thing) {
	assert(child != THING_NIL, "Cannot record a command for THING_NIL.")
	record(buffer, Cmd_Detach(K){kind = kind, child = child})
}

/*
Records killing the thing and all its descendants in the hierarchy of `kind`.

Asserts:
- `thing` is not THING_NIL.
*/
cmd_buffer_record_kill_tree :: proc(buffer: ^Cmd_Buffer($K), kind: K, thing: Thing) {
	assert(thing != THING_NIL, "Cannot record a command for THING_NIL.")
	record(buffer, Cmd_Kill_Tree(K){kind = kind, thing = thing})
}

/*
Gets the `size` bytes of parts at `offset`, as recorded by `cmd_buffer_record_set_value`.

The slice is valid until the next record or reset.

Asserts:
- the range is inside the recorded parts.
*/
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

/*
Gets a copy of the part of type `T` at `offset`. Parts are packed without alignment, so it is
loaded unaligned.

Asserts:
- the part is inside the recorded parts.
*/
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
