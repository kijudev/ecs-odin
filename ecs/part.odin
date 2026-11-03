package ecs

import "base:runtime"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

PART_POOL_PAGE_COUNT :: 1 << 6
PART_POOL_PAGE_BITS :: THING_IDX_BITS - 6
PART_POOL_PAGE_SIZE :: 1 << PART_POOL_PAGE_BITS
PART_POOL_MAX_CAPACITY :: THING_MAX_IDX
PART_MAX_COUNT :: 128

#assert(PART_POOL_PAGE_COUNT * PART_POOL_PAGE_SIZE == THING_MAX_IDX)

Part_Idx :: u32
Part_Pool_Page :: [PART_POOL_PAGE_SIZE]Part_Idx

Part_Pool :: struct {
	part_info:      ^runtime.Type_Info,
	part_size:      int,
	part_align:     int,
	indices:        [PART_POOL_PAGE_COUNT]^Part_Pool_Page,
	things:         []Thing,
	parts_data:     []byte,
	parts_capacity: int,
	parts_size:     int,
	destroy_part:   proc(part: rawptr),
	allocator:      mem.Allocator,
}

@(private = "file")
zero_sized_part: u8

// >------------------------------------------------------------------ Part_Pool

part_pool_init :: proc(
	pool: ^Part_Pool,
	part_info: ^runtime.Type_Info,
	destroy_part: proc(part: rawptr) = nil,
	allocator: mem.Allocator = context.allocator,
) {
	assert(part_info != nil, "Part pool needs the part type info.")

	pool^ = Part_Pool {
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
}

part_pool_destroy :: proc(pool: ^Part_Pool) {
	parts_destroy_all(pool)
	pages_free_all(pool)

	delete(pool.things, pool.allocator)
	delete(pool.parts_data, pool.allocator)
	pool^ = Part_Pool{}
}

part_pool_reset :: proc(pool: ^Part_Pool) {
	parts_destroy_all(pool)
	pages_free_all(pool)
	pool.parts_size = 0
}

part_pool_count :: proc(pool: ^Part_Pool) -> int {
	return pool.parts_size
}

part_pool_capacity :: proc(pool: ^Part_Pool) -> int {
	return pool.parts_capacity
}

part_pool_has :: proc(pool: ^Part_Pool, thing: Thing) -> bool {
	_, ok := dense_idx(pool, thing)
	return ok
}

part_pool_get :: proc(pool: ^Part_Pool, thing: Thing) -> rawptr {
	idx, ok := dense_idx(pool, thing)
	if !ok do return nil

	return parts_get_unchecked(pool, idx)
}

part_pool_get_unchecked :: proc(pool: ^Part_Pool, thing: Thing) -> rawptr {
	return parts_get_unchecked(pool, dense_idx_unchecked(pool, thing))
}

part_pool_insert :: proc(pool: ^Part_Pool, thing: Thing, part: rawptr = nil) -> rawptr {
	assert(thing != THING_NIL, "Cannot insert a part for THING_NIL.")

	page := pool.indices[page_idx(thing.idx)]
	if page == nil || page[page_offset(thing.idx)] == 0 {
		return part_pool_insert_unchecked(pool, thing, part)
	}

	idx := int(page[page_offset(thing.idx)] - 1)
	pool.things[idx] = thing

	result := parts_get_unchecked(pool, idx)
	if result == part do return result

	if pool.destroy_part != nil do pool.destroy_part(result)
	parts_write(pool, result, part)

	return result
}

part_pool_insert_unchecked :: proc(pool: ^Part_Pool, thing: Thing, part: rawptr = nil) -> rawptr {
	assert(thing != THING_NIL, "Cannot insert a part for THING_NIL.")
	assert(pool.parts_size < PART_POOL_MAX_CAPACITY, "Part pool is full.")

	page := ensure_page(pool, page_idx(thing.idx))

	idx := pool.parts_size
	result := parts_append(pool, part)

	pool.things[idx] = thing
	page[page_offset(thing.idx)] = Part_Idx(idx + 1)

	return result
}

part_pool_remove :: proc(pool: ^Part_Pool, thing: Thing) -> bool {
	if !part_pool_has(pool, thing) do return false

	part_pool_remove_unchecked(pool, thing)
	return true
}

part_pool_remove_unchecked :: proc(pool: ^Part_Pool, thing: Thing) {
	idx := dense_idx_unchecked(pool, thing)
	last_idx := pool.parts_size - 1

	if idx != last_idx {
		moved := pool.things[last_idx]
		pool.things[idx] = moved
		pool.indices[page_idx(moved.idx)][page_offset(moved.idx)] = Part_Idx(idx + 1)
	}

	pool.indices[page_idx(thing.idx)][page_offset(thing.idx)] = 0
	parts_remove_swap(pool, idx)
}

part_pool_slice :: proc(pool: ^Part_Pool) -> []byte {
	return pool.parts_data[:pool.parts_size * pool.part_size]
}

part_pool_thing_slice :: proc(pool: ^Part_Pool) -> []Thing {
	return pool.things[:pool.parts_size]
}

// >------------------------------------------------------------------ Internals

@(private = "file")
ensure_page :: proc(pool: ^Part_Pool, idx: int) -> ^Part_Pool_Page {
	if pool.indices[idx] == nil {
		page, err := new(Part_Pool_Page, pool.allocator)
		if err != nil do panic("Failed to allocate memory for part pool page.")

		pool.indices[idx] = page
	}

	return pool.indices[idx]
}

@(private = "file")
page_idx :: #force_inline proc(idx: Thing_Idx) -> int {
	return int(idx >> PART_POOL_PAGE_BITS)
}

