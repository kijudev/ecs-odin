package ecs_tests

import "core:mem"
import "core:testing"

import ecs "../ecs"

// >------------------------------------------------------------------ Lifecycle

@(test)
thing_pool_init_creates_empty_pool :: proc(t: ^testing.T) {
	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&pool)

	testing.expect_value(t, len(pool.slots), ecs.THING_POOL_MIN_CAPACITY)
	testing.expect_value(t, ecs.thing_pool_count_alive(pool), 0)
	testing.expect_value(t, pool.free_count, 0)
}

@(test)
thing_pool_destroy_zeroes_pool :: proc(t: ^testing.T) {
	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY)
	ecs.thing_pool_spawn(&pool)
	ecs.thing_pool_destroy(&pool)

	testing.expect_value(t, len(pool.slots), 0)
	testing.expect(t, pool.slots == nil)
	testing.expect(t, pool.free == nil)
}

@(test)
thing_pool_destroy_frees_with_init_allocator :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY, mem.tracking_allocator(&track))
	testing.expect(t, len(track.allocation_map) > 0)

	// Destroy runs under the default context.allocator, not the init one.
	ecs.thing_pool_destroy(&pool)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
thing_pool_reset_invalidates_all_things :: proc(t: ^testing.T) {
	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&pool)

	a := ecs.thing_pool_spawn(&pool)
	b := ecs.thing_pool_spawn(&pool)
	ecs.thing_pool_kill(&pool, a)

	ecs.thing_pool_reset(&pool)

	testing.expect(t, !ecs.thing_pool_poke(pool, a))
	testing.expect(t, !ecs.thing_pool_poke(pool, b))
	testing.expect_value(t, ecs.thing_pool_count_alive(pool), 0)
	testing.expect_value(t, pool.free_count, 0)
	testing.expect_value(t, len(pool.slots), ecs.THING_POOL_MIN_CAPACITY)

	// Pool is usable again after reset.
	c := ecs.thing_pool_spawn(&pool)
	testing.expect(t, ecs.thing_pool_poke(pool, c))
}

// >---------------------------------------------------------------------- Spawn

@(test)
thing_pool_nil_thing_is_never_valid :: proc(t: ^testing.T) {
	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&pool)

	testing.expect(t, !ecs.thing_pool_poke(pool, ecs.THING_NIL))

	ecs.thing_pool_spawn(&pool)
	testing.expect(t, !ecs.thing_pool_poke(pool, ecs.THING_NIL))
	testing.expect(t, !ecs.thing_pool_kill(&pool, ecs.THING_NIL))
}

@(test)
thing_pool_spawn_returns_valid_thing :: proc(t: ^testing.T) {
	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&pool)

	thing := ecs.thing_pool_spawn(&pool)

	testing.expect(t, thing != ecs.THING_NIL)
	testing.expect(t, ecs.thing_pool_poke(pool, thing))
	testing.expect_value(t, ecs.thing_pool_count_alive(pool), 1)
}

@(test)
thing_pool_spawn_returns_distinct_things :: proc(t: ^testing.T) {
	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&pool)

	a := ecs.thing_pool_spawn(&pool)
	b := ecs.thing_pool_spawn(&pool)
	c := ecs.thing_pool_spawn(&pool)

	testing.expect(t, a.idx != b.idx)
	testing.expect(t, b.idx != c.idx)
	testing.expect(t, a.idx != c.idx)
	testing.expect_value(t, ecs.thing_pool_count_alive(pool), 3)
}

@(test)
thing_pool_spawn_fills_pool_to_capacity :: proc(t: ^testing.T) {
	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&pool)

	// Slot 0 is reserved for THING_NIL.
	usable := len(pool.slots) - 1
	for _ in 0 ..< usable {
		thing := ecs.thing_pool_spawn(&pool)
		testing.expect(t, ecs.thing_pool_poke(pool, thing))
	}

	testing.expect_value(t, ecs.thing_pool_count_alive(pool), usable)
}

@(test)
thing_pool_spawn_returns_nil_when_full :: proc(t: ^testing.T) {
	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&pool)

	usable := len(pool.slots) - 1
	last: ecs.Thing
	for _ in 0 ..< usable {
		last = ecs.thing_pool_spawn(&pool)
	}

	testing.expect_value(t, ecs.thing_pool_spawn(&pool), ecs.THING_NIL)
	testing.expect_value(t, ecs.thing_pool_count_alive(pool), usable)

	// Killing frees a slot again.
	ecs.thing_pool_kill(&pool, last)
	testing.expect(t, ecs.thing_pool_spawn(&pool) != ecs.THING_NIL)
}

// >----------------------------------------------------------------------- Kill

@(test)
thing_pool_kill_invalidates_thing :: proc(t: ^testing.T) {
	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&pool)

	thing := ecs.thing_pool_spawn(&pool)

	testing.expect(t, ecs.thing_pool_kill(&pool, thing))
	testing.expect(t, !ecs.thing_pool_poke(pool, thing))
	testing.expect_value(t, ecs.thing_pool_count_alive(pool), 0)
	testing.expect_value(t, pool.free_count, 1)
}

