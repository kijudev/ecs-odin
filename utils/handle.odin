package utils

import "core:mem"

// >-------------------------------------------------------- Constants and Types

Handle_Idx :: u32
Handle_Gen :: u16
HANDLE_IDX_BITS :: 20
HANDLE_GEN_BITS :: 12
HANDLE_MAX_IDX :: 1 << HANDLE_IDX_BITS
HANDLE_MAX_GEN :: 1 << HANDLE_GEN_BITS

Handle_Raw :: bit_field u32 {
	idx: Handle_Idx | HANDLE_IDX_BITS,
	gen: Handle_Gen | HANDLE_GEN_BITS,
}

// `T` only tags the handle so handles of different pools can't be mixed up.
Handle :: struct($T: typeid) {
	using raw: Handle_Raw,
}

HANDLE_POOL_MIN_CAPACITY :: 64
HANDLE_POOL_MAX_CAPACITY :: 1 << HANDLE_IDX_BITS

Handle_Pool :: struct($T: typeid) {
	slots:      []Handle_Slot,
	free:       []Handle_Idx,
	slots_next: int,
	free_count: int,
}

Handle_Slot :: bit_field u16 {
	gen:      Handle_Gen | HANDLE_GEN_BITS,
	is_alive: bool       | 1,
}

// >---------------------------------------------------------------- Handle_Pool

handle_pool_init :: proc($T: typeid, capacity: int) -> Handle_Pool(T) {
	assert(
		capacity >= HANDLE_POOL_MIN_CAPACITY,
		"Handle pool capacity has to be greater or equal to HANDLE_POOL_MIN_CAPACITY.",
	)

	assert(
		capacity <= HANDLE_POOL_MAX_CAPACITY,
		"Handle pool capacity has to be less or equal to HANDLE_POOL_MAX_CAPACITY.",
	)

	pool := Handle_Pool(T) {
		slots      = make([]Handle_Slot, capacity),
		free       = make([]Handle_Idx, capacity),
		slots_next = 1,
		free_count = 0,
	}

	return pool
}

handle_pool_destroy :: proc(pool: ^Handle_Pool($T)) {
	delete(pool.slots)
	delete(pool.free)
	pool^ = Handle_Pool(T){}
}

handle_pool_reset :: proc(pool: ^Handle_Pool($T)) {
	mem.zero_slice(pool.slots)
	mem.zero_slice(pool.free)
	pool.free_count = 0
	pool.slots_next = 1
}

handle_pool_capacity :: proc(pool: Handle_Pool($T)) -> int {
	return len(pool.slots)
}

handle_pool_alive_count :: proc(pool: Handle_Pool($T)) -> int {
	return pool.slots_next - 1 - pool.free_count
}

handle_pool_free_count :: proc(pool: Handle_Pool($T)) -> int {
	return pool.free_count
}

handle_pool_spawn :: proc(pool: ^Handle_Pool($T)) -> Handle(T) {
	if (pool.free_count > 0) {
		idx := pool.free[pool.free_count - 1]
		pool.free_count -= 1

		slot := &pool.slots[idx]
		slot.is_alive = true
		slot.gen += 1

		return Handle(T){raw = {idx = idx, gen = slot.gen}}
	} else {
		assert(pool.slots_next < handle_pool_capacity(pool^), "Handle pool is full.")

		idx := pool.slots_next
		pool.slots[idx] = Handle_Slot {
			gen      = 0,
			is_alive = true,
		}

		pool.slots_next += 1
		return Handle(T){raw = {idx = Handle_Idx(idx), gen = 0}}
	}
}

handle_pool_check :: proc(pool: Handle_Pool($T), handle: Handle(T)) -> bool {
	if (int(handle.idx) >= len(pool.slots)) do return false

	slot := pool.slots[handle.idx]
	return slot.is_alive && slot.gen == handle.gen
}

handle_pool_kill :: proc(pool: ^Handle_Pool($T), handle: Handle(T)) -> bool {
	if (handle_pool_check(pool^, handle)) {
		handle_pool_kill_unchecked(pool, handle)
		return true
	}

	return false
}

handle_pool_kill_unchecked :: proc(pool: ^Handle_Pool($T), handle: Handle(T)) {
	slot := &pool.slots[handle.idx]
	slot.is_alive = false
	pool.free[pool.free_count] = handle.idx
	pool.free_count += 1
}
