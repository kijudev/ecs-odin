package ecs_tests

import "core:mem"
import "core:testing"

import ecs "../ecs"

@(private = "file")
system_graph_edge :: proc(graph: ^ecs.System_Graph, from, to: int) -> bool {
	return graph.adj_matrix[from * ecs.SYSTEM_POOL_SIZE + to]
}

// >---------------------------------------------------------------- System_Info

@(test)
system_info_conflicts_on_shared_writes :: proc(t: ^testing.T) {
	reader_pos := System {
		reads = {.Position},
	}
	reader_pos_2 := System {
		reads = {.Position},
	}
	writer_pos := System {
		writes = {.Position},
	}
	writer_pos_2 := System {
		writes = {.Position},
	}
	writer_vel := System {
		writes = {.Velocity},
	}

	testing.expect(t, !ecs.system_info_conflicts(&reader_pos, &reader_pos_2), "read/read")
	testing.expect(t, ecs.system_info_conflicts(&reader_pos, &writer_pos), "read/write")
	testing.expect(t, ecs.system_info_conflicts(&writer_pos, &reader_pos), "write/read")
	testing.expect(t, ecs.system_info_conflicts(&writer_pos, &writer_pos_2), "write/write")
	testing.expect(t, !ecs.system_info_conflicts(&writer_pos, &writer_vel), "disjoint writes")
	testing.expect(t, !ecs.system_info_conflicts(&reader_pos, &writer_vel), "disjoint read/write")
}

// >------------------------------------------------------------------ Lifecycle

@(test)
system_pool_init_creates_empty_pool :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool)
	defer ecs.system_pool_destroy(&pool)

	testing.expect_value(t, ecs.system_pool_count_systems(&pool), 0)
	for stage in Stage {
		testing.expect_value(t, len(ecs.system_pool_get_systems(&pool, stage)), 0)
		testing.expect(t, pool.graphs[stage] != nil)
	}
}

@(test)
system_pool_destroy_frees_with_init_allocator :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	pool: System_Pool
	ecs.system_pool_init(&pool, mem.tracking_allocator(&track))
	ecs.system_pool_schedule(&pool, system_a, .Update, {.Velocity}, {.Position})
	testing.expect(t, len(track.allocation_map) > 0)

	// Destroy runs under the default context.allocator, not the init one.
	ecs.system_pool_destroy(&pool)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
system_pool_reset_removes_systems :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool)
	defer ecs.system_pool_destroy(&pool)

	ecs.system_pool_schedule(&pool, system_a, .Update, {}, {.Position})
	ecs.system_pool_schedule(&pool, system_b, .Update, {}, {.Position})
	ecs.system_pool_build_graphs(&pool)
	ecs.system_pool_reset(&pool)

	testing.expect_value(t, ecs.system_pool_count_systems(&pool), 0)
	testing.expect_value(t, len(ecs.system_pool_get_systems(&pool, .Update)), 0)
	testing.expect(t, pool.graphs[.Update] != nil, "reset must keep the graph allocation")
	testing.expect(t, !system_graph_edge(pool.graphs[.Update], 0, 1), "reset must clear the graph")
}

@(test)
system_pool_usable_after_reset :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool)
	defer ecs.system_pool_destroy(&pool)

	ecs.system_pool_schedule(&pool, system_a, .Update, {}, {.Position})
	ecs.system_pool_build_graphs(&pool)
	ecs.system_pool_reset(&pool)

	ecs.system_pool_schedule(&pool, system_b, .Update, {}, {})
	ecs.system_pool_build_graphs(&pool)

	clear(&system_log)
	stuff: Stuff
	testing.expect_value(t, ecs.system_pool_run_graph_sync(&pool, .Update, &stuff), 1)
	testing.expect_value(t, len(system_log), 1)
	testing.expect_value(t, system_log_count(1), 1)
}

// >------------------------------------------------------------------- Schedule

@(test)
system_pool_schedule_stores_the_system :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool)
	defer ecs.system_pool_destroy(&pool)

	ecs.system_pool_schedule(&pool, system_a, .Update, {.Velocity}, {.Position})

	systems := ecs.system_pool_get_systems(&pool, .Update)
	testing.expect_value(t, len(systems), 1)
	testing.expect_value(t, systems[0].reads, bit_set[Part]{.Velocity})
	testing.expect_value(t, systems[0].writes, bit_set[Part]{.Position})
	testing.expect_value(t, systems[0].stage, Stage.Update)
	testing.expect(t, systems[0].system == system_a)
}

