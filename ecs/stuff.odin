package ecs

import "base:intrinsics"

// >-------------------------------------------------------- Constants and Types

// What a system gets to work with. It can touch things, parts and resources, but cannot
// register kinds, apply commands or init/destroy/reset the world.
Stuff :: struct($P: typeid, $R: typeid, $S: typeid) where intrinsics.type_is_enum(P),
	intrinsics.type_is_enum(R),
	intrinsics.type_is_enum(S) {
	world: ^World(P, R, S),
}

// >---------------------------------------------------------------------- Stuff

stuff_make :: proc(world: ^World($P, $R, $S)) -> Stuff(P, R, S) {
	return Stuff(P, R, S){world = world}
}

// >--------------------------------------------------------------- Stuff Things

stuff_spawn :: proc(stuff: Stuff($P, $R, $S)) -> Thing {
	return world_spawn(stuff.world)
}

stuff_kill_now :: proc(stuff: Stuff($P, $R, $S), thing: Thing) -> bool {
	return world_kill_now(stuff.world, thing)
}

stuff_kill_later :: proc(stuff: Stuff($P, $R, $S), thing: Thing) {
	world_kill_later(stuff.world, thing)
}

stuff_is_alive :: proc(stuff: Stuff($P, $R, $S), thing: Thing) -> bool {
	return world_is_alive(stuff.world, thing)
}

stuff_count_alive :: proc(stuff: Stuff($P, $R, $S)) -> int {
	return world_count_alive(stuff.world)
}

stuff_count_free :: proc(stuff: Stuff($P, $R, $S)) -> int {
	return world_count_free(stuff.world)
}

// >---------------------------------------------------------------- Stuff Parts

stuff_has :: proc(stuff: Stuff($P, $R, $S), thing: Thing, kind: P) -> bool {
	return world_has(stuff.world, thing, kind)
}

stuff_get_part :: proc(stuff: Stuff($P, $R, $S), thing: Thing, kind: P, $T: typeid) -> ^T {
	return world_get_part(stuff.world, thing, kind, T)
}

stuff_get_parts :: proc(stuff: Stuff($P, $R, $S), kind: P, $T: typeid) -> []T {
	return world_get_parts(stuff.world, kind, T)
}

stuff_get_things :: proc(stuff: Stuff($P, $R, $S), kind: P) -> []Thing {
	return world_get_things(stuff.world, kind)
}

stuff_count_parts :: proc(stuff: Stuff($P, $R, $S), kind: P) -> int {
	return world_count_parts(stuff.world, kind)
}

stuff_set_value_now :: proc(
	stuff: Stuff($P, $R, $S),
	thing: Thing,
	kind: P,
	part: $T,
) -> ^T where !intrinsics.type_is_pointer(T),
	T !=
	typeid {
	return world_set_value_now(stuff.world, thing, kind, part)
}

stuff_set_pointer_now :: proc(stuff: Stuff($P, $R, $S), thing: Thing, kind: P, part: ^$T) -> ^T {
	return world_set_pointer_now(stuff.world, thing, kind, part)
}

stuff_set_zero_now :: proc(stuff: Stuff($P, $R, $S), thing: Thing, kind: P, $T: typeid) -> ^T {
	return world_set_zero_now(stuff.world, thing, kind, T)
}

stuff_add_now :: proc(stuff: Stuff($P, $R, $S), thing: Thing, kind: P) -> bool {
	return world_add_now(stuff.world, thing, kind)
}

stuff_remove_now :: proc(stuff: Stuff($P, $R, $S), thing: Thing, kind: P) -> bool {
	return world_remove_now(stuff.world, thing, kind)
}

stuff_set_value_later :: proc(
	stuff: Stuff($P, $R, $S),
	thing: Thing,
	kind: P,
	part: $T,
) where !intrinsics.type_is_pointer(T),
	T !=
	typeid {
	world_set_value_later(stuff.world, thing, kind, part)
}

stuff_set_pointer_later :: proc(stuff: Stuff($P, $R, $S), thing: Thing, kind: P, part: ^$T) {
	world_set_pointer_later(stuff.world, thing, kind, part)
}

stuff_set_zero_later :: proc(stuff: Stuff($P, $R, $S), thing: Thing, kind: P, $T: typeid) {
	world_set_zero_later(stuff.world, thing, kind, T)
}

stuff_add_later :: proc(stuff: Stuff($P, $R, $S), thing: Thing, kind: P) {
	world_add_later(stuff.world, thing, kind)
}

stuff_remove_later :: proc(stuff: Stuff($P, $R, $S), thing: Thing, kind: P) {
	world_remove_later(stuff.world, thing, kind)
}

// >------------------------------------------------------------ Stuff Resources

stuff_get_resource :: proc(stuff: Stuff($P, $R, $S), resource: R, $T: typeid) -> ^T {
	return world_get_resource(stuff.world, resource, T)
}
