package ecs

import "base:intrinsics"
import "core:fmt"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

Archetype :: struct($P: typeid) where intrinsics.type_is_enum(P) {
	mask: bit_set[P],
}

Archetype_Pool :: struct($P: typeid) where intrinsics.type_is_enum(P) {
	slots:     []Archetype(P),
	allocator: mem.Allocator,
}

ARCHETYPE_POOL_MIN_CAPACITY :: THING_POOL_MIN_CAPACITY
ARCHETYPE_POOL_MAX_CAPACITY :: THING_POOL_MAX_CAPACITY
ARCHETYPE_POOL_DEFAULT_CAPACITY :: THING_POOL_DEFAULT_CAPACITY

// >------------------------------------------------------------- Archetype_Pool

archetype_pool_init :: proc(
	pool: ^Archetype_Pool($P),
	capacity: int = ARCHETYPE_POOL_DEFAULT_CAPACITY,
	allocator: mem.Allocator = context.allocator,
) {
	fmt.assertf(
		capacity >= ARCHETYPE_POOL_MIN_CAPACITY && capacity <= ARCHETYPE_POOL_MAX_CAPACITY,
		"Archetype pool capacity has to be between %v and %v, got %v.",
		ARCHETYPE_POOL_MIN_CAPACITY,
		ARCHETYPE_POOL_MAX_CAPACITY,
		capacity,
	)

	slots, err := make([]Archetype(P), capacity, allocator)
	if err != nil do panic("Failed to allocate memory for archetype pool.")

	pool^ = Archetype_Pool(P) {
		slots     = slots,
		allocator = allocator,
	}
}

archetype_pool_destroy :: proc(pool: ^Archetype_Pool($P)) {
	delete(pool.slots, pool.allocator)
	pool^ = Archetype_Pool(P){}
}

archetype_pool_reset :: proc(pool: ^Archetype_Pool($P)) {
	mem.zero_slice(pool.slots)
}

archetype_pool_capacity :: proc(pool: Archetype_Pool($P)) -> int {
	return len(pool.slots)
}

archetype_pool_has :: proc(pool: Archetype_Pool($P), thing: Thing, kind: P) -> bool {
	check_thing(thing, len(pool.slots))
	return kind in pool.slots[thing.idx].mask
}

archetype_pool_insert :: proc(pool: ^Archetype_Pool($P), thing: Thing, kind: P) {
	check_thing(thing, len(pool.slots))
	pool.slots[thing.idx].mask += {kind}
}

archetype_pool_remove :: proc(pool: ^Archetype_Pool($P), thing: Thing, kind: P) {
	check_thing(thing, len(pool.slots))
	pool.slots[thing.idx].mask -= {kind}
}

archetype_pool_remove_all :: proc(pool: ^Archetype_Pool($P), thing: Thing) {
	check_thing(thing, len(pool.slots))
	pool.slots[thing.idx].mask = {}
}

archetype_pool_get_mask :: proc(pool: Archetype_Pool($P), thing: Thing) -> bit_set[P] {
	check_thing(thing, len(pool.slots))
	return pool.slots[thing.idx].mask
}

// >------------------------------------------------------------------ Internals

@(private = "file")
check_thing :: #force_inline proc(thing: Thing, capacity: int) {
	fmt.assertf(
		int(thing.idx) < capacity,
		"Thing idx %v is out of range of the archetype pool, the capacity is %v.",
		thing.idx,
		capacity,
	)
}