@(test)
system_pool_schedule_groups_by_stage_in_order :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool)
	defer ecs.system_pool_destroy(&pool)

	ecs.system_pool_schedule(&pool, system_a, .Render, {}, {})
	ecs.system_pool_schedule(&pool, system_b, .Update, {}, {})
	ecs.system_pool_schedule(&pool, system_c, .Render, {}, {})

	testing.expect_value(t, ecs.system_pool_count_systems(&pool), 3)

	update := ecs.system_pool_get_systems(&pool, .Update)
	testing.expect_value(t, len(update), 1)
	testing.expect(t, update[0].system == system_b)

	render := ecs.system_pool_get_systems(&pool, .Render)
	testing.expect_value(t, len(render), 2)
	testing.expect(t, render[0].system == system_a)
	testing.expect(t, render[1].system == system_c)
}

@(test)
system_pool_fills_a_stage_exactly :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool)
	defer ecs.system_pool_destroy(&pool)

	for _ in 0 ..< ecs.SYSTEM_POOL_SIZE do ecs.system_pool_schedule(&pool, system_a, .Update, {}, {})
	// The limit is per stage, other stages still have room.
	ecs.system_pool_schedule(&pool, system_b, .Render, {}, {})

	testing.expect_value(t, ecs.system_pool_count_systems(&pool), ecs.SYSTEM_POOL_SIZE + 1)
}

// >---------------------------------------------------------------------- Graph

@(test)
system_graph_independent_systems_have_no_edges :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool)
	defer ecs.system_pool_destroy(&pool)

	ecs.system_pool_schedule(&pool, system_a, .Update, {.Velocity}, {.Position})
	ecs.system_pool_schedule(&pool, system_b, .Update, {.Velocity}, {.Health})
	ecs.system_pool_build_graphs(&pool)

	graph := pool.graphs[.Update]
	testing.expect(t, !system_graph_edge(graph, 0, 1))
	testing.expect(t, !system_graph_edge(graph, 1, 0))
	testing.expect_value(t, graph.dependency_count[0], 0)
	testing.expect_value(t, graph.dependency_count[1], 0)
}

@(test)
system_graph_conflict_points_from_earlier_to_later :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool)
	defer ecs.system_pool_destroy(&pool)

	ecs.system_pool_schedule(&pool, system_a, .Update, {}, {.Position})
	ecs.system_pool_schedule(&pool, system_b, .Update, {.Position}, {})
	ecs.system_pool_build_graphs(&pool)

	graph := pool.graphs[.Update]
	testing.expect(t, system_graph_edge(graph, 0, 1), "earlier system must run first")
	testing.expect(t, !system_graph_edge(graph, 1, 0), "edge must not point backwards")
	testing.expect_value(t, graph.dependency_count[0], 0)
	testing.expect_value(t, graph.dependency_count[1], 1)
	testing.expect_value(t, graph.pending_count[1], 1)
}

@(test)
system_graph_only_links_systems_within_a_stage :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool)
	defer ecs.system_pool_destroy(&pool)

	ecs.system_pool_schedule(&pool, system_a, .Update, {}, {.Position})
	ecs.system_pool_schedule(&pool, system_b, .Render, {}, {.Position})
	ecs.system_pool_build_graphs(&pool)

	testing.expect_value(t, pool.graphs[.Update].dependency_count[0], 0)
	testing.expect_value(t, pool.graphs[.Render].dependency_count[0], 0)
}

@(test)
system_graph_rebuild_drops_old_edges :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool)
	defer ecs.system_pool_destroy(&pool)

	ecs.system_pool_schedule(&pool, system_a, .Update, {}, {.Position})
	ecs.system_pool_schedule(&pool, system_b, .Update, {}, {.Position})
	ecs.system_pool_build_graphs(&pool)
	ecs.system_pool_build_graphs(&pool)

	graph := pool.graphs[.Update]
	testing.expect_value(t, graph.dependency_count[1], 1)
}

// >------------------------------------------------------------------------ Run

