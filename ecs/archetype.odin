package ecs

import "base:intrinsics"
import "core:fmt"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

/*
Tracks the archetype of every thing, the `bit_set[K]` of part kinds it has, indexed by
`thing.idx`. Gens are not checked, so a stale thing gets the archetype of whatever thing now has
its slot.
*/
Archetype_Pool :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	slots:     []bit_set[K],
	allocator: mem.Allocator,
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

	slots, err := make([]bit_set[K], capacity, allocator)
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
archetype_pool_has :: proc(pool: ^Archetype_Pool($K), thing: Thing, kind: K) -> bool {
	check_thing(thing, len(pool.slots))
	return kind in pool.slots[thing.idx]
}

/*
Adds the kind to the thing's archetype.

Asserts:
- `thing.idx` is less than the pool capacity.
*/
archetype_pool_insert :: proc(pool: ^Archetype_Pool($K), thing: Thing, kind: K) {
	check_thing(thing, len(pool.slots))
	pool.slots[thing.idx] += {kind}
}

/*
Removes the kind from the thing's archetype.

Asserts:
- `thing.idx` is less than the pool capacity.
*/
archetype_pool_remove :: proc(pool: ^Archetype_Pool($K), thing: Thing, kind: K) {
	check_thing(thing, len(pool.slots))
	pool.slots[thing.idx] -= {kind}
}

/*
Empties the thing's archetype.

Asserts:
- `thing.idx` is less than the pool capacity.
*/
archetype_pool_remove_all :: proc(pool: ^Archetype_Pool($K), thing: Thing) {
	check_thing(thing, len(pool.slots))
	pool.slots[thing.idx] = {}
}

/*
Gets the thing's archetype.

Asserts:
- `thing.idx` is less than the pool capacity.
*/
archetype_pool_get :: #force_inline proc(pool: ^Archetype_Pool($K), thing: Thing) -> bit_set[K] {
	check_thing(thing, len(pool.slots))
	return pool.slots[thing.idx]
}

/*
Gets the thing's archetype without checking its idx. The idx has to be less than the pool
capacity.
*/
@(private)
archetype_pool_get_unchecked :: #force_inline proc(
	pool: ^Archetype_Pool($K),
	thing: Thing,
) -> bit_set[K] #no_bounds_check {
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
