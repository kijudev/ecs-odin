package ecs

import "base:intrinsics"
import "core:fmt"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

System_Info :: struct($P: typeid, $R: typeid, $S: typeid) where intrinsics.type_is_enum(P),
	intrinsics.type_is_enum(R),
	intrinsics.type_is_enum(S) {
	reads:  bit_set[P],
	writes: bit_set[P],
	stage:  S,
	system: proc(c: ^Stuff(P, R, S)),
}

System_Pool :: struct($P: typeid, $R: typeid, $S: typeid) where intrinsics.type_is_enum(P),
	intrinsics.type_is_enum(R),
	intrinsics.type_is_enum(S) {
	systems:          []System_Info(P, R, S),
	systems_size:     int,
	systems_capacity: int,
	allocator:        mem.Allocator,
}

SYSTEM_POOL_DEFAULT_CAPACITY :: 256

// >---------------------------------------------------------------- System_Pool

system_pool_init :: proc(
	pool: ^System_Pool($P, $R, $S),
	capacity := SYSTEM_POOL_DEFAULT_CAPACITY,
	allocator := context.allocator,
) {
	fmt.assertf(capacity >= 0, "System pool capacity cannot be negative, got %v.", capacity)

	systems, err := make([]System_Info(P, R, S), capacity, allocator)
	if err != nil do panic("Failed to allocate memory for system pool.")

	pool^ = System_Pool(P, R, S) {
		systems          = systems,
		systems_size     = 0,
		systems_capacity = capacity,
		allocator        = allocator,
	}
}

system_pool_destroy :: proc(pool: ^System_Pool($P, $R, $S)) {
	delete(pool.systems, pool.allocator)
	pool^ = System_Pool(P, R, S){}
}

system_pool_reset :: proc(pool: ^System_Pool($P, $R, $S)) {
	mem.zero_slice(pool.systems)
	pool.systems_size = 0
}

// Systems are kept in register order.
system_pool_register :: proc(
	pool: ^System_Pool($P, $R, $S),
	system: proc(stuff: ^Stuff(P, R, S)),
	stage: S,
	reads: bit_set[P],
	writes: bit_set[P],
) {
	assert(system != nil, "Cannot register a nil system.")

	if pool.systems_size >= pool.systems_capacity {
		fmt.panicf(
			"System pool is full, the capacity is %v. Consider increasing the capacity.",
			pool.systems_capacity,
		)
	}

	pool.systems[pool.systems_size] = System_Info(P, R, S) {
		reads  = reads,
		writes = writes,
		stage  = stage,
		system = system,
	}

	pool.systems_size += 1
}

system_pool_count_systems :: proc(pool: ^System_Pool($P, $R, $S)) -> int {
	return pool.systems_size
}

system_pool_get_systems :: proc(pool: ^System_Pool($P, $R, $S)) -> []System_Info(P, R, S) {
	return pool.systems[:pool.systems_size]
}
