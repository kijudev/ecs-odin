package ecs

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:mem"


// >-------------------------------------------------------- Constants and Types

/*
Everything the ECS keeps: things, their parts and hierarchies, stashes, deferred commands and
scheduled systems.
`K` is the one enum of part, stash and hierarchy kinds, `S` the enum of system stages.
*/
World :: struct($K: typeid, $S: typeid) where intrinsics.type_is_enum(K),
	intrinsics.type_is_enum(S) {
	thing_pool:     Thing_Pool,
	archetype_pool: Archetype_Pool(K),
	hierarchy_pool: Hierarchy_Pool(K),
	cmd_buffer:     Cmd_Buffer(K),
	part_pool:      Part_Pool(K),
	stash_pool:     Stash_Pool(K),
	system_pool:    System_Pool(K, S),
}

/*
How to size and allocate a world. A zero field takes its default: the matching
`*_DEFAULT_CAPACITY` constant, or `context.allocator` for an allocator.

`static_allocator` gets everything sized here: the thing, archetype, stash and system pools, and
the set of every registered hierarchy. It allocates only during setup, in `world_init` and the
`register_*` procs, and frees only in `world_destroy`, so an arena fits.
`dynamic_allocator` gets everything that grows with use: the part sets and the command buffer. It
allocates, resizes and frees during play.
*/
World_Params :: struct {
	capacity:           int,
	stash_capacity:     int,
	system_capacity:    int,
	cmd_capacity:       int,
	cmd_parts_capacity: int,
	static_allocator:   mem.Allocator,
	dynamic_allocator:  mem.Allocator,
}

// >---------------------------------------------------------------- World Setup

/*
Initializes the world, sized and allocated by `params`. See World_Params.

`capacity` caps the number of things and sizes every hierarchy registered later,
`stash_capacity` the bytes of all stashes together and `system_capacity` the systems of each
stage. `cmd_capacity` and `cmd_parts_capacity` are only the starting room of the command buffer,
it grows past them.

Asserts:
- `capacity` is between THING_POOL_MIN_CAPACITY and THING_POOL_MAX_CAPACITY.
- `stash_capacity` and `system_capacity` are not negative.
- `cmd_capacity` is not negative.
- `cmd_parts_capacity` is between 0 and CMD_BUFFER_MAX_PARTS_CAPACITY.
*/
world_init :: proc(world: ^World($K, $S), params := World_Params{}) {
	params := params

	if params.capacity == 0 do params.capacity = THING_POOL_DEFAULT_CAPACITY
	if params.stash_capacity == 0 do params.stash_capacity = STASH_POOL_DEFAULT_CAPACITY
	if params.system_capacity == 0 do params.system_capacity = SYSTEM_POOL_DEFAULT_CAPACITY
	if params.cmd_capacity == 0 do params.cmd_capacity = CMD_BUFFER_DEFAULT_CAPACITY
	if params.cmd_parts_capacity == 0 do params.cmd_parts_capacity = CMD_BUFFER_DEFAULT_PARTS_CAPACITY
	if params.static_allocator.procedure == nil do params.static_allocator = context.allocator
	if params.dynamic_allocator.procedure == nil do params.dynamic_allocator = context.allocator

	thing_pool_init(&world.thing_pool, params.capacity, params.static_allocator)
	archetype_pool_init(&world.archetype_pool, params.capacity, params.static_allocator)
	hierarchy_pool_init(&world.hierarchy_pool, params.capacity, params.static_allocator)
	stash_pool_init(&world.stash_pool, params.stash_capacity, params.static_allocator)
	system_pool_init(&world.system_pool, params.system_capacity, params.static_allocator)

	part_pool_init(&world.part_pool, params.dynamic_allocator)
	cmd_buffer_init(
		&world.cmd_buffer,
		params.cmd_capacity,
		params.cmd_parts_capacity,
		params.dynamic_allocator,
	)
}

/*
Runs `destroy` on every part and stash, frees every pool and zeroes the world.
*/
world_destroy :: proc(world: ^World($K, $S)) {
	thing_pool_destroy(&world.thing_pool)
	archetype_pool_destroy(&world.archetype_pool)
	hierarchy_pool_destroy(&world.hierarchy_pool)
	cmd_buffer_destroy(&world.cmd_buffer)
	part_pool_destroy(&world.part_pool)
	stash_pool_destroy(&world.stash_pool)
	system_pool_destroy(&world.system_pool)

	world^ = World(K, S){}
}

