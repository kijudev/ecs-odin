package ecs

import "base:intrinsics"
import "core:mem"


// >-------------------------------------------------------- Constants and Types

World :: struct($P: typeid, $R: typeid, $S: typeid) where intrinsics.type_is_enum(P),
	intrinsics.type_is_enum(R),
	intrinsics.type_is_enum(S) {
	thing_pool:     Thing_Pool,
	archetype_pool: Archetype_Pool(P),
	cmd_pool:       Cmd_Pool(P),
	part_pool:      Part_Pool(P),
	resource_pool:  Resource_Pool(R),
	system_pool:    System_Pool(P, R, S),
	pool_allocator: mem.Allocator,
}

// >---------------------------------------------------------------- World Setup

world_init :: proc(
	world: ^World($P, $R, $S),
	capacity := THING_POOL_DEFAULT_CAPACITY,
	resource_capacity := RESOURCE_POOL_DEFAULT_CAPACITY,
	pool_allocator := context.allocator,
) {
	// One general purpose allocator for every pool of the world.
	world.pool_allocator = pool_allocator

	thing_pool_init(&world.thing_pool, capacity, world.pool_allocator)
	archetype_pool_init(&world.archetype_pool, capacity, world.pool_allocator)
	cmd_pool_init(&world.cmd_pool, allocator = world.pool_allocator)
	part_pool_init(&world.part_pool, world.pool_allocator)
	resource_pool_init(&world.resource_pool, resource_capacity, world.pool_allocator)
	system_pool_init(&world.system_pool, world.pool_allocator)
}

world_destroy :: proc(world: ^World($P, $R, $S)) {
	thing_pool_destroy(&world.thing_pool)
	archetype_pool_destroy(&world.archetype_pool)
	cmd_pool_destroy(&world.cmd_pool)
	part_pool_destroy(&world.part_pool)
	resource_pool_destroy(&world.resource_pool)
	system_pool_destroy(&world.system_pool)

	world^ = World(P, R, S){}
}

// Kills every thing, zeroes every resource and drops the commands recorded with the `_later`
// procs without applying them. Registrations and scheduled systems are kept.
world_reset :: proc(world: ^World($P, $R, $S)) {
	thing_pool_reset(&world.thing_pool)
	archetype_pool_reset(&world.archetype_pool)
	cmd_pool_reset(&world.cmd_pool)
	part_pool_reset(&world.part_pool)
	resource_pool_reset(&world.resource_pool)
}

world_register :: proc(
	world: ^World($P, $R, $S),
	kind: P,
	$T: typeid,
	destroy: proc(part: rawptr) = nil,
) {
	part_pool_register(&world.part_pool, kind, T, destroy)
}

world_is_registered :: proc(world: ^World($P, $R, $S), kind: P) -> bool {
	return part_pool_is_registered(&world.part_pool, kind)
}

// >--------------------------------------------------------------- World Things

world_spawn :: proc(world: ^World($P, $R, $S)) -> Thing {
	return thing_pool_spawn(&world.thing_pool)
}

world_kill_now :: proc(world: ^World($P, $R, $S), thing: Thing) -> bool {
	if !thing_pool_poke(world.thing_pool, thing) do return false

	it := archetype_iter_make(archetype_pool_get(world.archetype_pool, thing))
	for kind in archetype_iter_next(&it) {
		part_pool_remove_unchecked(&world.part_pool, thing, kind)
	}

	archetype_pool_remove_all(&world.archetype_pool, thing)
	thing_pool_kill_unchecked(&world.thing_pool, thing)
	return true
}

world_poke :: proc(world: ^World($P, $R, $S), thing: Thing) -> bool {
	return thing_pool_poke(world.thing_pool, thing)
}

world_count_alive :: proc(world: ^World($P, $R, $S)) -> int {
	return thing_pool_count_alive(world.thing_pool)
}

world_count_free :: proc(world: ^World($P, $R, $S)) -> int {
	return world.thing_pool.free_count
}

// >---------------------------------------------------------------- World Parts

world_has :: proc(world: ^World($P, $R, $S), thing: Thing, kind: P) -> bool {
	return part_pool_has(&world.part_pool, thing, kind)
}

world_get_part :: proc(world: ^World($P, $R, $S), thing: Thing, kind: P, $T: typeid) -> ^T {
	return part_pool_get(&world.part_pool, thing, kind, T)
}

world_get_parts :: proc(world: ^World($P, $R, $S), kind: P, $T: typeid) -> []T {
	return part_pool_get_parts(&world.part_pool, kind, T)
}

world_get_things :: proc(world: ^World($P, $R, $S), kind: P) -> []Thing {
	return part_pool_get_things(&world.part_pool, kind)
}

world_count_parts :: proc(world: ^World($P, $R, $S), kind: P) -> int {
	return part_pool_count_parts(&world.part_pool, kind)
}

world_set_now :: proc {
	world_set_value_now,
	world_set_pointer_now,
	world_set_zero_now,
}

world_set_value_now :: proc(
	world: ^World($P, $R, $S),
	thing: Thing,
	kind: P,
	part: $T,
) -> ^T where !intrinsics.type_is_pointer(T),
	T !=
	typeid {
	part := part

	return world_set_pointer_now(world, thing, kind, &part)
}

world_set_pointer_now :: proc(world: ^World($P, $R, $S), thing: Thing, kind: P, part: ^$T) -> ^T {
	part_pool_assert_type(&world.part_pool, kind, T)
	return cast(^T)set_raw(world, thing, kind, part)
}

world_set_zero_now :: proc(world: ^World($P, $R, $S), thing: Thing, kind: P, $T: typeid) -> ^T {
	return world_set_pointer_now(world, thing, kind, (^T)(nil))
}

