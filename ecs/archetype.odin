package ecs

import "base:intrinsics"
import "core:fmt"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

/* The set of part kinds a thing has. */
Archetype :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	kinds: bit_set[K],
}

/* Iterates the kinds of an archetype in enum order. Make one with `archetype_iter_make`. */
Archetype_Iter :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	rest: bit_set[K],
}

/*
Tracks the archetype of every thing, indexed by `thing.idx`. Gens are not checked, so a stale
thing gets the archetype of whatever thing now has its slot.
*/
Archetype_Pool :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	slots:     []Archetype(K),
	allocator: mem.Allocator,
}

// >------------------------------------------------------------------ Archetype

/* Makes an archetype of the kinds. */
archetype_make :: proc(kinds: bit_set[$K]) -> Archetype(K) {
	return Archetype(K){kinds = kinds}
}

/* Checks whether the archetype has the kind. */
archetype_has :: proc(archetype: Archetype($K), kind: K) -> bool {
	return kind in archetype.kinds
}

/* Checks whether the archetype has no kinds. */
archetype_is_empty :: proc(archetype: Archetype($K)) -> bool {
	return archetype.kinds == {}
}

/* Checks whether the archetype has every kind of `other`. */
archetype_contains :: proc(archetype: Archetype($K), other: Archetype(K)) -> bool {
	return archetype.kinds & other.kinds == other.kinds
}

/* Checks whether the archetypes have no kinds in common. */
archetype_is_disjoint :: proc(archetype: Archetype($K), other: Archetype(K)) -> bool {
	return archetype.kinds & other.kinds == {}
}

/* Gets the kinds both archetypes have. */
archetype_intersect :: proc(archetype: Archetype($K), other: Archetype(K)) -> Archetype(K) {
	return Archetype(K){kinds = archetype.kinds & other.kinds}
}

/* Adds the kind to the archetype. */
archetype_insert :: proc(archetype: ^Archetype($K), kind: K) {
	archetype.kinds += {kind}
}

/* Removes the kind from the archetype. */
archetype_remove :: proc(archetype: ^Archetype($K), kind: K) {
	archetype.kinds -= {kind}
}

/* Removes every kind from the archetype. */
archetype_clear :: proc(archetype: ^Archetype($K)) {
	archetype.kinds = {}
}

/* Makes an iterator over the archetype's kinds. */
archetype_iter_make :: proc(archetype: Archetype($K)) -> Archetype_Iter(K) {
	return Archetype_Iter(K){rest = archetype.kinds}
}

/*
Advances the iterator.

Returns the next kind and true, or false once every kind was returned.
*/
archetype_iter :: proc(it: ^Archetype_Iter($K)) -> (K, bool) {
	for kind in it.rest {
		it.rest -= {kind}
		return kind, true
	}

	return K{}, false
}

// >------------------------------------------------------------- Archetype_Pool

/*
Initializes the pool with room for `capacity` things, allocated up front with `allocator`. Every
archetype starts empty.

Asserts:
- `capacity` is between ARCHETYPE_POOL_MIN_CAPACITY and ARCHETYPE_POOL_MAX_CAPACITY.
*/
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

/* Frees the pool with the allocator it was initialized with and zeroes it. */
archetype_pool_destroy :: proc(pool: ^Archetype_Pool($K)) {
	delete(pool.slots, pool.allocator)
	pool^ = Archetype_Pool(K){}
}

/* Empties every archetype. */
archetype_pool_reset :: proc(pool: ^Archetype_Pool($K)) {
	mem.zero_slice(pool.slots)
}

/*
Checks whether the thing's archetype has the kind.

Asserts:
- `thing.idx` is less than the pool capacity.
*/
archetype_pool_has :: proc(pool: Archetype_Pool($K), thing: Thing, kind: K) -> bool {
	check_thing(thing, len(pool.slots))
	return archetype_has(pool.slots[thing.idx], kind)
}

/*
Adds the kind to the thing's archetype.

Asserts:
- `thing.idx` is less than the pool capacity.
*/
archetype_pool_insert :: proc(pool: ^Archetype_Pool($K), thing: Thing, kind: K) {
	check_thing(thing, len(pool.slots))
	archetype_insert(&pool.slots[thing.idx], kind)
}

/*
Removes the kind from the thing's archetype.

Asserts:
- `thing.idx` is less than the pool capacity.
*/
archetype_pool_remove :: proc(pool: ^Archetype_Pool($K), thing: Thing, kind: K) {
	check_thing(thing, len(pool.slots))
	archetype_remove(&pool.slots[thing.idx], kind)
}

/*
Empties the thing's archetype.

Asserts:
- `thing.idx` is less than the pool capacity.
*/
archetype_pool_remove_all :: proc(pool: ^Archetype_Pool($K), thing: Thing) {
	check_thing(thing, len(pool.slots))
	archetype_clear(&pool.slots[thing.idx])
}

/*
Gets the thing's archetype.

Asserts:
- `thing.idx` is less than the pool capacity.
*/
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
