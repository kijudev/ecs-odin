package ecs

import "base:intrinsics"
import "core:fmt"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

/* A scheduled system, with the kinds it reads and writes and the stage it runs in. */
System_Info :: struct($K: typeid, $S: typeid) where intrinsics.type_is_enum(K),
	intrinsics.type_is_enum(S) {
	system: proc(stuff: Stuff(K, S)),
	reads:  bit_set[K],
	writes: bit_set[K],
	stage:  S,
}

/*
Holds the systems of each stage in schedule order, plus a dependency graph per stage that decides
the order they run in. Every stage has room for `capacity` systems, allocated up front.
*/
System_Pool :: struct($K: typeid, $S: typeid) where intrinsics.type_is_enum(K),
	intrinsics.type_is_enum(S) {
	systems:   [S][]System_Info(K, S),
	counts:    [S]int,
	graphs:    [S]System_Graph,
	capacity:  int,
	allocator: mem.Allocator,
}

/*
The dependencies between the systems of one stage. A system depends on every earlier system it
conflicts with: `adj_matrix[i * capacity + j]` means `j` waits for `i`. `pending_count` counts
down while the stage runs, and `ready` holds the systems whose turn has come.
*/
System_Graph :: struct {
	adj_matrix:       []bool,
	dependency_count: []int,
	pending_count:    []int,
	ready:            []int,
	capacity:         int,
	system_count:     int,
	allocator:        mem.Allocator,
}

// >---------------------------------------------------------------- System_Info

/* Checks whether the systems conflict: one writes a kind the other reads or writes. */
system_info_conflicts :: proc(a, b: ^System_Info($K, $S)) -> bool {
	return a.writes & b.writes != {} || a.writes & b.reads != {} || a.reads & b.writes != {}
}

// >---------------------------------------------------------------- System_Pool

/*
Initializes the pool with room for `capacity` systems and their graph in every stage, allocated
up front with `allocator`.

Asserts:
- `capacity` is greater than 0.
*/
system_pool_init :: proc(
	pool: ^System_Pool($K, $S),
	capacity := SYSTEM_POOL_DEFAULT_CAPACITY,
	allocator := context.allocator,
) {
	fmt.assertf(capacity > 0, "System pool capacity has to be greater than 0, got %v.", capacity)

	pool^ = System_Pool(K, S) {
		capacity  = capacity,
		allocator = allocator,
	}

	for stage in S {
		systems, err := make([]System_Info(K, S), capacity, allocator)
		if err != nil do fmt.panicf("Failed to allocate memory for system pool for stage %v.", stage)

		pool.systems[stage] = systems
		system_graph_init(&pool.graphs[stage], capacity, allocator)
	}
}

/* Frees the pool with the allocator it was initialized with and zeroes it. */
system_pool_destroy :: proc(pool: ^System_Pool($K, $S)) {
	for stage in S {
		delete(pool.systems[stage], pool.allocator)
		system_graph_destroy(&pool.graphs[stage])
	}

	pool^ = System_Pool(K, S){}
}

/* Unschedules every system and clears every graph. */
system_pool_reset :: proc(pool: ^System_Pool($K, $S)) {
	for stage in S {
		pool.counts[stage] = 0
		system_graph_reset(&pool.graphs[stage])
	}
}

/*
Schedules the system in `stage`, declaring the kinds it reads and writes. Of two conflicting
systems, the one scheduled first runs first. The stage's graph is stale until
`system_pool_build_graphs`.

Asserts:
- `system` is not nil.
- the stage has fewer systems than the pool capacity.
*/
system_pool_schedule :: proc(
	pool: ^System_Pool($K, $S),
	system: proc(stuff: Stuff(K, S)),
	stage: S,
	reads: bit_set[K],
	writes: bit_set[K],
) {
	assert(system != nil, "Cannot schedule a nil system.")
	fmt.assertf(
		pool.counts[stage] < pool.capacity,
		"Cannot schedule more than %v systems in stage %v.",
		pool.capacity,
		stage,
	)

	pool.systems[stage][pool.counts[stage]] = System_Info(K, S) {
		system = system,
		reads  = reads,
		writes = writes,
		stage  = stage,
	}
	pool.counts[stage] += 1
}

/* Counts the systems scheduled in every stage. */
system_pool_count_systems :: proc(pool: ^System_Pool($K, $S)) -> int {
	count := 0
	for stage in S do count += pool.counts[stage]
	return count
}

/*
Gets the systems scheduled in the stage, in schedule order.

The slice is valid until the pool is destroyed. Scheduling and resetting change its contents.
*/
system_pool_get_systems :: proc(pool: ^System_Pool($K, $S), stage: S) -> []System_Info(K, S) {
	return pool.systems[stage][:pool.counts[stage]]
}

