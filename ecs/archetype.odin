package ecs

import "base:intrinsics"
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
	assert(
		capacity >= ARCHETYPE_POOL_MIN_CAPACITY,
		"Archetype pool capacity has to be greater or equal to ARCHETYPE_POOL_MIN_CAPACITY.",
	)

	assert(
		capacity <= ARCHETYPE_POOL_MAX_CAPACITY,
		"Archetype pool capacity has to be less or equal to ARCHETYPE_POOL_MAX_CAPACITY.",
	)

	pool^ = Archetype_Pool(P) {
		slots     = make([]Archetype(P), capacity, allocator),
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
	return kind in pool.slots[thing.idx].mask
}

archetype_pool_insert :: proc(pool: ^Archetype_Pool($P), thing: Thing, kind: P) {
	pool.slots[thing.idx].mask += {kind}
}

archetype_pool_remove :: proc(pool: ^Archetype_Pool($P), thing: Thing, kind: P) {
	pool.slots[thing.idx].mask -= {kind}
}
