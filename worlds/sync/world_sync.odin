package world_sync

import "base:intrinsics"
import "core:mem"

import ecs "../../ecs"

// >-------------------------------------------------------- Constants and Types

World :: struct($P: typeid) where intrinsics.type_is_enum(P) {
	thing_pool:     ecs.Thing_Pool,
	part_pool:      [P]ecs.Part_Pool,
	archetype_pool: ecs.Archetype_Pool(P),
	cmd_pool:       ecs.Cmd_Pool(P),
	part_types:     [P]typeid,
	registered:     bit_set[P],
	pool_allocator: mem.Allocator,
}

// >---------------------------------------------------------------- World Setup

init :: proc(
	world: ^World($P),
	capacity := ecs.THING_POOL_DEFAULT_CAPACITY,
	pool_allocator := context.allocator,
) {
	ecs.thing_pool_init(&world.thing_pool, capacity, pool_allocator)
	ecs.archetype_pool_init(&world.archetype_pool, capacity, pool_allocator)
	ecs.cmd_pool_init(&world.cmd_pool, allocator = pool_allocator)
	world.part_types = {}
	world.registered = {}
	world.pool_allocator = pool_allocator
}

destroy :: proc(world: ^World($P)) {
	ecs.thing_pool_destroy(&world.thing_pool)
	ecs.archetype_pool_destroy(&world.archetype_pool)
	ecs.cmd_pool_destroy(&world.cmd_pool)

	for kind in world.registered {
		ecs.part_pool_destroy(&world.part_pool[kind])
	}

	world^ = World(P){}
}

// Also drops the commands recorded with the `_later` procs without applying them.
reset :: proc(world: ^World($P)) {
	ecs.thing_pool_reset(&world.thing_pool)
	ecs.archetype_pool_reset(&world.archetype_pool)
	ecs.cmd_pool_reset(&world.cmd_pool)

	for kind in world.registered {
		ecs.part_pool_reset(&world.part_pool[kind])
	}
}

register :: proc(world: ^World($P), kind: P, $T: typeid, destroy: proc(part: rawptr) = nil) {
	assert(kind not_in world.registered, "Part kind is already registered in the world.")

	world.part_types[kind] = T
	world.registered += {kind}

	ecs.part_pool_init(&world.part_pool[kind], type_info_of(T), destroy, world.pool_allocator)
}

is_registered :: proc(world: ^World($P), kind: P) -> bool {
	return kind in world.registered
}

// >--------------------------------------------------------------- World Things

spawn :: proc(world: ^World($P)) -> ecs.Thing {
	return ecs.thing_pool_spawn(&world.thing_pool)
}

kill_now :: proc(world: ^World($P), thing: ecs.Thing) -> bool {
	if !ecs.thing_pool_poke(world.thing_pool, thing) do return false

	for kind in ecs.archetype_pool_get_mask(world.archetype_pool, thing) {
		ecs.part_pool_remove_unchecked(&world.part_pool[kind], thing)
	}

	ecs.archetype_pool_remove_all(&world.archetype_pool, thing)
	ecs.thing_pool_kill_unchecked(&world.thing_pool, thing)
	return true
}

poke :: proc(world: ^World($P), thing: ecs.Thing) -> bool {
	return ecs.thing_pool_poke(world.thing_pool, thing)
}

count_alive :: proc(world: ^World($P)) -> int {
	return ecs.thing_pool_count_alive(world.thing_pool)
}

count_free :: proc(world: ^World($P)) -> int {
	return ecs.thing_pool_count_free(world.thing_pool)
}

// >---------------------------------------------------------------- World Parts

has :: proc(world: ^World($P), thing: ecs.Thing, kind: P) -> bool {
	assert(kind in world.registered, "Part kind is not registered in the world.")
	return ecs.part_pool_has(&world.part_pool[kind], thing)
}

get_part :: proc(world: ^World($P), thing: ecs.Thing, kind: P, $T: typeid) -> ^T {
	assert(kind in world.registered, "Part kind is not registered in the world.")
	assert(world.part_types[kind] == T, "Part kind does not match the provided type.")

	raw := ecs.part_pool_get_part(&world.part_pool[kind], thing)
	return cast(^T)raw
}

get_parts :: proc(world: ^World($P), kind: P, $T: typeid) -> []T {
	assert(kind in world.registered, "Part kind is not registered in the world.")
	assert(world.part_types[kind] == T, "Part kind does not match the provided type.")

	pool := &world.part_pool[kind]
	return ([^]T)(raw_data(pool.parts_data))[:ecs.part_pool_count_parts(pool)]
}

get_things :: proc(world: ^World($P), kind: P) -> []ecs.Thing {
	assert(kind in world.registered, "Part kind is not registered in the world.")
	return ecs.part_pool_get_things(&world.part_pool[kind])
}

count_parts :: proc(world: ^World($P), kind: P) -> int {
	assert(kind in world.registered, "Part kind is not registered in the world.")
	return ecs.part_pool_count_parts(&world.part_pool[kind])
}

set_now :: proc {
	set_value_now,
	set_pointer_now,
	set_zero_now,
}

