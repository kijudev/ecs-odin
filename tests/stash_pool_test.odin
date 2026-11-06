package ecs_tests

import "core:mem"
import "core:testing"

import ecs "../ecs"

// >------------------------------------------------------------------ Lifecycle

@(test)
stash_pool_destroy_frees_with_init_allocator :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	pool: ecs.Stash_Pool(Kind)
	ecs.stash_pool_init(&pool, 256, mem.tracking_allocator(&track))
	ecs.stash_pool_register(&pool, .Time, Time)
	testing.expect_value(t, len(track.allocation_map), 1)

	// Destroy runs under the default context.allocator, not the init one.
	ecs.stash_pool_destroy(&pool)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
stash_pool_destroy_runs_destroy_fns_once :: proc(t: ^testing.T) {
	destroyed_stashes = {}

	pool: ecs.Stash_Pool(Kind)
	ecs.stash_pool_init(&pool, 256)
	ecs.stash_pool_register(&pool, .Time, Time, count_destroyed_time)
	ecs.stash_pool_register(&pool, .Gravity, f32, count_destroyed_gravity)
	ecs.stash_pool_register(&pool, .Flag, bool)

	ecs.stash_pool_destroy(&pool)

	testing.expect_value(t, destroyed_stashes[.Time], 1)
	testing.expect_value(t, destroyed_stashes[.Gravity], 1)
}

@(test)
stash_pool_destroy_fn_sees_the_stash :: proc(t: ^testing.T) {
	@(static) seen: f32
	seen = 0

	pool: ecs.Stash_Pool(Kind)
	ecs.stash_pool_init(&pool, 64)
	ecs.stash_pool_register(&pool, .Gravity, f32, proc(stash: rawptr) {
		seen = (^f32)(stash)^
	})

	ecs.stash_pool_get(&pool, .Gravity, f32)^ = 9.81
	ecs.stash_pool_destroy(&pool)

	testing.expect_value(t, seen, 9.81)
}

@(test)
stash_pool_reset_destroys_and_zeroes_keeps_registrations :: proc(t: ^testing.T) {
	pool: ecs.Stash_Pool(Kind)
	ecs.stash_pool_init(&pool, 256)
	defer ecs.stash_pool_destroy(&pool)

	ecs.stash_pool_register(&pool, .Time, Time, count_destroyed_time)
	ecs.stash_pool_register(&pool, .Gravity, f32)
	ecs.stash_pool_get(&pool, .Time, Time)^ = {1, 2}
	ecs.stash_pool_get(&pool, .Gravity, f32)^ = 9.81

	destroyed_stashes = {}
	ecs.stash_pool_reset(&pool)

	testing.expect_value(t, destroyed_stashes[.Time], 1)
	testing.expect(t, ecs.stash_pool_is_registered(&pool, .Time))
	testing.expect(t, ecs.stash_pool_is_registered(&pool, .Gravity))
	testing.expect_value(t, ecs.stash_pool_get(&pool, .Time, Time)^, Time{})
	testing.expect_value(t, ecs.stash_pool_get(&pool, .Gravity, f32)^, 0)

	// Registering after a reset still appends behind the existing stashes.
	ecs.stash_pool_register(&pool, .Flag, bool)
	ecs.stash_pool_get(&pool, .Flag, bool)^ = true
	testing.expect_value(t, ecs.stash_pool_get(&pool, .Gravity, f32)^, 0)
}

// >------------------------------------------------------------------- Register

@(test)
stash_pool_register_starts_zeroed :: proc(t: ^testing.T) {
	pool: ecs.Stash_Pool(Kind)
	ecs.stash_pool_init(&pool, 256)
	defer ecs.stash_pool_destroy(&pool)

	testing.expect(t, !ecs.stash_pool_is_registered(&pool, .Time))
	ecs.stash_pool_register(&pool, .Time, Time)
	testing.expect(t, ecs.stash_pool_is_registered(&pool, .Time))
	testing.expect_value(t, ecs.stash_pool_get(&pool, .Time, Time)^, Time{})
}

@(test)
stash_pool_get_writes_through :: proc(t: ^testing.T) {
	pool: ecs.Stash_Pool(Kind)
	ecs.stash_pool_init(&pool, 256)
	defer ecs.stash_pool_destroy(&pool)

	ecs.stash_pool_register(&pool, .Time, Time)

	time := ecs.stash_pool_get(&pool, .Time, Time)
	time.delta = 0.016
	time.elapsed = 2

	testing.expect_value(t, ecs.stash_pool_get(&pool, .Time, Time)^, Time{0.016, 2})
}

