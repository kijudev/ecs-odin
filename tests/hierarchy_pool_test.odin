package ecs_tests

import "core:mem"
import "core:testing"

import ecs "../ecs"

Hierarchy_Pool :: ecs.Hierarchy_Pool(Kind)

// >------------------------------------------------------------------ Lifecycle

@(test)
hierarchy_pool_allocates_on_register :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	pool: Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_SET_MIN_CAPACITY, mem.tracking_allocator(&track))
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect(t, !ecs.hierarchy_pool_is_registered(&pool, .Transform))

	ecs.hierarchy_pool_register(&pool, .Transform)
	testing.expect(t, ecs.hierarchy_pool_is_registered(&pool, .Transform))
	testing.expect(t, !ecs.hierarchy_pool_is_registered(&pool, .Inside))
	testing.expect(t, len(track.allocation_map) > 0)

	set := ecs.hierarchy_pool_get_set(&pool, .Transform)
	testing.expect_value(t, ecs.hierarchy_set_capacity(set), ecs.HIERARCHY_SET_MIN_CAPACITY)

	ecs.hierarchy_pool_register(&pool, .Inside)
	ecs.hierarchy_pool_destroy(&pool)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
	testing.expect(t, !ecs.hierarchy_pool_is_registered(&pool, .Transform))
}

@(test)
hierarchy_pool_reset_keeps_registrations :: proc(t: ^testing.T) {
	pool: Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	ecs.hierarchy_pool_register(&pool, .Transform)
	ecs.hierarchy_pool_register(&pool, .Inside)
	transform := ecs.hierarchy_pool_get_set(&pool, .Transform)
	inside := ecs.hierarchy_pool_get_set(&pool, .Inside)
	ecs.hierarchy_set_attach(transform, ecs.thing_make(2), ecs.thing_make(1))
	ecs.hierarchy_set_attach(inside, ecs.thing_make(3), ecs.thing_make(1))

	ecs.hierarchy_pool_reset(&pool)

	testing.expect(t, ecs.hierarchy_pool_is_registered(&pool, .Transform))
	testing.expect(t, ecs.hierarchy_pool_is_registered(&pool, .Inside))
	testing.expect_value(t, ecs.hierarchy_set_count(transform), 0)
	testing.expect_value(t, ecs.hierarchy_set_count(inside), 0)
}

// >----------------------------------------------------------------- Remove All

@(test)
hierarchy_pool_remove_all_leaves_every_set :: proc(t: ^testing.T) {
	pool: Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	ecs.hierarchy_pool_register(&pool, .Transform)
	ecs.hierarchy_pool_register(&pool, .Inside)
	transform := ecs.hierarchy_pool_get_set(&pool, .Transform)
	inside := ecs.hierarchy_pool_get_set(&pool, .Inside)

	a, b, c := ecs.thing_make(1), ecs.thing_make(2), ecs.thing_make(3)
	ecs.hierarchy_set_attach(transform, b, a)
	ecs.hierarchy_set_attach(transform, c, b)
	ecs.hierarchy_set_attach(inside, a, b)

	ecs.hierarchy_pool_remove_all(&pool, b)

	testing.expect(t, !ecs.hierarchy_set_contains(transform, b))
	testing.expect(t, !ecs.hierarchy_set_contains(inside, b))
	testing.expect(t, !ecs.hierarchy_set_contains(inside, a))
	testing.expect_value(t, ecs.hierarchy_set_count(transform), 0)
	testing.expect_value(t, ecs.hierarchy_set_count(inside), 0)
}

@(test)
hierarchy_pool_remove_all_skips_things_outside :: proc(t: ^testing.T) {
	pool: Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_SET_MIN_CAPACITY)
	defer ecs.hierarchy_pool_destroy(&pool)

	ecs.hierarchy_pool_register(&pool, .Transform)
	transform := ecs.hierarchy_pool_get_set(&pool, .Transform)
	ecs.hierarchy_set_attach(transform, ecs.thing_make(2), ecs.thing_make(1))

	ecs.hierarchy_pool_remove_all(&pool, ecs.thing_make(5))

	testing.expect_value(t, ecs.hierarchy_set_count(transform), 2)
}

// >-------------------------------------------------------------------- Asserts

@(test)
hierarchy_pool_register_twice_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the sets from the stack instead of the heap.
	backing: [8 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_SET_MIN_CAPACITY, mem.arena_allocator(&arena))
	ecs.hierarchy_pool_register(&pool, .Transform)

	testing.expect_assert_message(t, "Hierarchy kind Transform is already registered.")
	ecs.hierarchy_pool_register(&pool, .Transform)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_pool_get_unregistered_set_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	pool: Hierarchy_Pool
	ecs.hierarchy_pool_init(&pool, ecs.HIERARCHY_SET_MIN_CAPACITY)

	testing.expect_assert_message(t, "Hierarchy kind Inside is not registered.")
	ecs.hierarchy_pool_get_set(&pool, .Inside)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
hierarchy_pool_init_capacity_too_small_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	pool: Hierarchy_Pool
	testing.expect_assert_message(
		t,
		"Hierarchy pool capacity has to be between 64 and 1048576, got 8.",
	)
	ecs.hierarchy_pool_init(&pool, 8)
	testing.fail_now(t, "The call did not assert.")
}
