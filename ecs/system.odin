package ecs

import "base:intrinsics"
import "core:fmt"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

System_Info :: struct($P: typeid, $R: typeid, $S: typeid) where intrinsics.type_is_enum(P),
	intrinsics.type_is_enum(R),
	intrinsics.type_is_enum(S) {
	system: proc(c: ^Stuff(P, R, S)),
	reads:  bit_set[P],
	writes: bit_set[P],
	stage:  S,
}

System_Pool :: struct($P: typeid, $R: typeid, $S: typeid) where intrinsics.type_is_enum(P),
	intrinsics.type_is_enum(R),
	intrinsics.type_is_enum(S) {
	systems:   [S][dynamic]System_Info(P, R, S),
	graphs:    [S]^System_Graph(P, R, S),
	allocator: mem.Allocator,
}

System_Graph :: struct {
	adj_matrix:       [SYSTEM_POOL_SIZE * SYSTEM_POOL_SIZE]bool,
	dependency_count: [SYSTEM_POOL_SIZE]int,
	pending_count:    [SYSTEM_POOL_SIZE]int,
}

SYSTEM_POOL_SIZE :: 256

// >---------------------------------------------------------------- System_Info

system_info_conflicts :: proc(a, b: ^System_Info($P, $R, $S)) -> bool {
	return a.writes & b.writes != {} || a.writes & b.reads != {} || a.reads & b.writes != {}
}

// >---------------------------------------------------------------- System_Pool

system_pool_init :: proc(pool: ^System_Pool($P, $R, $S), allocator := context.allocator) {
	fmt.assertf(capacity >= 0, "System pool capacity cannot be negative, got %v.", capacity)

	for stage in S {
		system, err := make([]System_Info(P, R, S), SYSTEM_POOL_SIZE, allocator)
		if err != nil do fmt.panicf("Failed to allocate memory for system pool for stage %v.", stage)

		graph, err := make(^System_Graph(P, R, S), 1, allocator)
		if err != nil do fmt.panicf("Failed to allocate memory for system graph for stage %v.", stage)

		pool.systems[stage] = system
		pool.graphs[stage] = graph
	}

	pool.allocator = allocator
}

system_pool_destroy :: proc(pool: ^System_Pool($P, $R, $S)) {
	for stage in S {
		delete(pool.systems[stage], pool.allocator)
		delete(pool.graphs[stage], pool.allocator)
	}

	pool^ = System_Pool(P, R, S){}
}

system_pool_reset :: proc(pool: ^System_Pool($P, $R, $S)) {
	for stage in S {
		mem.zero_slice(pool.systems[stage][:])
		pool.graphs[stage] = {}
	}
}

system_pool_register :: proc(
	pool: ^System_Pool($P, $R, $S),
	system: proc(stuff: ^Stuff(P, R, S)),
	stage: S,
	reads: bit_set[P],
	writes: bit_set[P],
) {
	assert(system != nil, "Cannot register a nil system.")

	info := System_Info(P, R, S) {
		system = system,
		reads  = reads,
		writes = writes,
		stage  = stage,
	}

	fmt.assertf(
		pool.systems_size < SYSTEM_POOL_SIZE,
		"Cannot register more than %v systems in the pool.",
		SYSTEM_POOL_SIZE,
	)

	append(&pool.systems[stage], info)
}

system_pool_count_systems :: proc(pool: ^System_Pool($P, $R, $S)) -> int {
	count := 0
	for stage in S do count += pool.systems_size[stage]
	return count
}

system_pool_get_systems :: proc(
	pool: ^System_Pool($P, $R, $S),
	stage: S,
) -> []System_Info(P, R, S) {
	return pool.systems[stage][:]
}

system_pool_build_graphs :: proc(pool: ^System_Pool($P, $R, $S)) {
	for stage in S {
		system_graph_build(pool.graphs[stage], pool.systems[stage][:])
	}
}

system_pool_run_graph_sync :: proc(
	pool: ^System_Pool($P, $R, $S),
	stage: S,
	stuff: ^Stuff(P, R, S),
) -> int {
	graph := pool.graphs[stage]
	systems := pool.systems[stage][:]

	n := len(systems)
	ran := 0
	ready: [dynamic; SYSTEM_POOL_SIZE]int
	for i in 0 ..< n do if graph.pending_count[i] == 0 do append(&ready, i)

	for len(ready) > 0 {
		i := pop(&ready)
		systems[i].system(stuff)
		ran += 1

		for j in i + 1 ..< n do if graph.adj_matrix[i * SYSTEM_POOL_SIZE + j] {
			graph.pending_count[j] -= 1
			if graph.pending_count[j] == 0 do append(&ready, j)
		}
	}

	fmt.assertf(ran == n, "Not all systems ran in stage %v. Ran %v out of %v.", stage, ran, n)

	return ran
}

// >--------------------------------------------------------------- System_Graph

system_graph_build :: proc(graph: ^System_Graph, systems: []System_Info($P, $R, $S)) {
	system_graph_reset(graph)

	for _, i in systems {
		for _, j in systems {
			if i == j do continue
			if system_info_conflicts(systems[i], systems[j]) {
				graph.adj_matrix[i * SYSTEM_POOL_SIZE + j] = true
				graph.dependency_count[j] += 1
			}
		}
	}

	system_graph_refresh(graph)
}

system_graph_reset :: proc(graph: ^System_Graph) {
	graph^ = {}
}

system_graph_refresh :: proc(graph: ^System_Graph) {
	copy(graph.pending_count[:], graph.dependency_count[:])
}
