package ecs

import "core:mem"

// >-------------------------------------------------------- Constants and Types

/* Tags `Thing` handles, so they can't be mixed up with other handles. */
Thing_Tag :: struct {}

/* A handle to a thing, see Handle. A zeroed thing is THING_NIL. */
Thing :: Handle(Thing_Tag)

/* Hands out and validates things, see Handle_Pool. */
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

/* Makes a thing from its parts. See handle_make. */
thing_make :: proc(idx: Thing_Idx, gen: Thing_Gen = 0) -> Thing {
	return handle_make(Thing_Tag, idx, gen)
}

// >----------------------------------------------------------------- Thing_Pool

/* Initializes the pool with room for `capacity - 1` things. See handle_pool_init. */
thing_pool_init :: proc(
	pool: ^Thing_Pool,
	capacity: int = THING_POOL_DEFAULT_CAPACITY,
	allocator: mem.Allocator = context.allocator,
) {
	handle_pool_init(pool, capacity, allocator)
}

/* See handle_pool_destroy. */
thing_pool_destroy :: handle_pool_destroy

/* See handle_pool_reset. */
thing_pool_reset :: handle_pool_reset

/* See handle_pool_count_alive. */
thing_pool_count_alive :: handle_pool_count_alive

/* See handle_pool_spawn. */
thing_pool_spawn :: handle_pool_spawn

/* See handle_pool_is_alive. */
thing_pool_is_alive :: handle_pool_is_alive

/* See handle_pool_kill. */
thing_pool_kill :: handle_pool_kill

/* See handle_pool_kill_unchecked. */
thing_pool_kill_unchecked :: handle_pool_kill_unchecked