/*
Kills every thing, empties every hierarchy, zeroes every stash and drops the commands recorded with
the `_later` procs without applying them. `destroy` runs on every part and stash. Registrations
and scheduled systems are kept.
*/
world_reset :: proc(world: ^World($K, $S)) {
	thing_pool_reset(&world.thing_pool)
	archetype_pool_reset(&world.archetype_pool)
	hierarchy_pool_reset(&world.hierarchy_pool)
	cmd_buffer_reset(&world.cmd_buffer)
	part_pool_reset(&world.part_pool)
	stash_pool_reset(&world.stash_pool)
}

/* See register_part. */
world_register_part :: proc(
	world: ^World($K, $S),
	kind: K,
	$T: typeid,
	destroy: proc(part: rawptr) = nil,
) {
	fmt.assertf(
		!stash_pool_is_registered(&world.stash_pool, kind),
		"Kind %v is already registered as a stash.",
		kind,
	)
	fmt.assertf(
		!hierarchy_pool_is_registered(&world.hierarchy_pool, kind),
		"Kind %v is already registered as a hierarchy.",
		kind,
	)
	part_pool_register(&world.part_pool, kind, T, destroy)
}

/* See is_part_registered. */
world_is_part_registered :: proc(world: ^World($K, $S), kind: K) -> bool {
	return part_pool_is_registered(&world.part_pool, kind)
}

// >--------------------------------------------------------------- World Things

/* See spawn. */
world_spawn :: proc(world: ^World($K, $S)) -> Thing {
	return thing_pool_spawn(&world.thing_pool)
}

/* See kill_now. */
world_kill_now :: proc(world: ^World($K, $S), thing: Thing) -> bool {
	if !thing_pool_is_alive(world.thing_pool, thing) do return false

	it := archetype_iter_make(archetype_pool_get(world.archetype_pool, thing))
	for kind in archetype_iter(&it) {
		part_pool_remove_unchecked(&world.part_pool, thing, kind)
	}

	archetype_pool_remove_all(&world.archetype_pool, thing)
	hierarchy_pool_remove_all(&world.hierarchy_pool, thing)
	thing_pool_kill_unchecked(&world.thing_pool, thing)
	return true
}

/* See kill_tree_now. */
world_kill_tree_now :: proc(world: ^World($K, $S), kind: K, thing: Thing) -> bool {
	set := hierarchy_pool_get_set(&world.hierarchy_pool, kind)
	if !thing_pool_is_alive(world.thing_pool, thing) do return false

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	buffer, err := make([]Thing, hierarchy_set_count(set) + 1, context.temp_allocator)
	if err != nil do panic("Failed to allocate memory for killing a tree.")

	tree := hierarchy_set_collect_subtree(set, thing, buffer)
	#reverse for tree_thing in tree do world_kill_now(world, tree_thing)

	return true
}

/* See is_alive. */
world_is_alive :: proc(world: ^World($K, $S), thing: Thing) -> bool {
	return thing_pool_is_alive(world.thing_pool, thing)
}

/* See count_alive. */
world_count_alive :: proc(world: ^World($K, $S)) -> int {
	return thing_pool_count_alive(world.thing_pool)
}

/* See count_free. */
world_count_free :: proc(world: ^World($K, $S)) -> int {
	return world.thing_pool.free_count
}

// >---------------------------------------------------------------- World Parts

/* See has. */
world_has :: proc(world: ^World($K, $S), thing: Thing, kind: K) -> bool {
	return part_pool_has(&world.part_pool, thing, kind)
}

/* See get_part. */
world_get_part :: proc(world: ^World($K, $S), thing: Thing, kind: K, $T: typeid) -> (T, bool) {
	part := part_pool_get(&world.part_pool, thing, kind, T)
	if part == nil do return {}, false

	return part^, true
}

/* See write_part. */
world_write_part :: proc(world: ^World($K, $S), thing: Thing, kind: K, $T: typeid) -> ^T {
	return part_pool_get(&world.part_pool, thing, kind, T)
}

/* See get_parts. */
world_get_parts :: proc(world: ^World($K, $S), kind: K, $T: typeid) -> []T {
	return part_pool_get_parts(&world.part_pool, kind, T)
}

