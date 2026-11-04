package ecs_tests

import "core:mem"
import "core:testing"

import ecs "../ecs"

Resource :: enum {
	Time,
	Gravity,
	Flag,
	Big,
	Marker,
}

Time :: struct {
	delta:   f32,
	elapsed: f64,
}

@(thread_local)
destroyed_resources: [Resource]int

count_destroyed_time :: proc(resource: rawptr) {
	destroyed_resources[.Time] += 1
}

count_destroyed_gravity :: proc(resource: rawptr) {
	destroyed_resources[.Gravity] += 1
}

// >------------------------------------------------------------------ Lifecycle

@(test)
resource_pool_destroy_frees_with_init_allocator :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	pool: ecs.Resource_Pool(Resource)
	ecs.resource_pool_init(&pool, 256, mem.tracking_allocator(&track))
	ecs.resource_pool_register(&pool, .Time, Time)
	testing.expect_value(t, len(track.allocation_map), 1)

	// Destroy runs under the default context.allocator, not the init one.
	ecs.resource_pool_destroy(&pool)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
resource_pool_destroy_runs_destroyers_once :: proc(t: ^testing.T) {
	destroyed_resources = {}

	pool: ecs.Resource_Pool(Resource)
	ecs.resource_pool_init(&pool, 256)
	ecs.resource_pool_register(&pool, .Time, Time, count_destroyed_time)
	ecs.resource_pool_register(&pool, .Gravity, f32, count_destroyed_gravity)
	ecs.resource_pool_register(&pool, .Flag, bool)

	ecs.resource_pool_destroy(&pool)

	testing.expect_value(t, destroyed_resources[.Time], 1)
	testing.expect_value(t, destroyed_resources[.Gravity], 1)
}

@(test)
resource_pool_destroyer_sees_the_resource :: proc(t: ^testing.T) {
	@(static) seen: f32
	seen = 0

	pool: ecs.Resource_Pool(Resource)
	ecs.resource_pool_init(&pool, 64)
	ecs.resource_pool_register(&pool, .Gravity, f32, proc(resource: rawptr) {
		seen = (^f32)(resource)^
	})

	ecs.resource_pool_get(&pool, .Gravity, f32)^ = 9.81
	ecs.resource_pool_destroy(&pool)

	testing.expect_value(t, seen, 9.81)
}

// >------------------------------------------------------------------- Register

@(test)
resource_pool_register_starts_zeroed :: proc(t: ^testing.T) {
	pool: ecs.Resource_Pool(Resource)
	ecs.resource_pool_init(&pool, 256)
	defer ecs.resource_pool_destroy(&pool)

	ecs.resource_pool_register(&pool, .Time, Time)
	testing.expect_value(t, ecs.resource_pool_get(&pool, .Time, Time)^, Time{})
}

@(test)
resource_pool_get_writes_through :: proc(t: ^testing.T) {
	pool: ecs.Resource_Pool(Resource)
	ecs.resource_pool_init(&pool, 256)
	defer ecs.resource_pool_destroy(&pool)

	ecs.resource_pool_register(&pool, .Time, Time)

	time := ecs.resource_pool_get(&pool, .Time, Time)
	time.delta = 0.016
	time.elapsed = 2

	testing.expect_value(t, ecs.resource_pool_get(&pool, .Time, Time)^, Time{0.016, 2})
}

@(test)
resource_pool_resources_do_not_overlap :: proc(t: ^testing.T) {
	pool: ecs.Resource_Pool(Resource)
	ecs.resource_pool_init(&pool, 256)
	defer ecs.resource_pool_destroy(&pool)

	ecs.resource_pool_register(&pool, .Flag, bool)
	ecs.resource_pool_register(&pool, .Time, Time)
	ecs.resource_pool_register(&pool, .Gravity, f32)

	ecs.resource_pool_get(&pool, .Flag, bool)^ = true
	ecs.resource_pool_get(&pool, .Time, Time)^ = {1, 2}
	ecs.resource_pool_get(&pool, .Gravity, f32)^ = 3

	testing.expect_value(t, ecs.resource_pool_get(&pool, .Flag, bool)^, true)
	testing.expect_value(t, ecs.resource_pool_get(&pool, .Time, Time)^, Time{1, 2})
	testing.expect_value(t, ecs.resource_pool_get(&pool, .Gravity, f32)^, 3)
}

