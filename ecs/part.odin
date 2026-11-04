package ecs

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

PART_SET_PAGE_COUNT :: 1 << 6
PART_SET_PAGE_BITS :: THING_IDX_BITS - 6
PART_SET_PAGE_SIZE :: 1 << PART_SET_PAGE_BITS
PART_SET_MAX_CAPACITY :: THING_MAX_IDX
PART_MAX_COUNT :: 128

#assert(PART_SET_PAGE_COUNT * PART_SET_PAGE_SIZE == THING_MAX_IDX)

Part_Idx :: u32
Part_Set_Indices :: Inline_Paged_Array(Part_Idx, PART_SET_PAGE_COUNT, PART_SET_PAGE_SIZE)

Part_Set :: struct {
	part_info:      ^runtime.Type_Info,
	part_size:      int,
	part_align:     int,
	indices:        Part_Set_Indices,
	things:         []Thing,
	parts_data:     []byte,
	parts_capacity: int,
	parts_size:     int,
	destroy_part:   proc(part: rawptr),
	allocator:      mem.Allocator,
}

Part_Pool :: struct($P: typeid) where intrinsics.type_is_enum(P) {
	sets:       [P]Part_Set,
	types:      [P]typeid,
	registered: bit_set[P],
	allocator:  mem.Allocator,
}

@(private = "file")
Part_Zero_Sized: u8

// >------------------------------------------------------------------- Part_Set

part_set_init :: proc(
	set: ^Part_Set,
	part_info: ^runtime.Type_Info,
	destroy_part: proc(part: rawptr) = nil,
	allocator: mem.Allocator = context.allocator,
) {
	assert(part_info != nil, "Part set needs the part type info.")

	set^ = Part_Set {
		part_info      = part_info,
		part_size      = part_info.size,
		part_align     = part_info.align,
		indices        = {},
		things         = nil,
		parts_data     = nil,
		parts_capacity = 0,
		parts_size     = 0,
		destroy_part   = destroy_part,
		allocator      = allocator,
	}

	inline_paged_array_init(&set.indices, allocator)
}

part_set_destroy :: proc(set: ^Part_Set) {
	parts_destroy_all(set)
	inline_paged_array_destroy(&set.indices)

	delete(set.things, set.allocator)
	delete(set.parts_data, set.allocator)
	set^ = Part_Set{}
}

part_set_reset :: proc(set: ^Part_Set) {
	parts_destroy_all(set)
	inline_paged_array_reset(&set.indices)
	set.parts_size = 0
}

part_set_count_parts :: proc(set: ^Part_Set) -> int {
	return set.parts_size
}

part_set_capacity :: proc(set: ^Part_Set) -> int {
	return set.parts_capacity
}

part_set_has :: proc(set: ^Part_Set, thing: Thing) -> bool {
	_, ok := dense_idx(set, thing)
	return ok
}

part_set_get_part :: proc(set: ^Part_Set, thing: Thing) -> rawptr {
	idx, ok := dense_idx(set, thing)
	if !ok do return nil

	return parts_get_unchecked(set, idx)
}

part_set_get_part_unchecked :: proc(set: ^Part_Set, thing: Thing) -> rawptr {
	return parts_get_unchecked(set, dense_idx_unchecked(set, thing))
}

part_set_insert :: proc(set: ^Part_Set, thing: Thing, part: rawptr = nil) -> rawptr {
	assert(thing != THING_NIL, "Cannot insert a part for THING_NIL.")

	entry := inline_paged_array_get(&set.indices, int(thing.idx))
	if entry == 0 do return part_set_insert_unchecked(set, thing, part)

	idx := int(entry - 1)
	set.things[idx] = thing

	result := parts_get_unchecked(set, idx)
	if result == part do return result

	if set.destroy_part != nil do set.destroy_part(result)
	parts_write(set, result, part)

	return result
}

part_set_insert_unchecked :: proc(set: ^Part_Set, thing: Thing, part: rawptr = nil) -> rawptr {
	assert(thing != THING_NIL, "Cannot insert a part for THING_NIL.")
	assert(set.parts_size < PART_SET_MAX_CAPACITY, "Part set is full.")

	idx := set.parts_size
	result := parts_append(set, part)

	set.things[idx] = thing
	inline_paged_array_set(&set.indices, int(thing.idx), Part_Idx(idx + 1))

	return result
}

part_set_remove :: proc(set: ^Part_Set, thing: Thing) -> bool {
	if !part_set_has(set, thing) do return false

	part_set_remove_unchecked(set, thing)
	return true
}

part_set_remove_unchecked :: proc(set: ^Part_Set, thing: Thing) {
	idx := dense_idx_unchecked(set, thing)
	last_idx := set.parts_size - 1

	if idx != last_idx {
		moved := set.things[last_idx]
		set.things[idx] = moved
		inline_paged_array_set_unchecked(&set.indices, int(moved.idx), Part_Idx(idx + 1))
	}

	inline_paged_array_set_unchecked(&set.indices, int(thing.idx), 0)
	parts_remove_swap(set, idx)
}

