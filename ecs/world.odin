package ecs

import "base:intrinsics"
import "core:mem"


// >-------------------------------------------------------- Constants and Types

World :: struct($P: typeid) where intrinsics.type_is_enum(P) {
	thing_pool:      Thing_Pool,
	archetype_pool:  Archetype_Pool(P),
	cmd_pool:        Cmd_Pool(P),
	part_pools:      [P]Part_Pool,
	part_types:      [P]typeid,
	part_registered: bit_set[P],
	pool_allocator:  mem.Allocator,
}

// >---------------------------------------------------------------- World Setup

world_init :: proc(
	world: ^World($P),
	capacity := THING_POOL_DEFAULT_CAPACITY,
	pool_allocator := context.allocator,
) {
	thing_pool_init(&world.thing_pool, capacity, pool_allocator)
	archetype_pool_init(&world.archetype_pool, capacity, pool_allocator)
	cmd_pool_init(&world.cmd_pool, allocator = pool_allocator)
	world.part_types = {}
	world.part_registered = {}
	world.pool_allocator = pool_allocator
}

world_destroy :: proc(world: ^World($P)) {
	thing_pool_destroy(&world.thing_pool)
	archetype_pool_destroy(&world.archetype_pool)
	cmd_pool_destroy(&world.cmd_pool)

	for kind in world.part_registered {
		part_pool_destroy(&world.part_pools[kind])
	}

	world^ = World(P){}
}

// Also drops the commands recorded with the `_later` procs without applying them.
world_reset :: proc(world: ^World($P)) {
	thing_pool_reset(&world.thing_pool)
	archetype_pool_reset(&world.archetype_pool)
	cmd_pool_reset(&world.cmd_pool)

	for kind in world.part_registered {
		part_pool_reset(&world.part_pools[kind])
	}
}

register :: proc(world: ^World($P), kind: P, $T: typeid, destroy: proc(part: rawptr) = nil) {
	assert(kind not_in world.part_registered, "Part kind is already registered in the world.")

	world.part_types[kind] = T
	world.part_registered += {kind}

	part_pool_init(&world.part_pools[kind], type_info_of(T), destroy, world.pool_allocator)
}

is_registered :: proc(world: ^World($P), kind: P) -> bool {
	return kind in world.part_registered
}

// >--------------------------------------------------------------- World Things

spawn :: proc(world: ^World($P)) -> Thing {
	return thing_pool_spawn(&world.thing_pool)
}

kill_now :: proc(world: ^World($P), thing: Thing) -> bool {
	if !thing_pool_poke(world.thing_pool, thing) do return false

	for kind in archetype_pool_get_mask(world.archetype_pool, thing) {
		part_pool_remove_unchecked(&world.part_pools[kind], thing)
	}

	archetype_pool_remove_all(&world.archetype_pool, thing)
	thing_pool_kill_unchecked(&world.thing_pool, thing)
	return true
}

poke :: proc(world: ^World($P), thing: Thing) -> bool {
	return thing_pool_poke(world.thing_pool, thing)
}

count_alive :: proc(world: ^World($P)) -> int {
	return thing_pool_count_alive(world.thing_pool)
}

count_free :: proc(world: ^World($P)) -> int {
	return thing_pool_count_free(world.thing_pool)
}

// >---------------------------------------------------------------- World Parts

has :: proc(world: ^World($P), thing: Thing, kind: P) -> bool {
	assert(kind in world.part_registered, "Part kind is not registered in the world.")
	return part_pool_has(&world.part_pools[kind], thing)
}

get_part :: proc(world: ^World($P), thing: Thing, kind: P, $T: typeid) -> ^T {
	assert(kind in world.part_registered, "Part kind is not registered in the world.")
	assert(world.part_types[kind] == T, "Part kind does not match the provided type.")

	raw := part_pool_get_part(&world.part_pools[kind], thing)
	return cast(^T)raw
}

get_parts :: proc(world: ^World($P), kind: P, $T: typeid) -> []T {
	assert(kind in world.part_registered, "Part kind is not registered in the world.")
	assert(world.part_types[kind] == T, "Part kind does not match the provided type.")

	pool := &world.part_pools[kind]
	return ([^]T)(raw_data(pool.parts_data))[:part_pool_count_parts(pool)]
}

get_things :: proc(world: ^World($P), kind: P) -> []Thing {
	assert(kind in world.part_registered, "Part kind is not registered in the world.")
	return part_pool_get_things(&world.part_pools[kind])
}

count_parts :: proc(world: ^World($P), kind: P) -> int {
	assert(kind in world.part_registered, "Part kind is not registered in the world.")
	return part_pool_count_parts(&world.part_pools[kind])
}

