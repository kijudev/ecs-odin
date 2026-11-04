package ecs_tests

import "core:mem"
import "core:testing"

import ecs "../ecs"

System_Part :: enum {
	Position,
	Velocity,
}

System_Resource :: enum {
	Time,
}

Stage :: enum {
	Update,
	Render,
}

System_Pool :: ecs.System_Pool(System_Part, System_Resource, Stage)
System_Stuff :: ecs.Stuff(System_Part, System_Resource, Stage)

@(thread_local)
system_calls: [2]int

move_system :: proc(stuff: ^System_Stuff) {
	system_calls[0] += 1
}

draw_system :: proc(stuff: ^System_Stuff) {
	system_calls[1] += 1
}

// >------------------------------------------------------------------ Lifecycle

@(test)
system_pool_init_creates_empty_pool :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool, 8)
	defer ecs.system_pool_destroy(&pool)

	testing.expect_value(t, ecs.system_pool_count_systems(&pool), 0)
	testing.expect_value(t, len(ecs.system_pool_get_systems(&pool)), 0)
}

@(test)
system_pool_destroy_frees_with_init_allocator :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	pool: System_Pool
	ecs.system_pool_init(&pool, 8, mem.tracking_allocator(&track))
	ecs.system_pool_register(&pool, move_system, .Update, {.Velocity}, {.Position})
	testing.expect_value(t, len(track.allocation_map), 1)

	// Destroy runs under the default context.allocator, not the init one.
	ecs.system_pool_destroy(&pool)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
system_pool_reset_removes_systems :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool, 8)
	defer ecs.system_pool_destroy(&pool)

	ecs.system_pool_register(&pool, move_system, .Update, {.Velocity}, {.Position})
	ecs.system_pool_reset(&pool)
	testing.expect_value(t, ecs.system_pool_count_systems(&pool), 0)

	// Usable again after reset.
	ecs.system_pool_register(&pool, draw_system, .Render, {.Position}, {})
	systems := ecs.system_pool_get_systems(&pool)
	testing.expect_value(t, len(systems), 1)
	testing.expect_value(t, systems[0].stage, Stage.Render)
}

// >------------------------------------------------------------------- Register

@(test)
system_pool_register_stores_the_system :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool, 8)
	defer ecs.system_pool_destroy(&pool)

	ecs.system_pool_register(&pool, move_system, .Update, {.Velocity}, {.Position})

	systems := ecs.system_pool_get_systems(&pool)
	testing.expect_value(t, len(systems), 1)
	testing.expect_value(t, systems[0].reads, bit_set[System_Part]{.Velocity})
	testing.expect_value(t, systems[0].writes, bit_set[System_Part]{.Position})
	testing.expect_value(t, systems[0].stage, Stage.Update)
	testing.expect(t, systems[0].system == move_system)
}

@(test)
system_pool_register_keeps_order :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool, 8)
	defer ecs.system_pool_destroy(&pool)

	ecs.system_pool_register(&pool, draw_system, .Render, {.Position}, {})
	ecs.system_pool_register(&pool, move_system, .Update, {.Velocity}, {.Position})
	ecs.system_pool_register(&pool, draw_system, .Render, {}, {})

	systems := ecs.system_pool_get_systems(&pool)
	testing.expect_value(t, len(systems), 3)
	testing.expect(t, systems[0].system == draw_system)
	testing.expect(t, systems[1].system == move_system)
	testing.expect(t, systems[2].system == draw_system)
}

@(test)
system_pool_registered_systems_can_run :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool, 8)
	defer ecs.system_pool_destroy(&pool)

	ecs.system_pool_register(&pool, move_system, .Update, {.Velocity}, {.Position})
	ecs.system_pool_register(&pool, draw_system, .Render, {.Position}, {})
	ecs.system_pool_register(&pool, move_system, .Update, {.Velocity}, {.Position})

	system_calls = {}
	stuff: System_Stuff
	for info in ecs.system_pool_get_systems(&pool) {
		info.system(&stuff)
	}

	testing.expect_value(t, system_calls, [2]int{2, 1})
}

@(test)
system_pool_fills_capacity_exactly :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool, 2)
	defer ecs.system_pool_destroy(&pool)

	ecs.system_pool_register(&pool, move_system, .Update, {}, {})
	ecs.system_pool_register(&pool, draw_system, .Render, {}, {})

	testing.expect_value(t, ecs.system_pool_count_systems(&pool), 2)
}

// >------------------------------------------------------------------- Failures

@(test)
system_pool_register_panics_when_full :: proc(t: ^testing.T) {
	// The panic skips any cleanup, so take the buffer from the stack instead of the heap.
	backing: [256]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: System_Pool
	ecs.system_pool_init(&pool, 1, mem.arena_allocator(&arena))
	ecs.system_pool_register(&pool, move_system, .Update, {}, {})

	testing.expect_assert_message(
		t,
		"System pool is full, the capacity is 1. Consider increasing the capacity.",
	)
	ecs.system_pool_register(&pool, draw_system, .Render, {}, {})
	testing.fail_now(t, "The call did not panic.")
}

@(test)
system_pool_register_nil_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	backing: [256]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: System_Pool
	ecs.system_pool_init(&pool, 1, mem.arena_allocator(&arena))

	testing.expect_assert_message(t, "Cannot register a nil system.")
	ecs.system_pool_register(&pool, nil, .Update, {}, {})
	testing.fail_now(t, "The call did not assert.")
}
