package ecs

import "base:intrinsics"
import "core:mem"


// >-------------------------------------------------------- Constants and Types

World :: struct($P: typeid, $R: typeid) where intrinsics.type_is_enum(P),
	intrinsics.type_is_enum(R) {
	thing_pool:     Thing_Pool,
	archetype_pool: Archetype_Pool(P),
	cmd_pool:       Cmd_Pool(P),
	part_pool:      Part_Pool(P),
	resource_pool:  Resource_Pool(R),
	pool_allocator: mem.Allocator,
}

// >---------------------------------------------------------------- World Setup

world_init :: proc(
	world: ^World($P, $R),
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
}

world_destroy :: proc(world: ^World($P, $R)) {
	thing_pool_destroy(&world.thing_pool)
	archetype_pool_destroy(&world.archetype_pool)
	cmd_pool_destroy(&world.cmd_pool)
	part_pool_destroy(&world.part_pool)
	resource_pool_destroy(&world.resource_pool)

	world^ = World(P, R){}
}

// Kills every thing, zeroes every resource and drops the commands recorded with the `_later`
// procs without applying them. Registrations are kept.
world_reset :: proc(world: ^World($P, $R)) {
	thing_pool_reset(&world.thing_pool)
	archetype_pool_reset(&world.archetype_pool)
	cmd_pool_reset(&world.cmd_pool)
	part_pool_reset(&world.part_pool)
	resource_pool_reset(&world.resource_pool)
}

register :: proc(world: ^World($P, $R), kind: P, $T: typeid, destroy: proc(part: rawptr) = nil) {
	part_pool_register(&world.part_pool, kind, T, destroy)
}

is_registered :: proc(world: ^World($P, $R), kind: P) -> bool {
	return part_pool_is_registered(&world.part_pool, kind)
}

// >--------------------------------------------------------------- World Things

spawn :: proc(world: ^World($P, $R)) -> Thing {
	return thing_pool_spawn(&world.thing_pool)
}

kill_now :: proc(world: ^World($P, $R), thing: Thing) -> bool {
	if !thing_pool_poke(world.thing_pool, thing) do return false

	for kind in archetype_pool_get_mask(world.archetype_pool, thing) {
		part_pool_remove_unchecked(&world.part_pool, thing, kind)
	}

	archetype_pool_remove_all(&world.archetype_pool, thing)
	thing_pool_kill_unchecked(&world.thing_pool, thing)
	return true
}

poke :: proc(world: ^World($P, $R), thing: Thing) -> bool {
	return thing_pool_poke(world.thing_pool, thing)
}

count_alive :: proc(world: ^World($P, $R)) -> int {
	return thing_pool_count_alive(world.thing_pool)
}

count_free :: proc(world: ^World($P, $R)) -> int {
	return thing_pool_count_free(world.thing_pool)
}

// >---------------------------------------------------------------- World Parts

has :: proc(world: ^World($P, $R), thing: Thing, kind: P) -> bool {
	return part_pool_has(&world.part_pool, thing, kind)
}

get_part :: proc(world: ^World($P, $R), thing: Thing, kind: P, $T: typeid) -> ^T {
	return part_pool_get(&world.part_pool, thing, kind, T)
}

get_parts :: proc(world: ^World($P, $R), kind: P, $T: typeid) -> []T {
	return part_pool_get_parts(&world.part_pool, kind, T)
}

get_things :: proc(world: ^World($P, $R), kind: P) -> []Thing {
	return part_pool_get_things(&world.part_pool, kind)
}

count_parts :: proc(world: ^World($P, $R), kind: P) -> int {
	return part_pool_count_parts(&world.part_pool, kind)
}

set_now :: proc {
	set_value_now,
	set_pointer_now,
	set_zero_now,
}

set_value_now :: proc(
	world: ^World($P, $R),
	thing: Thing,
	kind: P,
	part: $T,
) -> ^T where !intrinsics.type_is_pointer(T),
	T !=
	typeid {
	part := part

	return set_pointer_now(world, thing, kind, &part)
}

set_pointer_now :: proc(world: ^World($P, $R), thing: Thing, kind: P, part: ^$T) -> ^T {
	part_pool_assert_type(&world.part_pool, kind, T)
	return cast(^T)set_raw(world, thing, kind, part)
}