/* See write_parts. */
world_write_parts :: proc(world: ^World($K, $S), kind: K, $T: typeid) -> []T {
	return part_pool_get_parts(&world.part_pool, kind, T)
}

/* See get_things. */
world_get_things :: proc(world: ^World($K, $S), kind: K) -> []Thing {
	return part_pool_get_things(&world.part_pool, kind)
}

/* See count_parts. */
world_count_parts :: proc(world: ^World($K, $S), kind: K) -> int {
	return part_pool_count_parts(&world.part_pool, kind)
}

/* See set_now. */
world_set_value_now :: proc(
	world: ^World($K, $S),
	thing: Thing,
	kind: K,
	part: $T,
) -> ^T where !intrinsics.type_is_pointer(T),
	T !=
	typeid {
	part := part

	return world_set_pointer_now(world, thing, kind, &part)
}

/* See set_now. */
world_set_pointer_now :: proc(world: ^World($K, $S), thing: Thing, kind: K, part: ^$T) -> ^T {
	part_pool_assert_type(&world.part_pool, kind, T)
	return cast(^T)set_raw(world, thing, kind, part)
}

/* See set_now. */
world_set_zero_now :: proc(world: ^World($K, $S), thing: Thing, kind: K, $T: typeid) -> ^T {
	return world_set_pointer_now(world, thing, kind, (^T)(nil))
}

/* See add_now. */
world_add_now :: proc(world: ^World($K, $S), thing: Thing, kind: K) -> bool {
	return set_raw(world, thing, kind, nil) != nil
}

/* See remove_now. */
world_remove_now :: proc(world: ^World($K, $S), thing: Thing, kind: K) -> bool {
	if !part_pool_remove(&world.part_pool, thing, kind) do return false

	archetype_pool_remove(&world.archetype_pool, thing, kind)
	return true
}

// >-------------------------------------------------------------- World Stashes

/* See register_stash. */
world_register_stash :: proc(
	world: ^World($K, $S),
	kind: K,
	$T: typeid,
	destroy: proc(stash: rawptr) = nil,
) {
	fmt.assertf(
		!part_pool_is_registered(&world.part_pool, kind),
		"Kind %v is already registered as a part.",
		kind,
	)
	fmt.assertf(
		!hierarchy_pool_is_registered(&world.hierarchy_pool, kind),
		"Kind %v is already registered as a hierarchy.",
		kind,
	)
	stash_pool_register(&world.stash_pool, kind, T, destroy)
}

/* See is_stash_registered. */
world_is_stash_registered :: proc(world: ^World($K, $S), kind: K) -> bool {
	return stash_pool_is_registered(&world.stash_pool, kind)
}

/* See get_stash. */
world_get_stash :: proc(world: ^World($K, $S), kind: K, $T: typeid) -> T {
	return stash_pool_get(&world.stash_pool, kind, T)^
}

/* See write_stash. */
world_write_stash :: proc(world: ^World($K, $S), kind: K, $T: typeid) -> ^T {
	return stash_pool_get(&world.stash_pool, kind, T)
}

// >------------------------------------------------------------ World Hierarchy

/* See register_hierarchy. */
world_register_hierarchy :: proc(world: ^World($K, $S), kind: K) {
	fmt.assertf(
		!part_pool_is_registered(&world.part_pool, kind),
		"Kind %v is already registered as a part.",
		kind,
	)
	fmt.assertf(
		!stash_pool_is_registered(&world.stash_pool, kind),
		"Kind %v is already registered as a stash.",
		kind,
	)
	hierarchy_pool_register(&world.hierarchy_pool, kind)
}

/* See is_hierarchy_registered. */
world_is_hierarchy_registered :: proc(world: ^World($K, $S), kind: K) -> bool {
	return hierarchy_pool_is_registered(&world.hierarchy_pool, kind)
}

/* See attach_now. */
world_attach_now :: proc(world: ^World($K, $S), kind: K, child, parent: Thing) -> bool {
	set := hierarchy_pool_get_set(&world.hierarchy_pool, kind)
	if !thing_pool_is_alive(world.thing_pool, child) do return false
	if !thing_pool_is_alive(world.thing_pool, parent) do return false

	hierarchy_set_attach(set, child, parent)
	return true
}