/*
Builds the dependency graph of every stage from its scheduled systems. Call it after scheduling
and before running.
*/
system_pool_build_graphs :: proc(pool: ^System_Pool($K, $S)) {
	for stage in S {
		system_graph_build(&pool.graphs[stage], system_pool_get_systems(pool, stage))
	}
}

/*
Runs every system of the stage once on this thread. A system runs only after every earlier
system it conflicts with.

Returns the number of systems that ran.

Asserts:
- the stage's graph was built after its systems last changed.
*/
system_pool_run_stage_sync :: proc(
	pool: ^System_Pool($K, $S),
	stage: S,
	stuff: Stuff(K, S),
) -> int {
	graph := &pool.graphs[stage]
	systems := system_pool_get_systems(pool, stage)

	n := len(systems)
	fmt.assertf(
		graph.system_count == n,
		"System graph for stage %v is stale, it was built for %v systems but there are %v.",
		stage,
		graph.system_count,
		n,
	)

	ran := 0
	ready_count := 0
	for i in 0 ..< n do if graph.pending_count[i] == 0 {
		graph.ready[ready_count] = i
		ready_count += 1
	}

	for ready_count > 0 {
		ready_count -= 1
		i := graph.ready[ready_count]
		systems[i].system(stuff)
		ran += 1

		for j in i + 1 ..< n do if graph.adj_matrix[i * graph.capacity + j] {
			graph.pending_count[j] -= 1
			if graph.pending_count[j] == 0 {
				graph.ready[ready_count] = j
				ready_count += 1
			}
		}
	}

	fmt.assertf(ran == n, "Not all systems ran in stage %v. Ran %v out of %v.", stage, ran, n)
	system_graph_refresh(graph)

	return ran
}

// >--------------------------------------------------------------- System_Graph

/*
Initializes the graph with room for `capacity` systems, allocated up front with `allocator`.

Asserts:
- `capacity` is greater than 0.
*/
system_graph_init :: proc(graph: ^System_Graph, capacity: int, allocator := context.allocator) {
	fmt.assertf(capacity > 0, "System graph capacity has to be greater than 0, got %v.", capacity)

	adj_matrix, adj_err := make([]bool, capacity * capacity, allocator)
	if adj_err != nil do panic("Failed to allocate memory for system graph.")

	dependency_count, dependency_err := make([]int, capacity, allocator)
	if dependency_err != nil do panic("Failed to allocate memory for system graph.")

	pending_count, pending_err := make([]int, capacity, allocator)
	if pending_err != nil do panic("Failed to allocate memory for system graph.")

	ready, ready_err := make([]int, capacity, allocator)
	if ready_err != nil do panic("Failed to allocate memory for system graph.")

	graph^ = System_Graph {
		adj_matrix       = adj_matrix,
		dependency_count = dependency_count,
		pending_count    = pending_count,
		ready            = ready,
		capacity         = capacity,
		system_count     = 0,
		allocator        = allocator,
	}
}

/* Frees the graph with the allocator it was initialized with and zeroes it. */
system_graph_destroy :: proc(graph: ^System_Graph) {
	delete(graph.adj_matrix, graph.allocator)
	delete(graph.dependency_count, graph.allocator)
	delete(graph.pending_count, graph.allocator)
	delete(graph.ready, graph.allocator)
	graph^ = System_Graph{}
}

/*
Builds the graph from the systems of one stage, in schedule order. Each system depends on every
earlier one it conflicts with.

Asserts:
- there are no more systems than the graph capacity.
*/
system_graph_build :: proc(graph: ^System_Graph, systems: []System_Info($K, $S)) {
	n := len(systems)
	fmt.assertf(
		n <= graph.capacity,
		"System graph has room for %v systems, got %v.",
		graph.capacity,
		n,
	)

	system_graph_reset(graph)

	for i in 0 ..< n {
		for j in i + 1 ..< n {
			if system_info_conflicts(&systems[i], &systems[j]) {
				graph.adj_matrix[i * graph.capacity + j] = true
				graph.dependency_count[j] += 1
			}
		}
	}

	graph.system_count = n
	system_graph_refresh(graph)
}

/* Clears the graph, leaving it built for no systems. */
system_graph_reset :: proc(graph: ^System_Graph) {
	mem.zero_slice(graph.adj_matrix)
	mem.zero_slice(graph.dependency_count)
	mem.zero_slice(graph.pending_count)
	graph.system_count = 0
}

/* Resets the pending counts so the stage can run again. */
system_graph_refresh :: proc(graph: ^System_Graph) {
	copy(graph.pending_count, graph.dependency_count)
}
