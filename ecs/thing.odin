package ecs

import "core:mem"

import "../utils"

// >-------------------------------------------------------- Constants and Types

Thing_Tag :: struct {}

Thing :: utils.Handle(Thing_Tag)
Thing_Pool :: utils.Handle_Pool(Thing_Tag)

Thing_Idx :: utils.Handle_Idx
Thing_Gen :: utils.Handle_Gen
THING_IDX_BITS :: utils.HANDLE_IDX_BITS
THING_GEN_BITS :: utils.HANDLE_GEN_BITS
THING_MAX_IDX :: utils.HANDLE_MAX_IDX
THING_MAX_GEN :: utils.HANDLE_MAX_GEN
THING_NIL :: Thing{}

THING_POOL_MIN_CAPACITY :: utils.HANDLE_POOL_MIN_CAPACITY
THING_POOL_MAX_CAPACITY :: utils.HANDLE_POOL_MAX_CAPACITY
THING_POOL_DEFAULT_CAPACITY :: 1 << 16

// >---------------------------------------------------------------------- Thing

thing_make :: proc(idx: Thing_Idx, gen: Thing_Gen = 0) -> Thing {
	return utils.handle_make(Thing_Tag, idx, gen)
}

// >----------------------------------------------------------------- Thing_Pool

thing_pool_init :: proc(
	pool: ^Thing_Pool,
	capacity: int = THING_POOL_DEFAULT_CAPACITY,
	allocator: mem.Allocator = context.allocator,
) {
	utils.handle_pool_init(pool, capacity, allocator)
}

thing_pool_destroy :: utils.handle_pool_destroy
thing_pool_reset :: utils.handle_pool_reset
thing_pool_capacity :: utils.handle_pool_capacity
thing_pool_alive_count :: utils.handle_pool_alive_count
thing_pool_free_count :: utils.handle_pool_free_count
thing_pool_spawn :: utils.handle_pool_spawn
thing_pool_check :: utils.handle_pool_check
thing_pool_kill :: utils.handle_pool_kill
thing_pool_kill_unchecked :: utils.handle_pool_kill_unchecked