@(test)
thing_pool_kill_twice_fails :: proc(t: ^testing.T) {
	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&pool)

	thing := ecs.thing_pool_spawn(&pool)

	testing.expect(t, ecs.thing_pool_kill(&pool, thing))
	testing.expect(t, !ecs.thing_pool_kill(&pool, thing))
	testing.expect_value(t, pool.free_count, 1)
}

@(test)
thing_pool_kill_leaves_other_things_alive :: proc(t: ^testing.T) {
	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&pool)

	a := ecs.thing_pool_spawn(&pool)
	b := ecs.thing_pool_spawn(&pool)
	c := ecs.thing_pool_spawn(&pool)

	ecs.thing_pool_kill(&pool, b)

	testing.expect(t, ecs.thing_pool_poke(pool, a))
	testing.expect(t, !ecs.thing_pool_poke(pool, b))
	testing.expect(t, ecs.thing_pool_poke(pool, c))
	testing.expect_value(t, ecs.thing_pool_count_alive(pool), 2)
}

@(test)
thing_pool_poke_rejects_out_of_range_idx :: proc(t: ^testing.T) {
	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&pool)

	thing := ecs.thing_make(ecs.Thing_Idx(len(pool.slots)), 1)
	testing.expect(t, thing != ecs.THING_NIL)

	testing.expect(t, !ecs.thing_pool_poke(pool, thing))
	testing.expect(t, !ecs.thing_pool_kill(&pool, thing))
}

// >-------------------------------------------------------------------- Recycle

@(test)
thing_pool_spawn_reuses_killed_slot_with_new_gen :: proc(t: ^testing.T) {
	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&pool)

	old := ecs.thing_pool_spawn(&pool)
	ecs.thing_pool_kill(&pool, old)
	new := ecs.thing_pool_spawn(&pool)

	testing.expect_value(t, new.idx, old.idx)
	testing.expect(t, new.gen != old.gen)
	testing.expect(t, ecs.thing_pool_poke(pool, new))
	testing.expect(t, !ecs.thing_pool_poke(pool, old))
	testing.expect_value(t, pool.free_count, 0)
}

@(test)
thing_pool_stale_thing_cannot_kill_new_thing :: proc(t: ^testing.T) {
	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&pool)

	old := ecs.thing_pool_spawn(&pool)
	ecs.thing_pool_kill(&pool, old)
	new := ecs.thing_pool_spawn(&pool)

	testing.expect(t, !ecs.thing_pool_kill(&pool, old))
	testing.expect(t, ecs.thing_pool_poke(pool, new))
}

@(test)
thing_pool_count_alive_tracks_spawn_kill_reuse :: proc(t: ^testing.T) {
	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&pool)

	a := ecs.thing_pool_spawn(&pool)
	ecs.thing_pool_spawn(&pool)
	testing.expect_value(t, ecs.thing_pool_count_alive(pool), 2)

	ecs.thing_pool_kill(&pool, a)
	testing.expect_value(t, ecs.thing_pool_count_alive(pool), 1)

	ecs.thing_pool_spawn(&pool) // reuses a's slot
	testing.expect_value(t, ecs.thing_pool_count_alive(pool), 2)

	ecs.thing_pool_spawn(&pool) // fresh slot
	testing.expect_value(t, ecs.thing_pool_count_alive(pool), 3)
}

@(test)
thing_pool_reuse_then_fresh_spawn_does_not_collide :: proc(t: ^testing.T) {
	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&pool)

	a := ecs.thing_pool_spawn(&pool)
	b := ecs.thing_pool_spawn(&pool)
	ecs.thing_pool_kill(&pool, a)
	ecs.thing_pool_spawn(&pool) // reuses a's slot
	c := ecs.thing_pool_spawn(&pool) // must be a fresh slot, not b's

	testing.expect(t, c.idx != b.idx)
	testing.expect(t, ecs.thing_pool_poke(pool, b))
	testing.expect(t, ecs.thing_pool_poke(pool, c))
}

@(test)
thing_pool_gen_wraps_around_after_max_gen_reuses :: proc(t: ^testing.T) {
	pool: ecs.Thing_Pool
	ecs.thing_pool_init(&pool, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&pool)

	first := ecs.thing_pool_spawn(&pool)
	prev := first

	// Recycle the same slot through every generation.
	for _ in 0 ..< ecs.THING_MAX_GEN {
		ecs.thing_pool_kill(&pool, prev)
		next := ecs.thing_pool_spawn(&pool)

		testing.expect_value(t, next.idx, first.idx)
		testing.expect(t, ecs.thing_pool_poke(pool, next))
		testing.expect(t, !ecs.thing_pool_poke(pool, prev))

		prev = next
	}

	// After THING_MAX_GEN reuses the gen is back where it started, so a
	// handle that stale is valid again (ABA). Inherent to a 12-bit gen.
	testing.expect_value(t, prev.gen, first.gen)
	testing.expect(t, ecs.thing_pool_poke(pool, first))
}
