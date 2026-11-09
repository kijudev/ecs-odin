package ecs

import "core:mem"

// >-------------------------------------------------------- Constants and Types

Handle_Idx :: u32
Handle_Gen :: u16

/* The untyped bits of a handle: `idx` picks the slot, `gen` tells reuses of it apart. */
Handle_Raw :: bit_field u32 {
	idx: Handle_Idx | HANDLE_IDX_BITS,
	gen: Handle_Gen | HANDLE_GEN_BITS,
}

/*
An opaque handle tagged with `T`, so handles of different tags can't be mixed up. A zeroed
handle is nil. Build one with `handle_make`.
*/
Handle :: struct($T: typeid) {
	using raw: Handle_Raw,
}

/*
Hands out and validates handles of tag `T`. It stores no data, anything that needs data per
handle keeps its own array indexed by `handle.idx`. Slot 0 is reserved for the nil handle, so a
pool of capacity N holds at most N - 1 handles.
*/
Handle_Pool :: struct($T: typeid) {
	slots:      []Handle_Slot,
	free:       []Handle_Idx,
	slots_next: int,
	free_count: int,
	allocator:  mem.Allocator,
}

/* The current `gen` of a slot and whether a handle to it is alive. */
Handle_Slot :: bit_field u16 {
	gen:      Handle_Gen | HANDLE_GEN_BITS,
	is_alive: bool       | 1,
}

// >--------------------------------------------------------------------- Handle

/*
Makes a handle from its parts. Use it instead of a composite literal: fields promoted from a
`using` bit_field are silently dropped there, so `Handle(T){idx = 1}` is nil.

Asserts:
- `idx` is less than HANDLE_IDX_COUNT.
- `gen` is less than HANDLE_GEN_COUNT.
*/
handle_make :: proc($T: typeid, idx: Handle_Idx, gen: Handle_Gen = 0) -> Handle(T) {
	assert(idx < HANDLE_IDX_COUNT, "Handle idx has to be less than HANDLE_IDX_COUNT.")
	assert(gen < HANDLE_GEN_COUNT, "Handle gen has to be less than HANDLE_GEN_COUNT.")

	return Handle(T){raw = {idx = idx, gen = gen}}
}

// >---------------------------------------------------------------- Handle_Pool

/*
Initializes the pool with room for `capacity - 1` handles, allocated up front with `allocator`.

Asserts:
- `capacity` is between HANDLE_POOL_MIN_CAPACITY and HANDLE_POOL_MAX_CAPACITY.
*/
handle_pool_init :: proc(
	pool: ^Handle_Pool($T),
	capacity: int,
	allocator: mem.Allocator = context.allocator,
) {
	assert(
		capacity >= HANDLE_POOL_MIN_CAPACITY,
		"Handle pool capacity has to be greater or equal to HANDLE_POOL_MIN_CAPACITY.",
	)

	assert(
		capacity <= HANDLE_POOL_MAX_CAPACITY,
		"Handle pool capacity has to be less or equal to HANDLE_POOL_MAX_CAPACITY.",
	)

	slots, slots_err := make([]Handle_Slot, capacity, allocator)
	if slots_err != nil do panic("Failed to allocate memory for handle pool.")

	free, free_err := make([]Handle_Idx, capacity, allocator)
	if free_err != nil do panic("Failed to allocate memory for handle pool.")

	pool^ = Handle_Pool(T) {
		slots      = slots,
		free       = free,
		slots_next = 1,
		free_count = 0,
		allocator  = allocator,
	}
}

/* Frees the pool with the allocator it was initialized with and zeroes it. */
handle_pool_destroy :: proc(pool: ^Handle_Pool($T)) {
	delete(pool.slots, pool.allocator)
	delete(pool.free, pool.allocator)
	pool^ = Handle_Pool(T){}
}

/*
Kills every handle and starts every slot over at gen 0. Handles from before the reset can match
new ones again, so drop them all.
*/
handle_pool_reset :: proc(pool: ^Handle_Pool($T)) {
	mem.zero_slice(pool.slots)
	mem.zero_slice(pool.free)
	pool.free_count = 0
	pool.slots_next = 1
}

/* Counts the handles that are alive. */
handle_pool_count_alive :: proc(pool: ^Handle_Pool($T)) -> int {
	return pool.slots_next - 1 - pool.free_count
}

/*
Spawns a handle, reusing the most recently killed slot first. Reusing a slot bumps its `gen`, so
old handles to it stay dead. The gen wraps after HANDLE_GEN_COUNT reuses of the same slot.

Returns the nil handle when the pool is full.
*/
handle_pool_spawn :: proc(pool: ^Handle_Pool($T)) -> Handle(T) {
	if (pool.free_count > 0) {
		idx := pool.free[pool.free_count - 1]
		pool.free_count -= 1

		slot := &pool.slots[idx]
		slot.is_alive = true
		slot.gen += 1

		return handle_make(T, idx, slot.gen)
	} else {
		if pool.slots_next >= len(pool.slots) do return Handle(T){}

		idx := pool.slots_next
		pool.slots[idx] = Handle_Slot {
			gen      = 0,
			is_alive = true,
		}

		pool.slots_next += 1
		return handle_make(T, Handle_Idx(idx))
	}
}

/*
Checks whether the handle is alive.

Returns false for the nil handle, a stale handle and an `idx` out of range.
*/
handle_pool_is_alive :: proc(pool: ^Handle_Pool($T), handle: Handle(T)) -> bool {
	if (int(handle.idx) >= len(pool.slots)) do return false

	slot := pool.slots[handle.idx]
	return slot.is_alive && slot.gen == handle.gen
}

/* Counts the killed slots waiting to be reused by `handle_pool_spawn`. */
handle_pool_count_free :: proc(pool: ^Handle_Pool($T)) -> int {
	return pool.free_count
}

/*
Kills the handle, freeing its slot for reuse.

Returns false if the handle is already dead.
*/
handle_pool_kill :: proc(pool: ^Handle_Pool($T), handle: Handle(T)) -> bool {
	if (handle_pool_is_alive(pool, handle)) {
		handle_pool_kill_unchecked(pool, handle)
		return true
	}

	return false
}

/*
Kills the handle without checking it. The handle has to be alive: killing a dead one puts its
slot on the free stack twice.
*/
handle_pool_kill_unchecked :: proc(pool: ^Handle_Pool($T), handle: Handle(T)) {
	slot := &pool.slots[handle.idx]
	slot.is_alive = false
	pool.free[pool.free_count] = handle.idx
	pool.free_count += 1
}
