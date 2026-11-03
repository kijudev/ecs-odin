package ecs

import "base:intrinsics"
import "core:slice"

// >-------------------------------------------------------- Constants and Types

System_Priority :: int

SYSTEM_POOL_DEFAULT_CAPACITY :: 1 << 8

System :: struct($P: typeid, $R: typeid, $S: typeid) where intrinsics.type_is_enum(P),
	intrinsics.type_is_proc(R),
	intrinsics.type_is_enum(S) {
	reads:    bit_set[P],
	writes:   bit_set[P],
	run:      $R,
	stage:    S,
	priority: System_Priority,
}

System_Pool :: struct($P: typeid, $R: typeid, $S: typeid) where intrinsics.type_is_enum(P),
	intrinsics.type_is_proc(R),
	intrinsics.type_is_enum(S) {
	systems:   [dynamic]System(P, R, S),
	allocator: mem.Allocator,
}

// >--------------------------------------------------------------------- System

system_eq :: proc(a: System($P, $R, $S), b: System(P, R, S)) -> bool {
	return(
		a.reads == b.reads &&
		a.writes == b.writes &&
		a.run == b.run &&
		a.stage == b.stage &&
		a.priority == b.priority \
	)
}

// >---------------------------------------------------------------- System_Pool

system_pool_init :: proc(
	pool: ^System_Pool($P, $R, $S),
	capacity: int = SYSTEM_POOL_DEFAULT_CAPACITY,
	allocator := context.allocator,
) {
	assert(capacity >= 0, "System pool capacity cannot be negative.")

	pool^ = {
		systems   = make([dynamic]System(P, R, S), capacity, allocator),
		allocator = allocator,
	}
}

system_pool_destroy :: proc(pool: ^System_Pool($P, $R, $S)) {
	delete(pool.systems)
	pool^ = {}
}

system_pool_reset :: proc(pool: ^System_Pool($P, $R, $S)) {
	clear(pool.systems)
}

system_pool_count :: proc(pool: ^System_Pool($P, $R, $S)) -> int {
	return len(pool.systems)
}

system_pool_clear :: proc(pool: ^System_Pool($P, $R, $S)) {
	clear(pool.systems)
}

system_pool_add :: proc(pool: ^System_Pool($P, $R, $S), system: System(P, R, S)) {
	append(&pool.systems, system)
}

system_pool_remove :: proc(pool: ^System_Pool($P, $R, $S), target: System(P, R, S)) -> bool {
	idx := -1
	for system, i in pool.systems {
		if system_eq(system, target) {
			idx = i
			break
		}
	}

	if idx < 0 do return false
	unordered_remove(pool.systems, idx)
}

system_pool_get :: proc(pool: ^System_Pool($P, $R, $S)) -> []System(P, R, S) {
	return pool.systems[:]
}