set_zero_now :: proc(world: ^World($P, $R), thing: Thing, kind: P, $T: typeid) -> ^T {
	return set_pointer_now(world, thing, kind, (^T)(nil))
}

add_now :: proc(world: ^World($P, $R), thing: Thing, kind: P) -> bool {
	return set_raw(world, thing, kind, nil) != nil
}

remove_now :: proc(world: ^World($P, $R), thing: Thing, kind: P) -> bool {
	if !part_pool_remove(&world.part_pool, thing, kind) do return false

	archetype_pool_remove(&world.archetype_pool, thing, kind)
	return true
}

// >------------------------------------------------------------ World Resources

// The resource starts zeroed.
register_resource :: proc(
	world: ^World($P, $R),
	resource: R,
	$T: typeid,
	destroy: proc(resource: rawptr) = nil,
) {
	resource_pool_register(&world.resource_pool, resource, T, destroy)
}

is_resource_registered :: proc(world: ^World($P, $R), resource: R) -> bool {
	return resource_pool_is_registered(&world.resource_pool, resource)
}

get_resource :: proc(world: ^World($P, $R), resource: R, $T: typeid) -> ^T {
	return resource_pool_get(&world.resource_pool, resource, T)
}

// >------------------------------------------------------------- World Commands

kill_later :: proc(world: ^World($P, $R), thing: Thing) {
	if thing == THING_NIL do return
	cmd_pool_record_kill(&world.cmd_pool, thing)
}

set_later :: proc {
	set_value_later,
	set_pointer_later,
	set_zero_later,
}

set_value_later :: proc(
	world: ^World($P, $R),
	thing: Thing,
	kind: P,
	part: $T,
) where !intrinsics.type_is_pointer(T),
	T !=
	typeid {
	part := part

	set_pointer_later(world, thing, kind, &part)
}

set_pointer_later :: proc(world: ^World($P, $R), thing: Thing, kind: P, part: ^$T) {
	part_pool_assert_type(&world.part_pool, kind, T)
	if thing == THING_NIL do return

	if part == nil {
		cmd_pool_record_set_zero(&world.cmd_pool, thing, kind)
	} else {
		cmd_pool_record_set_value(&world.cmd_pool, thing, kind, part, size_of(T))
	}
}

set_zero_later :: proc(world: ^World($P, $R), thing: Thing, kind: P, $T: typeid) {
	set_pointer_later(world, thing, kind, (^T)(nil))
}

add_later :: proc(world: ^World($P, $R), thing: Thing, kind: P) {
	part_pool_assert_registered(&world.part_pool, kind)
	if thing == THING_NIL do return

	cmd_pool_record_set_zero(&world.cmd_pool, thing, kind)
}

remove_later :: proc(world: ^World($P, $R), thing: Thing, kind: P) {
	part_pool_assert_registered(&world.part_pool, kind)
	if thing == THING_NIL do return

	cmd_pool_record_remove(&world.cmd_pool, thing, kind)
}

count_cmds :: proc(world: ^World($P, $R)) -> int {
	return cmd_pool_count_cmds(&world.cmd_pool)
}

apply_self :: proc(world: ^World($P, $R)) {
	apply_cmds(world, &world.cmd_pool)
	cmd_pool_reset(&world.cmd_pool)
}

apply_other :: proc(world: ^World($P, $R), cmds: ^Cmd_Pool(P)) {
	assert(cmds != &world.cmd_pool, "Use apply_self to apply the world's own buffer.")
	apply_cmds(world, cmds)
}

// >------------------------------------------------------------------ Internals

@(private = "file")
set_raw :: proc(world: ^World($P, $R), thing: Thing, kind: P, part: rawptr) -> rawptr {
	part_pool_assert_registered(&world.part_pool, kind)
	if !thing_pool_poke(world.thing_pool, thing) do return nil

	result := part_pool_set_raw(&world.part_pool, thing, kind, part)
	archetype_pool_insert(&world.archetype_pool, thing, kind)

	return result
}

@(private = "file")
apply_cmds :: proc(world: ^World($P, $R), cmds: ^Cmd_Pool(P)) {
	for cmd in cmd_pool_get_cmds(cmds) {
		switch c in cmd {
		case Cmd_Kill:
			kill_now(world, c.thing)

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
			remove_now(world, c.thing, c.kind)
		}
	}
}