@(test)
resource_pool_resources_are_aligned :: proc(t: ^testing.T) {
	pool: ecs.Resource_Pool(Resource)
	ecs.resource_pool_init(&pool, 512)
	defer ecs.resource_pool_destroy(&pool)

	// A 1-byte resource first, so the next one needs padding.
	ecs.resource_pool_register(&pool, .Flag, bool)
	ecs.resource_pool_register(&pool, .Big, Aligned)
	ecs.resource_pool_register(&pool, .Time, Time)

	big := ecs.resource_pool_get(&pool, .Big, Aligned)
	time := ecs.resource_pool_get(&pool, .Time, Time)

	testing.expect_value(t, uintptr(big) % align_of(Aligned), 0)
	testing.expect_value(t, uintptr(time) % align_of(Time), 0)
}

@(test)
resource_pool_fills_capacity_exactly :: proc(t: ^testing.T) {
	pool: ecs.Resource_Pool(Resource)
	ecs.resource_pool_init(&pool, 2 * size_of(u64))
	defer ecs.resource_pool_destroy(&pool)

	ecs.resource_pool_register(&pool, .Time, u64)
	ecs.resource_pool_register(&pool, .Gravity, u64)

	testing.expect_value(t, pool.resources_size, 2 * size_of(u64))
	testing.expect_value(t, pool.resources_capacity, 2 * size_of(u64))
}

@(test)
resource_pool_zero_sized_resource :: proc(t: ^testing.T) {
	pool: ecs.Resource_Pool(Resource)
	ecs.resource_pool_init(&pool, size_of(u64))
	defer ecs.resource_pool_destroy(&pool)

	ecs.resource_pool_register(&pool, .Time, u64)

	// Fits even though the buffer is full.
	ecs.resource_pool_register(&pool, .Marker, Tag)
	testing.expect(t, ecs.resource_pool_get(&pool, .Marker, Tag) != nil)
}

@(test)
resource_pool_register_panics_when_out_of_memory :: proc(t: ^testing.T) {
	// The panic skips any cleanup, so take the buffer from the stack instead of the heap.
	backing: [64]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: ecs.Resource_Pool(Resource)
	ecs.resource_pool_init(&pool, size_of(u32), mem.arena_allocator(&arena))

	testing.expect_assert_message(
		t,
		"Resource pool is out of memory: Time needs 16 bytes, the capacity is 4. Consider increasing the capacity.",
	)
	ecs.resource_pool_register(&pool, .Time, Time)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
resource_pool_register_twice_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	backing: [64]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: ecs.Resource_Pool(Resource)
	ecs.resource_pool_init(&pool, 32, mem.arena_allocator(&arena))
	ecs.resource_pool_register(&pool, .Gravity, f32)

	testing.expect_assert_message(t, "Resource Gravity is already registered in the pool.")
	ecs.resource_pool_register(&pool, .Gravity, f32)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
resource_pool_get_wrong_type_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	backing: [64]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: ecs.Resource_Pool(Resource)
	ecs.resource_pool_init(&pool, 32, mem.arena_allocator(&arena))
	ecs.resource_pool_register(&pool, .Gravity, f32)

	testing.expect_assert_message(t, "Resource Gravity is a f32, not a f64.")
	ecs.resource_pool_get(&pool, .Gravity, f64)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
resource_pool_get_unregistered_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	backing: [64]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: ecs.Resource_Pool(Resource)
	ecs.resource_pool_init(&pool, 32, mem.arena_allocator(&arena))

	testing.expect_assert_message(t, "Resource Time is not registered in the pool.")
	ecs.resource_pool_get(&pool, .Time, Time)
	testing.fail_now(t, "The call did not assert.")
}