part_set_get_parts :: proc(set: ^Part_Set) -> []byte {
	return set.parts_data[:set.parts_size * set.part_size]
}

part_set_get_things :: proc(set: ^Part_Set) -> []Thing {
	return set.things[:set.parts_size]
}

// >------------------------------------------------------------------ Part_Pool

part_pool_init :: proc(pool: ^Part_Pool($P), allocator: mem.Allocator = context.allocator) {
	pool^ = Part_Pool(P) {
		allocator = allocator,
	}
}

part_pool_destroy :: proc(pool: ^Part_Pool($P)) {
	for kind in pool.registered {
		part_set_destroy(&pool.sets[kind])
	}

	pool^ = Part_Pool(P){}
}

// Keeps the registrations.
part_pool_reset :: proc(pool: ^Part_Pool($P)) {
	for kind in pool.registered {
		part_set_reset(&pool.sets[kind])
	}
}

part_pool_register :: proc(
	pool: ^Part_Pool($P),
	kind: P,
	$T: typeid,
	destroy_part: proc(part: rawptr) = nil,
) {
	fmt.assertf(kind not_in pool.registered, "Part kind %v is already registered.", kind)

	pool.types[kind] = T
	pool.registered += {kind}

	part_set_init(&pool.sets[kind], type_info_of(T), destroy_part, pool.allocator)
}

part_pool_is_registered :: proc(pool: ^Part_Pool($P), kind: P) -> bool {
	return kind in pool.registered
}

@(disabled = ODIN_DISABLE_ASSERT)
part_pool_assert_registered :: proc(pool: ^Part_Pool($P), kind: P, loc := #caller_location) {
	fmt.assertf(kind in pool.registered, "Part kind %v is not registered.", kind, loc = loc)
}

@(disabled = ODIN_DISABLE_ASSERT)
part_pool_assert_type :: proc(pool: ^Part_Pool($P), kind: P, $T: typeid, loc := #caller_location) {
	part_pool_assert_registered(pool, kind, loc)
	fmt.assertf(
		pool.types[kind] == T,
		"Part kind %v is a %v, not a %v.",
		kind,
		pool.types[kind],
		typeid_of(T),
		loc = loc,
	)
}

part_pool_count_parts :: proc(pool: ^Part_Pool($P), kind: P) -> int {
	part_pool_assert_registered(pool, kind)
	return part_set_count_parts(&pool.sets[kind])
}

part_pool_has :: proc(pool: ^Part_Pool($P), thing: Thing, kind: P) -> bool {
	part_pool_assert_registered(pool, kind)
	return part_set_has(&pool.sets[kind], thing)
}

// Returns nil when the thing does not have the part.
part_pool_get :: proc(pool: ^Part_Pool($P), thing: Thing, kind: P, $T: typeid) -> ^T {
	part_pool_assert_type(pool, kind, T)
	return cast(^T)part_set_get_part(&pool.sets[kind], thing)
}

// Assumes the thing has the part.
part_pool_get_unchecked :: proc(pool: ^Part_Pool($P), thing: Thing, kind: P, $T: typeid) -> ^T {
	part_pool_assert_type(pool, kind, T)
	return cast(^T)part_set_get_part_unchecked(&pool.sets[kind], thing)
}

part_pool_get_parts :: proc(pool: ^Part_Pool($P), kind: P, $T: typeid) -> []T {
	part_pool_assert_type(pool, kind, T)

	set := &pool.sets[kind]
	return ([^]T)(raw_data(set.parts_data))[:part_set_count_parts(set)]
}

part_pool_get_things :: proc(pool: ^Part_Pool($P), kind: P) -> []Thing {
	part_pool_assert_registered(pool, kind)
	return part_set_get_things(&pool.sets[kind])
}

// Inserts the part, or overwrites the one the thing already has.
part_pool_set_value :: proc(pool: ^Part_Pool($P), thing: Thing, kind: P, part: $T) -> ^T {
	part := part
	return part_pool_set_pointer(pool, thing, kind, &part)
}

// Assumes the thing does not have the part yet.
part_pool_set_value_unchecked :: proc(
	pool: ^Part_Pool($P),
	thing: Thing,
	kind: P,
	part: $T,
) -> ^T {
	part := part
	return part_pool_set_pointer_unchecked(pool, thing, kind, &part)
}

// Inserts the part, or overwrites the one the thing already has. A nil `part` zeroes it.
part_pool_set_pointer :: proc(pool: ^Part_Pool($P), thing: Thing, kind: P, part: ^$T) -> ^T {
	part_pool_assert_type(pool, kind, T)
	return cast(^T)part_set_insert(&pool.sets[kind], thing, part)
}

// Assumes the thing does not have the part yet. A nil `part` zeroes it.
part_pool_set_pointer_unchecked :: proc(
	pool: ^Part_Pool($P),
	thing: Thing,
	kind: P,
	part: ^$T,
) -> ^T {
	part_pool_assert_type(pool, kind, T)
	return cast(^T)part_set_insert_unchecked(&pool.sets[kind], thing, part)
}

