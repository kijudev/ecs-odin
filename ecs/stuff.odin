package ecs

import "base:intrinsics"

// >-------------------------------------------------------- Constants and Types

// What a system gets to work with. It can touch things, parts and stashes, but cannot
// register kinds, apply commands or init/destroy/reset the world.
Stuff :: struct($K: typeid, $S: typeid) where intrinsics.type_is_enum(K),
	intrinsics.type_is_enum(S) {
	world: ^World(K, S),
}

// >---------------------------------------------------------------------- Stuff

stuff_make :: proc(world: ^World($K, $S)) -> Stuff(K, S) {
	return Stuff(K, S){world = world}
}

// >--------------------------------------------------------------- Stuff Things

stuff_spawn :: proc(stuff: Stuff($K, $S)) -> Thing {
	return world_spawn(stuff.world)
}

stuff_kill_now :: proc(stuff: Stuff($K, $S), thing: Thing) -> bool {
	return world_kill_now(stuff.world, thing)
}

stuff_kill_later :: proc(stuff: Stuff($K, $S), thing: Thing) {
	world_kill_later(stuff.world, thing)
}

stuff_is_alive :: proc(stuff: Stuff($K, $S), thing: Thing) -> bool {
	return world_is_alive(stuff.world, thing)
}

stuff_count_alive :: proc(stuff: Stuff($K, $S)) -> int {
	return world_count_alive(stuff.world)
}

stuff_count_free :: proc(stuff: Stuff($K, $S)) -> int {
	return world_count_free(stuff.world)
}

// >---------------------------------------------------------------- Stuff Parts

stuff_has :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K) -> bool {
	return world_has(stuff.world, thing, kind)
}

stuff_get_part :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K, $T: typeid) -> ^T {
	return world_get_part(stuff.world, thing, kind, T)
}

stuff_get_parts :: proc(stuff: Stuff($K, $S), kind: K, $T: typeid) -> []T {
	return world_get_parts(stuff.world, kind, T)
}

stuff_get_things :: proc(stuff: Stuff($K, $S), kind: K) -> []Thing {
	return world_get_things(stuff.world, kind)
}

stuff_count_parts :: proc(stuff: Stuff($K, $S), kind: K) -> int {
	return world_count_parts(stuff.world, kind)
}

stuff_set_value_now :: proc(
	stuff: Stuff($K, $S),
	thing: Thing,
	kind: K,
	part: $T,
) -> ^T where !intrinsics.type_is_pointer(T),
	T !=
	typeid {
	return world_set_value_now(stuff.world, thing, kind, part)
}

stuff_set_pointer_now :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K, part: ^$T) -> ^T {
	return world_set_pointer_now(stuff.world, thing, kind, part)
}

stuff_set_zero_now :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K, $T: typeid) -> ^T {
	return world_set_zero_now(stuff.world, thing, kind, T)
}

stuff_add_now :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K) -> bool {
	return world_add_now(stuff.world, thing, kind)
}

stuff_remove_now :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K) -> bool {
	return world_remove_now(stuff.world, thing, kind)
}

stuff_set_value_later :: proc(
	stuff: Stuff($K, $S),
	thing: Thing,
	kind: K,
	part: $T,
) where !intrinsics.type_is_pointer(T),
	T !=
	typeid {
	world_set_value_later(stuff.world, thing, kind, part)
}

stuff_set_pointer_later :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K, part: ^$T) {
	world_set_pointer_later(stuff.world, thing, kind, part)
}

stuff_set_zero_later :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K, $T: typeid) {
	world_set_zero_later(stuff.world, thing, kind, T)
}

stuff_add_later :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K) {
	world_add_later(stuff.world, thing, kind)
}

stuff_remove_later :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K) {
	world_remove_later(stuff.world, thing, kind)
}

// >-------------------------------------------------------------- Stuff Stashes

stuff_get_stash :: proc(stuff: Stuff($K, $S), kind: K, $T: typeid) -> ^T {
	return world_get_stash(stuff.world, kind, T)
}