/* See detach_now. */
world_detach_now :: proc(world: ^World($K, $S), kind: K, child: Thing) -> bool {
	set := hierarchy_pool_get_set(&world.hierarchy_pool, kind)
	if !thing_pool_is_alive(world.thing_pool, child) do return false

	return hierarchy_set_detach(set, child)
}

/* See get_parent. */
world_get_parent :: proc(world: ^World($K, $S), kind: K, child: Thing) -> Thing {
	set := hierarchy_pool_get_set(&world.hierarchy_pool, kind)
	if !thing_pool_is_alive(world.thing_pool, child) do return THING_NIL

	return hierarchy_set_parent(set, child)
}

/* See get_first_child. */
world_get_first_child :: proc(world: ^World($K, $S), kind: K, parent: Thing) -> Thing {
	set := hierarchy_pool_get_set(&world.hierarchy_pool, kind)
	if !thing_pool_is_alive(world.thing_pool, parent) do return THING_NIL

	return hierarchy_set_first_child(set, parent)
}

/* See get_next_sibling. */
world_get_next_sibling :: proc(world: ^World($K, $S), kind: K, child: Thing) -> Thing {
	set := hierarchy_pool_get_set(&world.hierarchy_pool, kind)
	if !thing_pool_is_alive(world.thing_pool, child) do return THING_NIL

	return hierarchy_set_next_sibling(set, child)
}

/* See iter_children. */
world_iter_children :: proc(
	world: ^World($K, $S),
	kind: K,
	parent: Thing,
) -> Hierarchy_Children_Iter {
	set := hierarchy_pool_get_set(&world.hierarchy_pool, kind)
	if !thing_pool_is_alive(world.thing_pool, parent) do return Hierarchy_Children_Iter{set = set}

	return hierarchy_set_iter_children(set, parent)
}

/* See iter_roots. */
world_iter_roots :: proc(world: ^World($K, $S), kind: K) -> Hierarchy_Children_Iter {
	return hierarchy_set_iter_roots(hierarchy_pool_get_set(&world.hierarchy_pool, kind))
}

/* See is_ancestor. */
world_is_ancestor :: proc(world: ^World($K, $S), kind: K, ancestor, thing: Thing) -> bool {
	set := hierarchy_pool_get_set(&world.hierarchy_pool, kind)
	if !thing_pool_is_alive(world.thing_pool, ancestor) do return false
	if !thing_pool_is_alive(world.thing_pool, thing) do return false

	return hierarchy_set_is_ancestor(set, ancestor, thing)
}

/* See get_hierarchy_order. */
world_get_hierarchy_order :: proc(world: ^World($K, $S), kind: K) -> []Thing {
	return hierarchy_set_order(hierarchy_pool_get_set(&world.hierarchy_pool, kind))
}

/* See get_hierarchy_depths. */
world_get_hierarchy_depths :: proc(world: ^World($K, $S), kind: K) -> []Hierarchy_Depth {
	return hierarchy_set_depths(hierarchy_pool_get_set(&world.hierarchy_pool, kind))
}

/* See get_hierarchy_ends. */
world_get_hierarchy_ends :: proc(world: ^World($K, $S), kind: K) -> []Hierarchy_Pos {
	return hierarchy_set_ends(hierarchy_pool_get_set(&world.hierarchy_pool, kind))
}

/* See get_subtree. */
world_get_subtree :: proc(world: ^World($K, $S), kind: K, thing: Thing) -> []Thing {
	set := hierarchy_pool_get_set(&world.hierarchy_pool, kind)
	if !thing_pool_is_alive(world.thing_pool, thing) do return nil

	return hierarchy_set_subtree(set, thing)
}

/*
Checks whether things were attached, detached or killed in the hierarchy of `kind` since its last
rebuild.

Asserts:
- `kind` is a registered hierarchy.
*/
world_is_hierarchy_dirty :: proc(world: ^World($K, $S), kind: K) -> bool {
	return hierarchy_set_is_dirty(hierarchy_pool_get_set(&world.hierarchy_pool, kind))
}

