package ecs

import "base:intrinsics"
import "core:fmt"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

Archetype :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	kinds: bit_set[K],
}

Archetype_Iter :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	rest: bit_set[K],
}

Archetype_Pool :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	slots:     []Archetype(K),
	allocator: mem.Allocator,
}

ARCHETYPE_POOL_MIN_CAPACITY :: THING_POOL_MIN_CAPACITY
ARCHETYPE_POOL_MAX_CAPACITY :: THING_POOL_MAX_CAPACITY
ARCHETYPE_POOL_DEFAULT_CAPACITY :: THING_POOL_DEFAULT_CAPACITY

// >------------------------------------------------------------------ Archetype

archetype_make :: proc(kinds: bit_set[$K]) -> Archetype(K) {
	return Archetype(K){kinds = kinds}
}

archetype_has :: proc(archetype: Archetype($K), kind: K) -> bool {
	return kind in archetype.kinds
}

archetype_is_empty :: proc(archetype: Archetype($K)) -> bool {
	return archetype.kinds == {}
}

archetype_contains :: proc(archetype: Archetype($K), other: Archetype(K)) -> bool {
	return archetype.kinds & other.kinds == other.kinds
}

archetype_is_disjoint :: proc(archetype: Archetype($K), other: Archetype(K)) -> bool {
	return archetype.kinds & other.kinds == {}
}

archetype_intersect :: proc(archetype: Archetype($K), other: Archetype(K)) -> Archetype(K) {
	return Archetype(K){kinds = archetype.kinds & other.kinds}
}

archetype_insert :: proc(archetype: ^Archetype($K), kind: K) {
	archetype.kinds += {kind}
}

archetype_remove :: proc(archetype: ^Archetype($K), kind: K) {
	archetype.kinds -= {kind}
}

archetype_clear :: proc(archetype: ^Archetype($K)) {
	archetype.kinds = {}
}

archetype_iter_make :: proc(archetype: Archetype($K)) -> Archetype_Iter(K) {
	return Archetype_Iter(K){rest = archetype.kinds}
}

archetype_iter_next :: proc(it: ^Archetype_Iter($K)) -> (K, bool) {
	for kind in it.rest {
		it.rest -= {kind}
		return kind, true
	}

	return K{}, false
}

// >------------------------------------------------------------- Archetype_Pool

archetype_pool_init :: proc(
	pool: ^Archetype_Pool($K),
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

	slots, err := make([]Archetype(K), capacity, allocator)
	if err != nil do panic("Failed to allocate memory for archetype pool.")

	pool^ = Archetype_Pool(K) {
		slots     = slots,
		allocator = allocator,
	}
}

archetype_pool_destroy :: proc(pool: ^Archetype_Pool($K)) {
	delete(pool.slots, pool.allocator)
	pool^ = Archetype_Pool(K){}
}

archetype_pool_reset :: proc(pool: ^Archetype_Pool($K)) {
	mem.zero_slice(pool.slots)
}

archetype_pool_has :: proc(pool: Archetype_Pool($K), thing: Thing, kind: K) -> bool {
	check_thing(thing, len(pool.slots))
	return archetype_has(pool.slots[thing.idx], kind)
}

archetype_pool_insert :: proc(pool: ^Archetype_Pool($K), thing: Thing, kind: K) {
	check_thing(thing, len(pool.slots))
	archetype_insert(&pool.slots[thing.idx], kind)
}

archetype_pool_remove :: proc(pool: ^Archetype_Pool($K), thing: Thing, kind: K) {
	check_thing(thing, len(pool.slots))
	archetype_remove(&pool.slots[thing.idx], kind)
}

archetype_pool_remove_all :: proc(pool: ^Archetype_Pool($K), thing: Thing) {
	check_thing(thing, len(pool.slots))
	archetype_clear(&pool.slots[thing.idx])
}

archetype_pool_get :: proc(pool: Archetype_Pool($K), thing: Thing) -> Archetype(K) {
	check_thing(thing, len(pool.slots))
	return pool.slots[thing.idx]
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