set_now :: proc {
	set_value_now,
	set_pointer_now,
	set_zero_now,
}

set_value_now :: proc(
	world: ^World($P),
	thing: Thing,
	kind: P,
	part: $T,
) -> ^T where !intrinsics.type_is_pointer(T),
	T !=
	typeid {
	part := part

	return set_pointer_now(world, thing, kind, &part)
}

set_pointer_now :: proc(world: ^World($P), thing: Thing, kind: P, part: ^$T) -> ^T {
	assert(world.part_types[kind] == T, "Part kind does not match the provided type.")
	return cast(^T)set_raw(world, thing, kind, part)
}

set_zero_now :: proc(world: ^World($P), thing: Thing, kind: P, $T: typeid) -> ^T {
	return set_pointer_now(world, thing, kind, (^T)(nil))
}

add_now :: proc(world: ^World($P), thing: Thing, kind: P) -> bool {
	return set_raw(world, thing, kind, nil) != nil
}

remove_now :: proc(world: ^World($P), thing: Thing, kind: P) -> bool {
	assert(kind in world.part_registered, "Part kind is not registered in the world.")

	if !part_pool_remove(&world.part_pools[kind], thing) do return false

	archetype_pool_remove(&world.archetype_pool, thing, kind)
	return true
}

// >------------------------------------------------------------- World Commands

kill_later :: proc(world: ^World($P), thing: Thing) {
	if thing == THING_NIL do return
	cmd_pool_record_kill(&world.cmd_pool, thing)
}

set_later :: proc {
	set_value_later,
	set_pointer_later,
	set_zero_later,
}

set_value_later :: proc(
	world: ^World($P),
	thing: Thing,
	kind: P,
	part: $T,
) where !intrinsics.type_is_pointer(T),
	T !=
	typeid {
	part := part

	set_pointer_later(world, thing, kind, &part)
}

set_pointer_later :: proc(world: ^World($P), thing: Thing, kind: P, part: ^$T) {
	assert(kind in world.part_registered, "Part kind is not registered in the world.")
	assert(world.part_types[kind] == T, "Part kind does not match the provided type.")
	if thing == THING_NIL do return

	if part == nil {
		cmd_pool_record_set_zero(&world.cmd_pool, thing, kind)
	} else {
		cmd_pool_record_set_value(&world.cmd_pool, thing, kind, part, size_of(T))
	}
}

set_zero_later :: proc(world: ^World($P), thing: Thing, kind: P, $T: typeid) {
	set_pointer_later(world, thing, kind, (^T)(nil))
}

add_later :: proc(world: ^World($P), thing: Thing, kind: P) {
	assert(kind in world.part_registered, "Part kind is not registered in the world.")
	if thing == THING_NIL do return

	cmd_pool_record_set_zero(&world.cmd_pool, thing, kind)
}

remove_later :: proc(world: ^World($P), thing: Thing, kind: P) {
	assert(kind in world.part_registered, "Part kind is not registered in the world.")
	if thing == THING_NIL do return

	cmd_pool_record_remove(&world.cmd_pool, thing, kind)
}

count_cmds :: proc(world: ^World($P)) -> int {
	return cmd_pool_count_cmds(&world.cmd_pool)
}

apply_self :: proc(world: ^World($P)) {
	apply_cmds(world, &world.cmd_pool)
	cmd_pool_reset(&world.cmd_pool)
}

apply_other :: proc(world: ^World($P), cmds: ^Cmd_Pool(P)) {
	assert(cmds != &world.cmd_pool, "Use apply_self to apply the world's own buffer.")
	apply_cmds(world, cmds)
}

// >------------------------------------------------------------------ Internals

@(private = "file")
set_raw :: proc(world: ^World($P), thing: Thing, kind: P, part: rawptr) -> rawptr {
	assert(kind in world.part_registered, "Part kind is not registered in the world.")
	if !thing_pool_poke(world.thing_pool, thing) do return nil

	result := part_pool_insert(&world.part_pools[kind], thing, part)
	archetype_pool_insert(&world.archetype_pool, thing, kind)

	return result
}

@(private = "file")
apply_cmds :: proc(world: ^World($P), cmds: ^Cmd_Pool(P)) {
	for cmd in cmd_pool_get_cmds(cmds) {
		switch c in cmd {
		case Cmd_Kill:
			kill_now(world, c.thing)

		case Cmd_Set_Value(P):
			assert(c.kind in world.part_registered, "Part kind is not registered in the world.")
			assert(
				int(c.size) == world.part_pools[c.kind].part_size,
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
