package ecs

import "base:intrinsics"
import "core:fmt"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

System_Info :: struct($P: typeid, $R: typeid, $S: typeid) where intrinsics.type_is_enum(P),
	intrinsics.type_is_enum(R),
	intrinsics.type_is_enum(S) {
	system: proc(stuff: Stuff(P, R, S)),
	reads:  bit_set[P],
	writes: bit_set[P],
	stage:  S,
}

System_Pool :: struct($P: typeid, $R: typeid, $S: typeid) where intrinsics.type_is_enum(P),
	intrinsics.type_is_enum(R),
	intrinsics.type_is_enum(S) {
	systems:   [S][dynamic]System_Info(P, R, S),
	graphs:    [S]^System_Graph,
	allocator: mem.Allocator,
}

System_Graph :: struct {
	adj_matrix:       [SYSTEM_POOL_SIZE * SYSTEM_POOL_SIZE]bool,
	dependency_count: [SYSTEM_POOL_SIZE]int,
	pending_count:    [SYSTEM_POOL_SIZE]int,
	system_count:     int,
}

SYSTEM_POOL_SIZE :: 256

// >---------------------------------------------------------------- System_Info

system_info_conflicts :: proc(a, b: ^System_Info($P, $R, $S)) -> bool {
	return a.writes & b.writes != {} || a.writes & b.reads != {} || a.reads & b.writes != {}
}

// >---------------------------------------------------------------- System_Pool

system_pool_init :: proc(pool: ^System_Pool($P, $R, $S), allocator := context.allocator) {
	for stage in S {
		systems, systems_err := make([dynamic]System_Info(P, R, S), 0, SYSTEM_POOL_SIZE, allocator)
		if systems_err != nil do fmt.panicf("Failed to allocate memory for system pool for stage %v.", stage)

		graph, graph_err := new(System_Graph, allocator)
		if graph_err != nil do fmt.panicf("Failed to allocate memory for system graph for stage %v.", stage)

		pool.systems[stage] = systems
		pool.graphs[stage] = graph
	}

	pool.allocator = allocator
}

system_pool_destroy :: proc(pool: ^System_Pool($P, $R, $S)) {
	for stage in S {
		delete(pool.systems[stage])
		free(pool.graphs[stage], pool.allocator)
	}

	pool^ = System_Pool(P, R, S){}
}

system_pool_reset :: proc(pool: ^System_Pool($P, $R, $S)) {
	for stage in S {
		clear(&pool.systems[stage])
		system_graph_reset(pool.graphs[stage])
	}
}

system_pool_schedule :: proc(
	pool: ^System_Pool($P, $R, $S),
	system: proc(stuff: Stuff(P, R, S)),
	stage: S,
	reads: bit_set[P],
	writes: bit_set[P],
) {
	assert(system != nil, "Cannot schedule a nil system.")

	info := System_Info(P, R, S) {
		system = system,
		reads  = reads,
		writes = writes,
		stage  = stage,
	}

	fmt.assertf(
		len(pool.systems[stage]) < SYSTEM_POOL_SIZE,
		"Cannot schedule more than %v systems in stage %v.",
		SYSTEM_POOL_SIZE,
		stage,
	)

	append(&pool.systems[stage], info)
}

system_pool_count_systems :: proc(pool: ^System_Pool($P, $R, $S)) -> int {
	count := 0
	for stage in S do count += len(pool.systems[stage])
	return count
}

system_pool_build_graphs :: proc(pool: ^System_Pool($P, $R, $S)) {
	for stage in S {
		system_graph_build(pool.graphs[stage], pool.systems[stage][:])
	}
}

system_pool_run_graph_sync :: proc(
	pool: ^System_Pool($P, $R, $S),
	stage: S,
	stuff: Stuff(P, R, S),
) -> int {
	graph := pool.graphs[stage]
	systems := pool.systems[stage][:]

	n := len(systems)
	fmt.assertf(
		graph.system_count == n,
		"System graph for stage %v is stale, it was built for %v systems but there are %v.",
		stage,
		graph.system_count,
		n,
	)

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
	system_graph_refresh(graph)

	return ran
}

// >--------------------------------------------------------------- System_Graph

system_graph_build :: proc(graph: ^System_Graph, systems: []System_Info($P, $R, $S)) {
	system_graph_reset(graph)

	n := len(systems)
	for i in 0 ..< n {
		for j in i + 1 ..< n {
			if system_info_conflicts(&systems[i], &systems[j]) {
				graph.adj_matrix[i * SYSTEM_POOL_SIZE + j] = true
				graph.dependency_count[j] += 1
			}
		}
	}

	graph.system_count = n
	system_graph_refresh(graph)
}

system_graph_reset :: proc(graph: ^System_Graph) {
	graph^ = {}
}

system_graph_refresh :: proc(graph: ^System_Graph) {
	copy(graph.pending_count[:], graph.dependency_count[:])
}
