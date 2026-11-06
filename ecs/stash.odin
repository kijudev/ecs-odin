package ecs

import "base:intrinsics"
import "core:fmt"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

STASH_POOL_DEFAULT_CAPACITY :: 1 << 16

Stash_Pool :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	stashes_data:     []byte,
	stashes_size:     int,
	stashes_capacity: int,
	offsets:          [K]int,
	destroy_procs:      [K]proc(stash: rawptr),
	registered:       bit_set[K],
	types:            [K]typeid,
	allocator:        mem.Allocator,
}

// >----------------------------------------------------------------- Stash_Pool

stash_pool_init :: proc(
	pool: ^Stash_Pool($K),
	capacity: int = STASH_POOL_DEFAULT_CAPACITY,
	allocator := context.allocator,
) {
	fmt.assertf(capacity >= 0, "Stash pool capacity cannot be negative, got %v.", capacity)

	data, err := make([]byte, capacity, allocator)
	if err != nil do panic("Failed to allocate memory for stash pool.")

	pool^ = Stash_Pool(K) {
		stashes_data     = data,
		stashes_size     = 0,
		stashes_capacity = capacity,
		offsets          = [K]int{},
		allocator        = allocator,
	}
}

stash_pool_destroy :: proc(pool: ^Stash_Pool($K)) {
	destroy_all(pool)

	delete(pool.stashes_data, pool.allocator)
	pool^ = {}
}

stash_pool_reset :: proc(pool: ^Stash_Pool($K)) {
	destroy_all(pool)
	mem.zero_slice(pool.stashes_data[:pool.stashes_size])
}

stash_pool_register :: proc(
	pool: ^Stash_Pool($K),
	kind: K,
	$T: typeid,
	destroy: proc(stash: rawptr) = nil,
) {
	fmt.assertf(
		kind not_in pool.registered,
		"Stash kind %v is already registered.",
		kind,
	)

	// The buffer never moves, so aligning the address keeps the stash aligned for good.
	base := uintptr(raw_data(pool.stashes_data))
	start := mem.align_forward_uintptr(base + uintptr(pool.stashes_size), align_of(T))
	offset := int(start - base)

	required_size := offset + size_of(T)
	if required_size > pool.stashes_capacity {
		fmt.panicf(
			"Stash pool is out of memory: %v needs %v bytes, the capacity is %v. Consider increasing the capacity.",
			kind,
			required_size,
			pool.stashes_capacity,
		)
	}

	pool.stashes_size = required_size
	pool.offsets[kind] = offset
	pool.types[kind] = T
	pool.destroy_procs[kind] = destroy
	pool.registered += {kind}
}

stash_pool_is_registered :: proc(pool: ^Stash_Pool($K), kind: K) -> bool {
	return kind in pool.registered
}

@(disabled = ODIN_DISABLE_ASSERT)
stash_pool_assert_registered :: proc(
	pool: ^Stash_Pool($K),
	kind: K,
	loc := #caller_location,
) {
	fmt.assertf(
		kind in pool.registered,
		"Stash kind %v is not registered.",
		kind,
		loc = loc,
	)
}

@(disabled = ODIN_DISABLE_ASSERT)
stash_pool_assert_type :: proc(
	pool: ^Stash_Pool($K),
	kind: K,
	$T: typeid,
	loc := #caller_location,
) {
	stash_pool_assert_registered(pool, kind, loc)
	fmt.assertf(
		pool.types[kind] == T,
		"Stash kind %v is a %v, not a %v.",
		kind,
		pool.types[kind],
		typeid_of(T),
		loc = loc,
	)
}

stash_pool_get :: proc(pool: ^Stash_Pool($K), kind: K, $T: typeid) -> ^T {
	stash_pool_assert_type(pool, kind, T)
	return cast(^T)get_raw(pool, kind)
}

// >------------------------------------------------------------------ Internals

@(private = "file")
destroy_all :: proc(pool: ^Stash_Pool($K)) {
	for kind in pool.registered {
		destroy := pool.destroy_procs[kind]
		if destroy != nil do destroy(get_raw(pool, kind))
	}
}

@(private = "file")
get_raw :: proc(pool: ^Stash_Pool($K), kind: K) -> rawptr {
	offset := pool.offsets[kind]
	return rawptr(uintptr(raw_data(pool.stashes_data)) + uintptr(offset))
}
