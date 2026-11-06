package ecs

import "base:intrinsics"
import "core:fmt"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

Archetype :: struct($P: typeid) where intrinsics.type_is_enum(P) {
	kinds: bit_set[P],
}

Archetype_Iter :: struct($P: typeid) where intrinsics.type_is_enum(P) {
	rest: bit_set[P],
}

Archetype_Pool :: struct($P: typeid) where intrinsics.type_is_enum(P) {
	slots:     []Archetype(P),
	allocator: mem.Allocator,
}

ARCHETYPE_POOL_MIN_CAPACITY :: THING_POOL_MIN_CAPACITY
ARCHETYPE_POOL_MAX_CAPACITY :: THING_POOL_MAX_CAPACITY
ARCHETYPE_POOL_DEFAULT_CAPACITY :: THING_POOL_DEFAULT_CAPACITY

// >------------------------------------------------------------------ Archetype

archetype_make :: proc(kinds: bit_set[$P]) -> Archetype(P) {
	return Archetype(P){kinds = kinds}
}

archetype_has :: proc(archetype: Archetype($P), kind: P) -> bool {
	return kind in archetype.kinds
}

archetype_is_empty :: proc(archetype: Archetype($P)) -> bool {
	return archetype.kinds == {}
}

// Every kind of `other` is in `archetype`.
archetype_contains :: proc(archetype: Archetype($P), other: Archetype(P)) -> bool {
	return archetype.kinds & other.kinds == other.kinds
}

// No kind is in both.
archetype_is_disjoint :: proc(archetype: Archetype($P), other: Archetype(P)) -> bool {
	return archetype.kinds & other.kinds == {}
}

archetype_intersect :: proc(archetype: Archetype($P), other: Archetype(P)) -> Archetype(P) {
	return Archetype(P){kinds = archetype.kinds & other.kinds}
}

archetype_insert :: proc(archetype: ^Archetype($P), kind: P) {
	archetype.kinds += {kind}
}

archetype_remove :: proc(archetype: ^Archetype($P), kind: P) {
	archetype.kinds -= {kind}
}

archetype_clear :: proc(archetype: ^Archetype($P)) {
	archetype.kinds = {}
}

// Iterate with `for kind in archetype_iter_next(&it)`, in the order of the kinds in `P`.
archetype_iter_make :: proc(archetype: Archetype($P)) -> Archetype_Iter(P) {
	return Archetype_Iter(P){rest = archetype.kinds}
}

archetype_iter_next :: proc(it: ^Archetype_Iter($P)) -> (P, bool) {
	for kind in it.rest {
		it.rest -= {kind}
		return kind, true
	}

	return P{}, false
}

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

archetype_pool_has :: proc(pool: Archetype_Pool($P), thing: Thing, kind: P) -> bool {
	check_thing(thing, len(pool.slots))
	return archetype_has(pool.slots[thing.idx], kind)
}

archetype_pool_insert :: proc(pool: ^Archetype_Pool($P), thing: Thing, kind: P) {
	check_thing(thing, len(pool.slots))
	archetype_insert(&pool.slots[thing.idx], kind)
}

archetype_pool_remove :: proc(pool: ^Archetype_Pool($P), thing: Thing, kind: P) {
	check_thing(thing, len(pool.slots))
	archetype_remove(&pool.slots[thing.idx], kind)
}

archetype_pool_remove_all :: proc(pool: ^Archetype_Pool($P), thing: Thing) {
	check_thing(thing, len(pool.slots))
	archetype_clear(&pool.slots[thing.idx])
}

archetype_pool_get :: proc(pool: Archetype_Pool($P), thing: Thing) -> Archetype(P) {
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