/*
Flattens the hierarchy of `kind` into the order that `get_hierarchy_order`,
`get_hierarchy_depths`, `get_hierarchy_ends`, `get_subtree` and `is_ancestor` read. Nothing calls
it on its own, so call it wherever the main loop needs those to be up to date. See
hierarchy_set_rebuild.

Asserts:
- `kind` is a registered hierarchy.
- No thing is deeper than HIERARCHY_MAX_DEPTH.
*/
world_rebuild_hierarchy :: proc(world: ^World($K, $S), kind: K) {
	hierarchy_set_rebuild(hierarchy_pool_get_set(&world.hierarchy_pool, kind))
}

/*
Rebuilds every registered hierarchy that changed since its last rebuild, see
`world_rebuild_hierarchy`.

Asserts:
- No thing is deeper than HIERARCHY_MAX_DEPTH.
*/
world_rebuild_hierarchies :: proc(world: ^World($K, $S)) {
	pool := &world.hierarchy_pool
	for kind in pool.registered {
		set := &pool.sets[kind]
		if hierarchy_set_is_dirty(set) do hierarchy_set_rebuild(set)
	}
}

// >------------------------------------------------------------- World Commands

/* See kill_later. */
world_kill_later :: proc(world: ^World($K, $S), thing: Thing) {
	if thing == THING_NIL do return
	cmd_buffer_record_kill(&world.cmd_buffer, thing)
}

/* See kill_tree_later. */
world_kill_tree_later :: proc(world: ^World($K, $S), kind: K, thing: Thing) {
	hierarchy_pool_assert_registered(&world.hierarchy_pool, kind)
	if thing == THING_NIL do return

	cmd_buffer_record_kill_tree(&world.cmd_buffer, kind, thing)
}

/* See attach_later. */
world_attach_later :: proc(world: ^World($K, $S), kind: K, child, parent: Thing) {
	hierarchy_pool_assert_registered(&world.hierarchy_pool, kind)
	if child == THING_NIL || parent == THING_NIL do return

	fmt.assertf(
		child.idx != parent.idx,
		"Hierarchy thing %v can't be attached to itself.",
		child.idx,
	)
	cmd_buffer_record_attach(&world.cmd_buffer, kind, child, parent)
}

/* See detach_later. */
world_detach_later :: proc(world: ^World($K, $S), kind: K, child: Thing) {
	hierarchy_pool_assert_registered(&world.hierarchy_pool, kind)
	if child == THING_NIL do return

	cmd_buffer_record_detach(&world.cmd_buffer, kind, child)
}

/* See set_later. */
world_set_value_later :: proc(
	world: ^World($K, $S),
	thing: Thing,
	kind: K,
	part: $T,
) where !intrinsics.type_is_pointer(T),
	T !=
	typeid {
	part := part

	world_set_pointer_later(world, thing, kind, &part)
}

/* See set_later. */
world_set_pointer_later :: proc(world: ^World($K, $S), thing: Thing, kind: K, part: ^$T) {
	part_pool_assert_type(&world.part_pool, kind, T)
	if thing == THING_NIL do return

	if part == nil {
		cmd_buffer_record_set_zero(&world.cmd_buffer, thing, kind)
	} else {
		cmd_buffer_record_set_value(&world.cmd_buffer, thing, kind, part, size_of(T))
	}
}

/* See set_later. */
world_set_zero_later :: proc(world: ^World($K, $S), thing: Thing, kind: K, $T: typeid) {
	world_set_pointer_later(world, thing, kind, (^T)(nil))
}

/* See add_later. */
world_add_later :: proc(world: ^World($K, $S), thing: Thing, kind: K) {
	part_pool_assert_registered(&world.part_pool, kind)
	if thing == THING_NIL do return

	cmd_buffer_record_set_zero(&world.cmd_buffer, thing, kind)
}

/* See remove_later. */
world_remove_later :: proc(world: ^World($K, $S), thing: Thing, kind: K) {
	part_pool_assert_registered(&world.part_pool, kind)
	if thing == THING_NIL do return

	cmd_buffer_record_remove(&world.cmd_buffer, thing, kind)
}

/* Counts the commands recorded with the `_later` procs and not applied yet. */
world_count_cmds :: proc(world: ^World($K, $S)) -> int {
	return len(world.cmd_buffer.cmds)
}

/*
Applies the commands recorded with the `_later` procs in record order, then clears them.
*/
world_apply :: proc(world: ^World($K, $S)) {
	apply_cmds(world, &world.cmd_buffer)
	cmd_buffer_reset(&world.cmd_buffer)
}