@(private = "file")
page_offset :: #force_inline proc(idx: Thing_Idx) -> int {
	return int(idx & (PART_POOL_PAGE_SIZE - 1))
}

@(private = "file")
dense_idx :: proc(pool: ^Part_Pool, thing: Thing) -> (int, bool) {
	page := pool.indices[page_idx(thing.idx)]
	if page == nil do return 0, false

	entry := page[page_offset(thing.idx)]
	if entry == 0 do return 0, false

	idx := int(entry - 1)
	return idx, pool.things[idx] == thing
}

@(private = "file")
dense_idx_unchecked :: proc(pool: ^Part_Pool, thing: Thing) -> int {
	return int(pool.indices[page_idx(thing.idx)][page_offset(thing.idx)] - 1)
}

@(private = "file")
pages_free_all :: proc(pool: ^Part_Pool) {
	for page in pool.indices {
		if page != nil do mem.free(page, pool.allocator)
	}

	pool.indices = {}
}

@(private = "file")
parts_destroy_all :: proc(pool: ^Part_Pool) {
	if pool.destroy_part == nil do return

	for i in 0 ..< pool.parts_size {
		part := parts_get_unchecked(pool, i)
		pool.destroy_part(part)
	}
}

@(private = "file")
parts_remove_swap :: proc(pool: ^Part_Pool, target_idx: int) {
	last_idx := pool.parts_size - 1

	target := parts_get_unchecked(pool, target_idx)
	last := parts_get_unchecked(pool, last_idx)

	if pool.destroy_part != nil do pool.destroy_part(target)
	if target_idx != last_idx do mem.copy(target, last, pool.part_size)

	pool.parts_size -= 1
}

@(private = "file")
parts_append :: proc(pool: ^Part_Pool, part: rawptr) -> rawptr {
	// `part` may point into this pool, which growing would move.
	data := uintptr(raw_data(pool.parts_data))
	in_pool :=
		part != nil &&
		uintptr(part) >= data &&
		uintptr(part) < data + uintptr(len(pool.parts_data))
	offset := uintptr(part) - data

	result := parts_alloc(pool)

	src := part
	if in_pool do src = rawptr(uintptr(raw_data(pool.parts_data)) + offset)
	parts_write(pool, result, src)

	return result
}

@(private = "file")
parts_alloc :: proc(pool: ^Part_Pool) -> rawptr {
	parts_ensure_capacity(pool, pool.parts_size + 1)

	part := parts_get_unchecked(pool, pool.parts_size)
	pool.parts_size += 1

	return part
}

@(private = "file")
parts_write :: proc(pool: ^Part_Pool, dst: rawptr, src: rawptr) {
	if pool.part_size == 0 do return

	if src != nil {
		mem.copy(dst, src, pool.part_size)
	} else {
		mem.zero(dst, pool.part_size)
	}
}

@(private = "file")
parts_get_unchecked :: proc(pool: ^Part_Pool, idx: int) -> rawptr {
	if pool.part_size == 0 do return &zero_sized_part

	offset := uintptr(idx * pool.part_size)
	return rawptr(uintptr(raw_data(pool.parts_data)) + offset)
}

@(private = "file")
parts_ensure_capacity :: proc(pool: ^Part_Pool, capacity: int) {
	if capacity <= pool.parts_capacity do return

	new_capacity := pool.parts_capacity
	if new_capacity == 0 do new_capacity = 1
	for new_capacity < capacity do new_capacity *= 2

	things, things_err := make([]Thing, new_capacity, pool.allocator)
	if things_err != nil do panic("Failed to allocate memory for part pool.")

	copy(things, pool.things[:pool.parts_size])
	delete(pool.things, pool.allocator)
	pool.things = things

	if pool.part_size > 0 {
		data, data_err := mem.resize_bytes(
			pool.parts_data,
			new_capacity * pool.part_size,
			pool.part_align,
			pool.allocator,
		)
		if data_err != nil do panic("Failed to allocate memory for part pool.")

		pool.parts_data = data
	}

	pool.parts_capacity = new_capacity
}