set_value_now :: proc(
	world: ^World($P),
	thing: ecs.Thing,
	kind: P,
	part: $T,
) -> ^T where !intrinsics.type_is_pointer(T),
	T !=
	typeid {
	part := part

	return set_pointer_now(world, thing, kind, &part)
}

set_pointer_now :: proc(world: ^World($P), thing: ecs.Thing, kind: P, part: ^$T) -> ^T {
	assert(world.part_types[kind] == T, "Part kind does not match the provided type.")
	return cast(^T)set_raw(world, thing, kind, part)
}

set_zero_now :: proc(world: ^World($P), thing: ecs.Thing, kind: P, $T: typeid) -> ^T {
	return set_pointer_now(world, thing, kind, (^T)(nil))
}

add_now :: proc(world: ^World($P), thing: ecs.Thing, kind: P) -> bool {
	return set_raw(world, thing, kind, nil) != nil
}

remove_now :: proc(world: ^World($P), thing: ecs.Thing, kind: P) -> bool {
	assert(kind in world.registered, "Part kind is not registered in the world.")

	if !ecs.part_pool_remove(&world.part_pool[kind], thing) do return false

	ecs.archetype_pool_remove(&world.archetype_pool, thing, kind)
	return true
}

// >------------------------------------------------------------- World Commands

kill_later :: proc(world: ^World($P), thing: ecs.Thing) {
	if thing == ecs.THING_NIL do return
	ecs.cmd_pool_record_kill(&world.cmd_pool, thing)
}

set_later :: proc {
	set_value_later,
	set_pointer_later,
	set_zero_later,
}

set_value_later :: proc(
	world: ^World($P),
	thing: ecs.Thing,
	kind: P,
	part: $T,
) where !intrinsics.type_is_pointer(T),
	T !=
	typeid {
	part := part

	set_pointer_later(world, thing, kind, &part)
}

set_pointer_later :: proc(world: ^World($P), thing: ecs.Thing, kind: P, part: ^$T) {
	assert(kind in world.registered, "Part kind is not registered in the world.")
	assert(world.part_types[kind] == T, "Part kind does not match the provided type.")
	if thing == ecs.THING_NIL do return

	if part == nil {
		ecs.cmd_pool_record_set_zero(&world.cmd_pool, thing, kind)
	} else {
		ecs.cmd_pool_record_set_value(&world.cmd_pool, thing, kind, part, size_of(T))
	}
}

set_zero_later :: proc(world: ^World($P), thing: ecs.Thing, kind: P, $T: typeid) {
	set_pointer_later(world, thing, kind, (^T)(nil))
}

add_later :: proc(world: ^World($P), thing: ecs.Thing, kind: P) {
	assert(kind in world.registered, "Part kind is not registered in the world.")
	if thing == ecs.THING_NIL do return

	ecs.cmd_pool_record_set_zero(&world.cmd_pool, thing, kind)
}

remove_later :: proc(world: ^World($P), thing: ecs.Thing, kind: P) {
	assert(kind in world.registered, "Part kind is not registered in the world.")
	if thing == ecs.THING_NIL do return

	ecs.cmd_pool_record_remove(&world.cmd_pool, thing, kind)
}

count_cmds :: proc(world: ^World($P)) -> int {
	return ecs.cmd_pool_count_cmds(&world.cmd_pool)
}

apply_self :: proc(world: ^World($P)) {
	apply_cmds(world, &world.cmd_pool)
	ecs.cmd_pool_reset(&world.cmd_pool)
}

apply_other :: proc(world: ^World($P), cmds: ^ecs.Cmd_Pool(P)) {
	assert(cmds != &world.cmd_pool, "Use apply_self to apply the world's own buffer.")
	apply_cmds(world, cmds)
}

// >------------------------------------------------------------------ Internals

@(private = "file")
set_raw :: proc(world: ^World($P), thing: ecs.Thing, kind: P, part: rawptr) -> rawptr {
	assert(kind in world.registered, "Part kind is not registered in the world.")
	if !ecs.thing_pool_poke(world.thing_pool, thing) do return nil

	result := ecs.part_pool_insert(&world.part_pool[kind], thing, part)
	ecs.archetype_pool_insert(&world.archetype_pool, thing, kind)

	return result
}

@(private = "file")
apply_cmds :: proc(world: ^World($P), cmds: ^ecs.Cmd_Pool(P)) {
	for cmd in ecs.cmd_pool_get_cmds(cmds) {
		switch c in cmd {
		case ecs.Cmd_Kill:
			kill_now(world, c.thing)

		case ecs.Cmd_Set_Value(P):
			assert(c.kind in world.registered, "Part kind is not registered in the world.")
			assert(
				int(c.size) == world.part_pool[c.kind].part_size,
				"Command part size does not match the registered part type.",
			)

			bytes := ecs.cmd_pool_get_bytes(cmds, c.offset, c.size)
			set_raw(world, c.thing, c.kind, raw_data(bytes))

		case ecs.Cmd_Set_Zero(P):
			set_raw(world, c.thing, c.kind, nil)

		case ecs.Cmd_Remove(P):
			remove_now(world, c.thing, c.kind)
		}
	}
}