world_add_now :: proc(world: ^World($P, $R, $S), thing: Thing, kind: P) -> bool {
	return set_raw(world, thing, kind, nil) != nil
}

world_remove_now :: proc(world: ^World($P, $R, $S), thing: Thing, kind: P) -> bool {
	if !part_pool_remove(&world.part_pool, thing, kind) do return false

	archetype_pool_remove(&world.archetype_pool, thing, kind)
	return true
}

// >------------------------------------------------------------ World Resources

// The resource starts zeroed.
world_register_resource :: proc(
	world: ^World($P, $R, $S),
	resource: R,
	$T: typeid,
	destroy: proc(resource: rawptr) = nil,
) {
	resource_pool_register(&world.resource_pool, resource, T, destroy)
}

world_is_resource_registered :: proc(world: ^World($P, $R, $S), resource: R) -> bool {
	return resource_pool_is_registered(&world.resource_pool, resource)
}

world_get_resource :: proc(world: ^World($P, $R, $S), resource: R, $T: typeid) -> ^T {
	return resource_pool_get(&world.resource_pool, resource, T)
}

// >------------------------------------------------------------- World Commands

world_kill_later :: proc(world: ^World($P, $R, $S), thing: Thing) {
	if thing == THING_NIL do return
	cmd_pool_record_kill(&world.cmd_pool, thing)
}

world_set_later :: proc {
	world_set_value_later,
	world_set_pointer_later,
	world_set_zero_later,
}

world_set_value_later :: proc(
	world: ^World($P, $R, $S),
	thing: Thing,
	kind: P,
	part: $T,
) where !intrinsics.type_is_pointer(T),
	T !=
	typeid {
	part := part

	world_set_pointer_later(world, thing, kind, &part)
}

world_set_pointer_later :: proc(world: ^World($P, $R, $S), thing: Thing, kind: P, part: ^$T) {
	part_pool_assert_type(&world.part_pool, kind, T)
	if thing == THING_NIL do return

	if part == nil {
		cmd_pool_record_set_zero(&world.cmd_pool, thing, kind)
	} else {
		cmd_pool_record_set_value(&world.cmd_pool, thing, kind, part, size_of(T))
	}
}

world_set_zero_later :: proc(world: ^World($P, $R, $S), thing: Thing, kind: P, $T: typeid) {
	world_set_pointer_later(world, thing, kind, (^T)(nil))
}

world_add_later :: proc(world: ^World($P, $R, $S), thing: Thing, kind: P) {
	part_pool_assert_registered(&world.part_pool, kind)
	if thing == THING_NIL do return

	cmd_pool_record_set_zero(&world.cmd_pool, thing, kind)
}

world_remove_later :: proc(world: ^World($P, $R, $S), thing: Thing, kind: P) {
	part_pool_assert_registered(&world.part_pool, kind)
	if thing == THING_NIL do return

	cmd_pool_record_remove(&world.cmd_pool, thing, kind)
}

world_count_commands :: proc(world: ^World($P, $R, $S)) -> int {
	return len(world.cmd_pool.commands)
}

world_apply_self :: proc(world: ^World($P, $R, $S)) {
	apply_cmds(world, &world.cmd_pool)
	cmd_pool_reset(&world.cmd_pool)
}

world_apply_other :: proc(world: ^World($P, $R, $S), cmds: ^Cmd_Pool(P)) {
	assert(cmds != &world.cmd_pool, "Use apply_self to apply the world's own buffer.")
	apply_cmds(world, cmds)
}

// >-------------------------------------------------------------- World Systems

world_schedule :: proc(
	world: ^World($P, $R, $S),
	system: proc(stuff: Stuff(P, R, S)),
	stage: S,
	reads: bit_set[P],
	writes: bit_set[P],
) {
	system_pool_schedule(&world.system_pool, system, stage, reads, writes)
}

world_count_systems :: proc(world: ^World($P, $R, $S)) -> int {
	return system_pool_count_systems(&world.system_pool)
}

world_run_stage_sync :: proc(world: ^World($P, $R, $S), stage: S) {
	pool := &world.system_pool

	graph := pool.graphs[stage]
	systems := pool.systems[stage][:]
	if graph.system_count != len(systems) do system_graph_build(graph, systems)

	system_pool_run_graph_sync(pool, stage, stuff_make(world))
	world_apply_self(world)
}

world_run_all_sync :: proc(world: ^World($P, $R, $S)) {
	for stage in S do world_run_stage_sync(world, stage)
}

// >------------------------------------------------------------------ Internals

@(private = "file")
set_raw :: proc(world: ^World($P, $R, $S), thing: Thing, kind: P, part: rawptr) -> rawptr {
	part_pool_assert_registered(&world.part_pool, kind)
	if !thing_pool_poke(world.thing_pool, thing) do return nil

	result := part_pool_set_raw(&world.part_pool, thing, kind, part)
	archetype_pool_insert(&world.archetype_pool, thing, kind)

	return result
}

@(private = "file")
apply_cmds :: proc(world: ^World($P, $R, $S), cmds: ^Cmd_Pool(P)) {
	for cmd in cmds.commands {
		switch c in cmd {
		case Cmd_Kill:
			world_kill_now(world, c.thing)

		case Cmd_Set_Value(P):
			part_pool_assert_registered(&world.part_pool, c.kind)
			assert(
				int(c.size) == world.part_pool.sets[c.kind].part_size,
				"Command part size does not match the registered part type.",
			)

			bytes := cmd_pool_get_bytes(cmds, c.offset, c.size)
			set_raw(world, c.thing, c.kind, raw_data(bytes))

		case Cmd_Set_Zero(P):
			set_raw(world, c.thing, c.kind, nil)

		case Cmd_Remove(P):
			world_remove_now(world, c.thing, c.kind)
		}
	}
}
