package ecs_tests

import "core:mem"
import "core:testing"

import ecs "../../ecs"

Part_Kind :: enum {
	Position,
	Velocity,
	Health,
}

// >------------------------------------------------------------------ Lifecycle

@(test)
archetype_pool_init_creates_empty_pool :: proc(t: ^testing.T) {
	pool: ecs.Archetype_Pool(Part_Kind)
	ecs.archetype_pool_init(&pool, ecs.ARCHETYPE_POOL_MIN_CAPACITY)
	defer ecs.archetype_pool_destroy(&pool)

	testing.expect_value(t, ecs.archetype_pool_capacity(pool), ecs.ARCHETYPE_POOL_MIN_CAPACITY)

	thing := ecs.thing_make(1)
	for kind in Part_Kind {
		testing.expect(t, !ecs.archetype_pool_has(pool, thing, kind))
	}
}

@(test)
archetype_pool_destroy_zeroes_pool :: proc(t: ^testing.T) {
	pool: ecs.Archetype_Pool(Part_Kind)
	ecs.archetype_pool_init(&pool, ecs.ARCHETYPE_POOL_MIN_CAPACITY)
	ecs.archetype_pool_destroy(&pool)

	testing.expect_value(t, ecs.archetype_pool_capacity(pool), 0)
	testing.expect(t, pool.slots == nil)
}

@(test)
archetype_pool_destroy_frees_with_init_allocator :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	pool: ecs.Archetype_Pool(Part_Kind)
	ecs.archetype_pool_init(&pool, ecs.ARCHETYPE_POOL_MIN_CAPACITY, mem.tracking_allocator(&track))
	testing.expect(t, len(track.allocation_map) > 0)

	// Destroy runs under the default context.allocator, not the init one.
	ecs.archetype_pool_destroy(&pool)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
archetype_pool_reset_clears_all_masks :: proc(t: ^testing.T) {
	pool: ecs.Archetype_Pool(Part_Kind)
	ecs.archetype_pool_init(&pool, ecs.ARCHETYPE_POOL_MIN_CAPACITY)
	defer ecs.archetype_pool_destroy(&pool)

	a := ecs.thing_make(1)
	b := ecs.thing_make(2)
	ecs.archetype_pool_insert(&pool, a, .Position)
	ecs.archetype_pool_insert(&pool, b, .Health)

	ecs.archetype_pool_reset(&pool)

	testing.expect(t, !ecs.archetype_pool_has(pool, a, .Position))
	testing.expect(t, !ecs.archetype_pool_has(pool, b, .Health))
	testing.expect_value(t, ecs.archetype_pool_capacity(pool), ecs.ARCHETYPE_POOL_MIN_CAPACITY)
}

// >------------------------------------------------------------- Insert / Remove

@(test)
archetype_pool_insert_sets_kind :: proc(t: ^testing.T) {
	pool: ecs.Archetype_Pool(Part_Kind)
	ecs.archetype_pool_init(&pool, ecs.ARCHETYPE_POOL_MIN_CAPACITY)
	defer ecs.archetype_pool_destroy(&pool)

	thing := ecs.thing_make(1)
	ecs.archetype_pool_insert(&pool, thing, .Position)
	ecs.archetype_pool_insert(&pool, thing, .Velocity)

	testing.expect(t, ecs.archetype_pool_has(pool, thing, .Position))
	testing.expect(t, ecs.archetype_pool_has(pool, thing, .Velocity))
	testing.expect(t, !ecs.archetype_pool_has(pool, thing, .Health))
}

@(test)
archetype_pool_insert_twice_is_idempotent :: proc(t: ^testing.T) {
	pool: ecs.Archetype_Pool(Part_Kind)
	ecs.archetype_pool_init(&pool, ecs.ARCHETYPE_POOL_MIN_CAPACITY)
	defer ecs.archetype_pool_destroy(&pool)

	thing := ecs.thing_make(1)
	ecs.archetype_pool_insert(&pool, thing, .Position)
	ecs.archetype_pool_insert(&pool, thing, .Position)
	testing.expect(t, ecs.archetype_pool_has(pool, thing, .Position))

	// A single remove clears it; no counting.
	ecs.archetype_pool_remove(&pool, thing, .Position)
	testing.expect(t, !ecs.archetype_pool_has(pool, thing, .Position))
}

@(test)
archetype_pool_remove_keeps_other_kinds :: proc(t: ^testing.T) {
	pool: ecs.Archetype_Pool(Part_Kind)
	ecs.archetype_pool_init(&pool, ecs.ARCHETYPE_POOL_MIN_CAPACITY)
	defer ecs.archetype_pool_destroy(&pool)

	thing := ecs.thing_make(1)
	ecs.archetype_pool_insert(&pool, thing, .Position)
	ecs.archetype_pool_insert(&pool, thing, .Velocity)
	ecs.archetype_pool_remove(&pool, thing, .Position)

	testing.expect(t, !ecs.archetype_pool_has(pool, thing, .Position))
	testing.expect(t, ecs.archetype_pool_has(pool, thing, .Velocity))
}

@(test)
archetype_pool_remove_missing_is_noop :: proc(t: ^testing.T) {
	pool: ecs.Archetype_Pool(Part_Kind)
	ecs.archetype_pool_init(&pool, ecs.ARCHETYPE_POOL_MIN_CAPACITY)
	defer ecs.archetype_pool_destroy(&pool)

	thing := ecs.thing_make(1)
	ecs.archetype_pool_insert(&pool, thing, .Velocity)
	ecs.archetype_pool_remove(&pool, thing, .Position)

	testing.expect(t, !ecs.archetype_pool_has(pool, thing, .Position))
	testing.expect(t, ecs.archetype_pool_has(pool, thing, .Velocity))
}

@(test)
archetype_pool_things_are_independent :: proc(t: ^testing.T) {
	pool: ecs.Archetype_Pool(Part_Kind)
	ecs.archetype_pool_init(&pool, ecs.ARCHETYPE_POOL_MIN_CAPACITY)
	defer ecs.archetype_pool_destroy(&pool)

	a := ecs.thing_make(1)
	b := ecs.thing_make(2)
	ecs.archetype_pool_insert(&pool, a, .Position)
	ecs.archetype_pool_insert(&pool, b, .Health)

	testing.expect(t, ecs.archetype_pool_has(pool, a, .Position))
	testing.expect(t, !ecs.archetype_pool_has(pool, a, .Health))
	testing.expect(t, ecs.archetype_pool_has(pool, b, .Health))
	testing.expect(t, !ecs.archetype_pool_has(pool, b, .Position))
}