// Untyped `set_pointer`, `part` has to point to a value of the registered type.
part_pool_set_raw :: proc(pool: ^Part_Pool($P), thing: Thing, kind: P, part: rawptr) -> rawptr {
	part_pool_assert_registered(pool, kind)
	return part_set_insert(&pool.sets[kind], thing, part)
}

// Untyped `set_pointer_unchecked`, `part` has to point to a value of the registered type.
part_pool_set_raw_unchecked :: proc(
	pool: ^Part_Pool($P),
	thing: Thing,
	kind: P,
	part: rawptr,
) -> rawptr {
	part_pool_assert_registered(pool, kind)
	return part_set_insert_unchecked(&pool.sets[kind], thing, part)
}

part_pool_remove :: proc(pool: ^Part_Pool($P), thing: Thing, kind: P) -> bool {
	part_pool_assert_registered(pool, kind)
	return part_set_remove(&pool.sets[kind], thing)
}

// Assumes the thing has the part.
part_pool_remove_unchecked :: proc(pool: ^Part_Pool($P), thing: Thing, kind: P) {
	part_pool_assert_registered(pool, kind)
	part_set_remove_unchecked(&pool.sets[kind], thing)
}

// Tries every registered kind. When the kinds of the thing are known, prefer `remove_unchecked`.
part_pool_remove_all :: proc(pool: ^Part_Pool($P), thing: Thing) {
	for kind in pool.registered {
		part_set_remove(&pool.sets[kind], thing)
	}
}

// >------------------------------------------------------------------ Internals

@(private = "file")
dense_idx :: proc(set: ^Part_Set, thing: Thing) -> (int, bool) {
	entry := inline_paged_array_get(&set.indices, int(thing.idx))
	if entry == 0 do return 0, false

	idx := int(entry - 1)
	return idx, set.things[idx] == thing
}

@(private = "file")
dense_idx_unchecked :: proc(set: ^Part_Set, thing: Thing) -> int {
	return int(inline_paged_array_get_unchecked(&set.indices, int(thing.idx)) - 1)
}

@(private = "file")
parts_destroy_all :: proc(set: ^Part_Set) {
	if set.destroy_part == nil do return

	for i in 0 ..< set.parts_size {
		part := parts_get_unchecked(set, i)
		set.destroy_part(part)
	}
}

@(private = "file")
parts_remove_swap :: proc(set: ^Part_Set, target_idx: int) {
	last_idx := set.parts_size - 1

	target := parts_get_unchecked(set, target_idx)
	last := parts_get_unchecked(set, last_idx)

	if set.destroy_part != nil do set.destroy_part(target)
	if target_idx != last_idx do mem.copy(target, last, set.part_size)

	set.parts_size -= 1
}

@(private = "file")
parts_append :: proc(set: ^Part_Set, part: rawptr) -> rawptr {
	// `part` may point into this set, which growing would move.
	data := uintptr(raw_data(set.parts_data))
	in_pool :=
		part != nil && uintptr(part) >= data && uintptr(part) < data + uintptr(len(set.parts_data))
	offset := uintptr(part) - data

	result := parts_alloc(set)

	src := part
	if in_pool do src = rawptr(uintptr(raw_data(set.parts_data)) + offset)
	parts_write(set, result, src)

	return result
}

@(private = "file")
parts_alloc :: proc(set: ^Part_Set) -> rawptr {
	parts_ensure_capacity(set, set.parts_size + 1)

	part := parts_get_unchecked(set, set.parts_size)
	set.parts_size += 1

	return part
}

@(private = "file")
parts_write :: proc(set: ^Part_Set, dst: rawptr, src: rawptr) {
	if set.part_size == 0 do return

	if src != nil {
		mem.copy(dst, src, set.part_size)
	} else {
		mem.zero(dst, set.part_size)
	}
}

@(private = "file")
parts_get_unchecked :: proc(set: ^Part_Set, idx: int) -> rawptr {
	if set.part_size == 0 do return &Part_Zero_Sized

	offset := uintptr(idx * set.part_size)
	return rawptr(uintptr(raw_data(set.parts_data)) + offset)
}

@(private = "file")
parts_ensure_capacity :: proc(set: ^Part_Set, capacity: int) {
	if capacity <= set.parts_capacity do return

	new_capacity := set.parts_capacity
	if new_capacity == 0 do new_capacity = 1
	for new_capacity < capacity do new_capacity *= 2

	things, things_err := make([]Thing, new_capacity, set.allocator)
	if things_err != nil do panic("Failed to allocate memory for part set.")

	copy(things, set.things[:set.parts_size])
	delete(set.things, set.allocator)
	set.things = things

	if set.part_size > 0 {
		data, data_err := mem.resize_bytes(
			set.parts_data,
			new_capacity * set.part_size,
			set.part_align,
			set.allocator,
		)
		if data_err != nil do panic("Failed to allocate memory for part set.")

		set.parts_data = data
	}

	set.parts_capacity = new_capacity
}