@(test)
stash_pool_stashes_do_not_overlap :: proc(t: ^testing.T) {
	pool: ecs.Stash_Pool(Kind)
	ecs.stash_pool_init(&pool, 256)
	defer ecs.stash_pool_destroy(&pool)

	ecs.stash_pool_register(&pool, .Flag, bool)
	ecs.stash_pool_register(&pool, .Time, Time)
	ecs.stash_pool_register(&pool, .Gravity, f32)

	ecs.stash_pool_get(&pool, .Flag, bool)^ = true
	ecs.stash_pool_get(&pool, .Time, Time)^ = {1, 2}
	ecs.stash_pool_get(&pool, .Gravity, f32)^ = 3

	testing.expect_value(t, ecs.stash_pool_get(&pool, .Flag, bool)^, true)
	testing.expect_value(t, ecs.stash_pool_get(&pool, .Time, Time)^, Time{1, 2})
	testing.expect_value(t, ecs.stash_pool_get(&pool, .Gravity, f32)^, 3)
}

@(test)
stash_pool_stashes_are_aligned :: proc(t: ^testing.T) {
	pool: ecs.Stash_Pool(Kind)
	ecs.stash_pool_init(&pool, 512)
	defer ecs.stash_pool_destroy(&pool)

	// A 1-byte stash first, so the next one needs padding.
	ecs.stash_pool_register(&pool, .Flag, bool)
	ecs.stash_pool_register(&pool, .Big, Aligned)
	ecs.stash_pool_register(&pool, .Time, Time)

	big := ecs.stash_pool_get(&pool, .Big, Aligned)
	time := ecs.stash_pool_get(&pool, .Time, Time)

	testing.expect_value(t, uintptr(big) % align_of(Aligned), 0)
	testing.expect_value(t, uintptr(time) % align_of(Time), 0)
}

@(test)
stash_pool_fills_capacity_exactly :: proc(t: ^testing.T) {
	pool: ecs.Stash_Pool(Kind)
	ecs.stash_pool_init(&pool, 2 * size_of(u64))
	defer ecs.stash_pool_destroy(&pool)

	ecs.stash_pool_register(&pool, .Time, u64)
	ecs.stash_pool_register(&pool, .Gravity, u64)

	testing.expect_value(t, pool.stashes_size, 2 * size_of(u64))
	testing.expect_value(t, pool.stashes_capacity, 2 * size_of(u64))
}

@(test)
stash_pool_zero_sized_stash :: proc(t: ^testing.T) {
	pool: ecs.Stash_Pool(Kind)
	ecs.stash_pool_init(&pool, size_of(u64))
	defer ecs.stash_pool_destroy(&pool)

	ecs.stash_pool_register(&pool, .Time, u64)

	// Fits even though the buffer is full.
	ecs.stash_pool_register(&pool, .Marker, Tag)
	testing.expect(t, ecs.stash_pool_get(&pool, .Marker, Tag) != nil)
}

@(test)
stash_pool_register_panics_when_out_of_memory :: proc(t: ^testing.T) {
	// The panic skips any cleanup, so take the buffer from the stack instead of the heap.
	backing: [64]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: ecs.Stash_Pool(Kind)
	ecs.stash_pool_init(&pool, size_of(u32), mem.arena_allocator(&arena))

	testing.expect_assert_message(
		t,
		"Stash pool is out of memory: Time needs 16 bytes, the capacity is 4. Consider increasing the capacity.",
	)
	ecs.stash_pool_register(&pool, .Time, Time)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
stash_pool_register_twice_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	backing: [64]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: ecs.Stash_Pool(Kind)
	ecs.stash_pool_init(&pool, 32, mem.arena_allocator(&arena))
	ecs.stash_pool_register(&pool, .Gravity, f32)

	testing.expect_assert_message(t, "Stash kind Gravity is already registered.")
	ecs.stash_pool_register(&pool, .Gravity, f32)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
stash_pool_get_wrong_type_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	backing: [64]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: ecs.Stash_Pool(Kind)
	ecs.stash_pool_init(&pool, 32, mem.arena_allocator(&arena))
	ecs.stash_pool_register(&pool, .Gravity, f32)

	testing.expect_assert_message(t, "Stash kind Gravity is a f32, not a f64.")
	ecs.stash_pool_get(&pool, .Gravity, f64)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
stash_pool_get_unregistered_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	backing: [64]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: ecs.Stash_Pool(Kind)
	ecs.stash_pool_init(&pool, 32, mem.arena_allocator(&arena))

	testing.expect_assert_message(t, "Stash kind Time is not registered.")
	ecs.stash_pool_get(&pool, .Time, Time)
	testing.fail_now(t, "The call did not assert.")
}
