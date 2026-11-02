package ecs

import "core:mem"
// >-------------------------------------------------------- Constants and Types

Thing_Idx :: u32
Thing_Gen :: u16
THING_IDX_BITS :: 20
THING_GEN_BITS :: 12
THING_MAX_IDX :: 1 << THING_IDX_BITS
THING_MAX_GEN :: 1 << THING_GEN_BITS
THING_NIL :: Thing{}

Thing :: bit_field u32 {
	idx: Thing_Idx | THING_IDX_BITS,
	gen: Thing_Gen | THING_GEN_BITS,
}

THING_POOL_MIN_CAPACITY :: 64
THING_POOL_MAX_CAPACITY :: 1 << THING_IDX_BITS
THING_POOL_DEFAULT_CAPACITY :: 1 << 16

Thing_Pool :: struct {
	slots:      []Thing_Slot,
	free:       []Thing_Idx,
	slots_next: int,
	free_count: int,
}

Thing_Slot :: bit_field u16 {
	gen:      Thing_Gen | THING_GEN_BITS,
	is_alive: bool      | 1,
}

// >----------------------------------------------------------------- Thing_Pool

thing_pool_init :: proc(capacity: int = THING_POOL_DEFAULT_CAPACITY) -> Thing_Pool {
	assert(
		capacity >= THING_POOL_MIN_CAPACITY,
		"Thing pool capacity has to be greater or equal to THING_POOL_MIN_CAPACITY.",
	)

	assert(
		capacity <= THING_POOL_MAX_CAPACITY,
		"Thing pool capacity has to be less or equal to THING_POOL_MAX_CAPACITY.",
	)

	pool := Thing_Pool {
		slots      = make([]Thing_Slot, capacity),
		free       = make([]Thing_Idx, capacity),
		slots_next = 1,
		free_count = 0,
	}

	return pool
}

thing_pool_destroy :: proc(pool: ^Thing_Pool) {
	delete(pool.slots)
	delete(pool.free)
	pool^ = Thing_Pool{}
}

thing_pool_reset :: proc(pool: ^Thing_Pool) {
	mem.zero_slice(pool.slots)
	mem.zero_slice(pool.free)
	pool.free_count = 0
	pool.slots_next = 1
}

thing_pool_capacity :: proc(pool: Thing_Pool) -> int {
	return len(pool.slots)
}

thing_pool_alive_count :: proc(pool: Thing_Pool) -> int {
	return pool.slots_next - 1 - pool.free_count
}

thing_pool_free_count :: proc(pool: Thing_Pool) -> int {
	return pool.free_count
}

thing_pool_spawn :: proc(pool: ^Thing_Pool) -> Thing {
	if (pool.free_count > 0) {
		idx := pool.free[pool.free_count - 1]
		pool.free_count -= 1

		slot := &pool.slots[idx]
		slot.is_alive = true
		slot.gen += 1

		return Thing{idx = idx, gen = slot.gen}
	} else {
		assert(pool.slots_next < thing_pool_capacity(pool^), "Thing pool is full.")

		idx := pool.slots_next
		pool.slots[idx] = Thing_Slot {
			gen      = 0,
			is_alive = true,
		}

		pool.slots_next += 1
		return Thing{idx = Thing_Idx(idx), gen = 0}
	}
}

thing_pool_check :: proc(pool: Thing_Pool, thing: Thing) -> bool {
	if (int(thing.idx) >= len(pool.slots)) do return false

	slot := pool.slots[thing.idx]
	return slot.is_alive && slot.gen == thing.gen
}

thing_pool_kill :: proc(pool: ^Thing_Pool, thing: Thing) -> bool {
	if (thing_pool_check(pool^, thing)) {
		thing_pool_kill_unchecked(pool, thing)
		return true
	}

	return false
}

thing_pool_kill_unchecked :: proc(pool: ^Thing_Pool, thing: Thing) {
	slot := &pool.slots[thing.idx]
	slot.is_alive = false
	pool.free[pool.free_count] = thing.idx
	pool.free_count += 1
}