/*
Applies a buffer recorded outside the world in record order. The buffer is left untouched, so
it can be applied to several worlds; resetting it is up to the caller.

Asserts:
- `buffer` is not the world's own buffer, use `world_apply` for that.
- every part kind in the buffer is a registered part, and set values match its type's size.
- every hierarchy kind in the buffer is a registered hierarchy.
*/
world_apply_buffer :: proc(world: ^World($K, $S), buffer: ^Cmd_Buffer(K)) {
	assert(buffer != &world.cmd_buffer, "Use world_apply to apply the world's own buffer.")
	apply_cmds(world, buffer)
}

// >-------------------------------------------------------------- World Systems

/*
Schedules a system into a stage under `name`, with the kinds it reads and writes. Part, stash and hierarchy
kinds all count. Systems whose kinds conflict run in schedule order, nothing checks that a system
only touches what it declared.

Asserts:
- `system` is not nil.
- `name` is not empty.
- the stage has fewer systems than `system_capacity`.
*/
world_schedule :: proc(
	world: ^World($K, $S),
	system: proc(stuff: Stuff(K, S)),
	name: string,
	stage: S,
	reads: bit_set[K],
	writes: bit_set[K],
) {
	system_pool_schedule(&world.system_pool, system, name, stage, reads, writes)
}

/* Counts the systems scheduled in every stage. */
world_count_systems :: proc(world: ^World($K, $S)) -> int {
	return system_pool_count_systems(&world.system_pool)
}

/*
Runs every system of the stage once on this thread, ordered by their conflicts. The commands they
record stay in the buffer until `world_apply`. The stage graph is rebuilt first when systems were
scheduled since the last run.
*/
world_run_stage_sync :: proc(world: ^World($K, $S), stage: S) {
	pool := &world.system_pool

	graph := &pool.graphs[stage]
	systems := system_pool_get_systems(pool, stage)
	if graph.system_count != len(systems) do system_graph_build(graph, systems)

	system_pool_run_stage_sync(pool, stage, stuff_make(world))
}

/* Runs every stage with `world_run_stage_sync`, in the order of `S`. */
world_run_sync :: proc(world: ^World($K, $S)) {
	for stage in S do world_run_stage_sync(world, stage)
}

// >------------------------------------------------------------------ Internals

@(private = "file")
set_raw :: proc(world: ^World($K, $S), thing: Thing, kind: K, part: rawptr) -> rawptr {
	part_pool_assert_registered(&world.part_pool, kind)
	if !thing_pool_is_alive(world.thing_pool, thing) do return nil

	result := part_pool_set_raw(&world.part_pool, thing, kind, part)
	archetype_pool_insert(&world.archetype_pool, thing, kind)

	return result
}

@(private = "file")
apply_cmds :: proc(world: ^World($K, $S), buffer: ^Cmd_Buffer(K)) {
	for cmd in buffer.cmds {
		switch c in cmd {
		case Cmd_Kill:
			world_kill_now(world, c.thing)

		case Cmd_Set_Value(K):
			part_pool_assert_registered(&world.part_pool, c.kind)
			assert(
				int(c.size) == world.part_pool.sets[c.kind].part_size,
				"Command part size does not match the registered part type.",
			)

			bytes := cmd_buffer_get_bytes(buffer, c.offset, c.size)
			set_raw(world, c.thing, c.kind, raw_data(bytes))

		case Cmd_Set_Zero(K):
			set_raw(world, c.thing, c.kind, nil)

		case Cmd_Remove(K):
			world_remove_now(world, c.thing, c.kind)

		case Cmd_Attach(K):
			set := hierarchy_pool_get_set(&world.hierarchy_pool, c.kind)
			if !thing_pool_is_alive(world.thing_pool, c.child) do continue
			if !thing_pool_is_alive(world.thing_pool, c.parent) do continue
			if !hierarchy_set_can_attach(set, c.child, c.parent) do continue

			hierarchy_set_attach(set, c.child, c.parent)

		case Cmd_Detach(K):
			world_detach_now(world, c.kind, c.child)

		case Cmd_Kill_Tree(K):
			world_kill_tree_now(world, c.kind, c.thing)
		}
	}
}
