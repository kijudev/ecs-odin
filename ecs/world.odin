package ecs

import "base:intrinsics"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

World :: struct($P: typeid) where intrinsics.type_is_enum(P) {
	thing_pool:     Thing_Pool,
	part_pool:      [P]Part_Pool,
	archetype_pool: Archetype_Pool(P),
	part_types:     [P]typeid,
	registered:     bit_set[P],
	pool_allocator: mem.Allocator,
}

// >---------------------------------------------------------------- World Setup

world_init :: proc(
	world: ^World($P),
	capacity := THING_POOL_DEFAULT_CAPACITY,
	pool_allocator := context.allocator,
) {
	thing_pool_init(&world.thing_pool, capacity, pool_allocator)
	archetype_pool_init(&world.archetype_pool, capacity, pool_allocator)
	world.part_types = {}
	world.registered = {}
	world.pool_allocator = pool_allocator
}

world_destroy :: proc(world: ^World($P)) {
	thing_pool_destroy(&world.thing_pool)
	archetype_pool_destroy(&world.archetype_pool)

	for kind in world.registered {
		part_pool_destroy(&world.part_pool[kind])
	}

	world^ = World(P){}
}

world_reset :: proc(world: ^World($P)) {
	thing_pool_reset(&world.thing_pool)
	archetype_pool_reset(&world.archetype_pool)

	for kind in world.registered {
		part_pool_reset(&world.part_pool[kind])
	}
}

world_register_part :: proc(
	world: ^World($P),
	kind: P,
	$T: typeid,
	destroy: proc(part: rawptr) = nil,
) {
	assert(kind not_in world.registered, "Part kind is already registered in the world.")

	world.part_types[kind] = T
	world.registered += {kind}

	part_pool_init(&world.part_pool[kind], type_info_of(T), destroy, world.pool_allocator)
}

world_is_registered :: proc(world: ^World($P), kind: P) -> bool {
	return kind in world.registered
}

// >--------------------------------------------------------------- World Things

world_spawn :: proc(world: ^World($P)) -> Thing {
	return thing_pool_spawn(&world.thing_pool)
}

world_kill :: proc(world: ^World($P), thing: Thing) -> bool {
	if !thing_pool_check(world.thing_pool, thing) do return false

	for kind in archetype_pool_get_mask(world.archetype_pool, thing) {
		part_pool_remove_unchecked(&world.part_pool[kind], thing)
	}

	archetype_pool_remove_all(&world.archetype_pool, thing)
	thing_pool_kill_unchecked(&world.thing_pool, thing)
	return true
}

world_check :: proc(world: ^World($P), thing: Thing) -> bool {
	return thing_pool_check(world.thing_pool, thing)
}

world_count_alive :: proc(world: ^World($P)) -> int {
	return thing_pool_count_alive(world.thing_pool)
}

world_count_free :: proc(world: ^World($P)) -> int {
	return thing_pool_count_free(world.thing_pool)
}

world_capacity :: proc(world: ^World($P)) -> int {
	return thing_pool_capacity(world.thing_pool)
}

// >---------------------------------------------------------------- World Parts

world_has :: proc(world: ^World($P), thing: Thing, kind: P) -> bool {
	assert(kind in world.registered, "Part kind is not registered in the world.")
	return part_pool_has(&world.part_pool[kind], thing)
}

world_get :: proc(world: ^World($P), thing: Thing, kind: P, $T: typeid) -> ^T {
	assert(kind in world.registered, "Part kind is not registered in the world.")
	assert(world.part_types[kind] == T, "Part kind does not match the provided type.")

	raw := part_pool_get(&world.part_pool[kind], thing)
	return cast(^T)raw
}

world_set_now :: proc {
	world_set_value_now,
	world_set_pointer_now,
	world_set_zero_now,
}

world_set_value_now :: proc(
	world: ^World($P),
	thing: Thing,
	kind: P,
	part: $T,
) -> ^T where !intrinsics.type_is_pointer(T),
	T !=
	typeid {
	part := part
	return world_set_pointer_now(world, thing, kind, &part)
}

world_set_pointer_now :: proc(world: ^World($P), thing: Thing, kind: P, part: ^$T) -> ^T {
	assert(world.part_types[kind] == T, "Part kind does not match the provided type.")
	return cast(^T)set_raw(world, thing, kind, part)
}

world_set_zero_now :: proc(world: ^World($P), thing: Thing, kind: P, $T: typeid) -> ^T {
	return world_set_pointer_now(world, thing, kind, (^T)(nil))
}

world_add_now :: proc(world: ^World($P), thing: Thing, kind: P) -> bool {
	return set_raw(world, thing, kind, nil) != nil
}

world_remove_now :: proc(world: ^World($P), thing: Thing, kind: P) -> bool {
	assert(kind in world.registered, "Part kind is not registered in the world.")

	if !part_pool_remove(&world.part_pool[kind], thing) do return false

	archetype_pool_remove(&world.archetype_pool, thing, kind)
	return true
}

world_count :: proc(world: ^World($P), kind: P) -> int {
	assert(kind in world.registered, "Part kind is not registered in the world.")
	return part_pool_count(&world.part_pool[kind])
}

world_part_slice :: proc(world: ^World($P), kind: P, $T: typeid) -> []T {
	assert(kind in world.registered, "Part kind is not registered in the world.")
	assert(world.part_types[kind] == T, "Part kind does not match the provided type.")

	pool := &world.part_pool[kind]
	return ([^]T)(raw_data(pool.parts_data))[:part_pool_count(pool)]
}

world_thing_slice :: proc(world: ^World($P), kind: P) -> []Thing {
	assert(kind in world.registered, "Part kind is not registered in the world.")
	return part_pool_thing_slice(&world.part_pool[kind])
}

// >------------------------------------------------------------------ Internals

@(private = "file")
set_raw :: proc(world: ^World($P), thing: Thing, kind: P, part: rawptr) -> rawptr {
	assert(kind in world.registered, "Part kind is not registered in the world.")
	if !thing_pool_check(world.thing_pool, thing) do return nil

	result := part_pool_insert(&world.part_pool[kind], thing, part)
	archetype_pool_insert(&world.archetype_pool, thing, kind)

	return result
}