@(test)
system_pool_run_graph_sync_runs_each_system_once :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool)
	defer ecs.system_pool_destroy(&pool)

	ecs.system_pool_schedule(&pool, system_a, .Update, {}, {.Position})
	ecs.system_pool_schedule(&pool, system_b, .Update, {}, {.Velocity})
	ecs.system_pool_schedule(&pool, system_c, .Update, {.Position}, {})
	ecs.system_pool_schedule(&pool, system_d, .Render, {}, {})
	ecs.system_pool_build_graphs(&pool)

	clear(&system_log)
	stuff: Stuff
	testing.expect_value(t, ecs.system_pool_run_graph_sync(&pool, .Update, &stuff), 3)

	testing.expect_value(t, len(system_log), 3)
	for id in 0 ..< 3 do testing.expect_value(t, system_log_count(id), 1)
	testing.expect_value(t, system_log_count(3), 0)
}

@(test)
system_pool_run_graph_sync_respects_conflicts :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool)
	defer ecs.system_pool_destroy(&pool)

	// a -> b -> c is a chain, d is independent.
	ecs.system_pool_schedule(&pool, system_a, .Update, {}, {.Position})
	ecs.system_pool_schedule(&pool, system_b, .Update, {.Position}, {.Velocity})
	ecs.system_pool_schedule(&pool, system_c, .Update, {.Velocity}, {})
	ecs.system_pool_schedule(&pool, system_d, .Update, {.Health}, {})
	ecs.system_pool_build_graphs(&pool)

	clear(&system_log)
	stuff: Stuff
	testing.expect_value(t, ecs.system_pool_run_graph_sync(&pool, .Update, &stuff), 4)

	testing.expect(t, system_log_index(0) < system_log_index(1), "a before b")
	testing.expect(t, system_log_index(1) < system_log_index(2), "b before c")
	testing.expect(t, system_log_index(3) >= 0, "d ran")
}

@(test)
system_pool_run_graph_sync_can_run_again :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool)
	defer ecs.system_pool_destroy(&pool)

	ecs.system_pool_schedule(&pool, system_a, .Update, {}, {.Position})
	ecs.system_pool_schedule(&pool, system_b, .Update, {.Position}, {})
	ecs.system_pool_build_graphs(&pool)

	clear(&system_log)
	stuff: Stuff
	testing.expect_value(t, ecs.system_pool_run_graph_sync(&pool, .Update, &stuff), 2)
	testing.expect_value(t, ecs.system_pool_run_graph_sync(&pool, .Update, &stuff), 2)

	testing.expect_value(t, len(system_log), 4)
	testing.expect_value(t, system_log[2], 0)
	testing.expect_value(t, system_log[3], 1)
}

@(test)
system_pool_run_graph_sync_empty_stage :: proc(t: ^testing.T) {
	pool: System_Pool
	ecs.system_pool_init(&pool)
	defer ecs.system_pool_destroy(&pool)

	ecs.system_pool_build_graphs(&pool)

	stuff: Stuff
	testing.expect_value(t, ecs.system_pool_run_graph_sync(&pool, .Update, &stuff), 0)
}

// >------------------------------------------------------------------- Failures

@(test)
system_pool_schedule_panics_when_stage_full :: proc(t: ^testing.T) {
	// The panic skips any cleanup, so take the memory from a static buffer instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: System_Pool
	ecs.system_pool_init(&pool, mem.arena_allocator(&arena))
	for _ in 0 ..< ecs.SYSTEM_POOL_SIZE do ecs.system_pool_schedule(&pool, system_a, .Update, {}, {})

	testing.expect_assert_message(t, "Cannot schedule more than 256 systems in stage Update.")
	ecs.system_pool_schedule(&pool, system_b, .Update, {}, {})
	testing.fail_now(t, "The call did not panic.")
}

@(test)
system_pool_schedule_nil_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: System_Pool
	ecs.system_pool_init(&pool, mem.arena_allocator(&arena))

	testing.expect_assert_message(t, "Cannot schedule a nil system.")
	ecs.system_pool_schedule(&pool, nil, .Update, {}, {})
	testing.fail_now(t, "The call did not assert.")
}

@(test)
system_pool_run_graph_sync_asserts_on_stale_graph :: proc(t: ^testing.T) {
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	pool: System_Pool
	ecs.system_pool_init(&pool, mem.arena_allocator(&arena))
	ecs.system_pool_schedule(&pool, system_a, .Update, {}, {.Position})
	ecs.system_pool_build_graphs(&pool)
	ecs.system_pool_schedule(&pool, system_b, .Update, {.Position}, {})

	stuff: Stuff
	testing.expect_assert_message(
		t,
		"System graph for stage Update is stale, it was built for 1 systems but there are 2.",
	)
	ecs.system_pool_run_graph_sync(&pool, .Update, &stuff)
	testing.fail_now(t, "The call did not assert.")
}
