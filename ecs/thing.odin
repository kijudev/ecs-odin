package ecs

import "core:mem"

// >-------------------------------------------------------- Constants and Types

Thing_Tag :: struct {}

Thing :: Handle(Thing_Tag)
Thing_Pool :: Handle_Pool(Thing_Tag)

Thing_Idx :: Handle_Idx
Thing_Gen :: Handle_Gen
THING_IDX_BITS :: HANDLE_IDX_BITS
THING_GEN_BITS :: HANDLE_GEN_BITS
THING_MAX_IDX :: HANDLE_MAX_IDX
THING_MAX_GEN :: HANDLE_MAX_GEN
THING_NIL :: Thing{}

THING_POOL_MIN_CAPACITY :: HANDLE_POOL_MIN_CAPACITY
THING_POOL_MAX_CAPACITY :: HANDLE_POOL_MAX_CAPACITY
THING_POOL_DEFAULT_CAPACITY :: 1 << 16

// >---------------------------------------------------------------------- Thing

thing_make :: proc(idx: Thing_Idx, gen: Thing_Gen = 0) -> Thing {
	return handle_make(Thing_Tag, idx, gen)
}

// >----------------------------------------------------------------- Thing_Pool

thing_pool_init :: proc(
	pool: ^Thing_Pool,
	capacity: int = THING_POOL_DEFAULT_CAPACITY,
	allocator: mem.Allocator = context.allocator,
) {
	handle_pool_init(pool, capacity, allocator)
}

thing_pool_destroy :: handle_pool_destroy
thing_pool_reset :: handle_pool_reset
thing_pool_capacity :: handle_pool_capacity
thing_pool_count_alive :: handle_pool_count_alive
thing_pool_count_free :: handle_pool_count_free
thing_pool_spawn :: handle_pool_spawn
thing_pool_poke :: handle_pool_check
thing_pool_kill :: handle_pool_kill
thing_pool_kill_unchecked :: handle_pool_kill_unchecked
