package ecs

import "base:intrinsics"

// >-------------------------------------------------------- Constants and Types

/*
What a system gets to work with. It can touch things, parts and stashes, but cannot register
kinds, apply commands or init/destroy/reset the world.
*/
Stuff :: struct($K: typeid, $S: typeid) where intrinsics.type_is_enum(K),
	intrinsics.type_is_enum(S) {
	world: ^World(K, S),
}

// >---------------------------------------------------------------------- Stuff

/* Makes a stuff for the world. Systems get one from the world when they run. */
stuff_make :: proc(world: ^World($K, $S)) -> Stuff(K, S) {
	return Stuff(K, S){world = world}
}

// >--------------------------------------------------------------- Stuff Things

/* See spawn. */
stuff_spawn :: proc(stuff: Stuff($K, $S)) -> Thing {
	return world_spawn(stuff.world)
}

/* See kill_now. */
stuff_kill_now :: proc(stuff: Stuff($K, $S), thing: Thing) -> bool {
	return world_kill_now(stuff.world, thing)
}

/* See kill_later. */
stuff_kill_later :: proc(stuff: Stuff($K, $S), thing: Thing) {
	world_kill_later(stuff.world, thing)
}

/* See kill_tree_now. */
stuff_kill_tree_now :: proc(stuff: Stuff($K, $S), kind: K, thing: Thing) -> bool {
	return world_kill_tree_now(stuff.world, kind, thing)
}

/* See kill_tree_later. */
stuff_kill_tree_later :: proc(stuff: Stuff($K, $S), kind: K, thing: Thing) {
	world_kill_tree_later(stuff.world, kind, thing)
}

/* See is_alive. */
stuff_is_alive :: proc(stuff: Stuff($K, $S), thing: Thing) -> bool {
	return world_is_alive(stuff.world, thing)
}

/* See count_alive. */
stuff_count_alive :: proc(stuff: Stuff($K, $S)) -> int {
	return world_count_alive(stuff.world)
}

/* See count_free. */
stuff_count_free :: proc(stuff: Stuff($K, $S)) -> int {
	return world_count_free(stuff.world)
}

// >---------------------------------------------------------------- Stuff Parts

/* See has. */
stuff_has :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K) -> bool {
	return world_has(stuff.world, thing, kind)
}

/* See get_part. */
stuff_get_part :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K, $T: typeid) -> ^T {
	return world_get_part(stuff.world, thing, kind, T)
}

/* See get_parts. */
stuff_get_parts :: proc(stuff: Stuff($K, $S), kind: K, $T: typeid) -> []T {
	return world_get_parts(stuff.world, kind, T)
}

/* See get_things. */
stuff_get_things :: proc(stuff: Stuff($K, $S), kind: K) -> []Thing {
	return world_get_things(stuff.world, kind)
}

/* See count_parts. */
stuff_count_parts :: proc(stuff: Stuff($K, $S), kind: K) -> int {
	return world_count_parts(stuff.world, kind)
}

/* See set_now. */
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

/* See set_now. */
stuff_set_pointer_now :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K, part: ^$T) -> ^T {
	return world_set_pointer_now(stuff.world, thing, kind, part)
}

/* See set_now. */
stuff_set_zero_now :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K, $T: typeid) -> ^T {
	return world_set_zero_now(stuff.world, thing, kind, T)
}

/* See add_now. */
stuff_add_now :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K) -> bool {
	return world_add_now(stuff.world, thing, kind)
}

/* See remove_now. */
stuff_remove_now :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K) -> bool {
	return world_remove_now(stuff.world, thing, kind)
}

/* See set_later. */
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

/* See set_later. */
stuff_set_pointer_later :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K, part: ^$T) {
	world_set_pointer_later(stuff.world, thing, kind, part)
}

/* See set_later. */
stuff_set_zero_later :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K, $T: typeid) {
	world_set_zero_later(stuff.world, thing, kind, T)
}

/* See add_later. */
stuff_add_later :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K) {
	world_add_later(stuff.world, thing, kind)
}

/* See remove_later. */
stuff_remove_later :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K) {
	world_remove_later(stuff.world, thing, kind)
}

// >------------------------------------------------------------ Stuff Hierarchy

/* See attach_now. */
stuff_attach_now :: proc(stuff: Stuff($K, $S), kind: K, child, parent: Thing) -> bool {
	return world_attach_now(stuff.world, kind, child, parent)
}

/* See attach_later. */
stuff_attach_later :: proc(stuff: Stuff($K, $S), kind: K, child, parent: Thing) {
	world_attach_later(stuff.world, kind, child, parent)
}

/* See detach_now. */
stuff_detach_now :: proc(stuff: Stuff($K, $S), kind: K, child: Thing) -> bool {
	return world_detach_now(stuff.world, kind, child)
}

/* See detach_later. */
stuff_detach_later :: proc(stuff: Stuff($K, $S), kind: K, child: Thing) {
	world_detach_later(stuff.world, kind, child)
}

/* See get_parent. */
stuff_get_parent :: proc(stuff: Stuff($K, $S), kind: K, child: Thing) -> Thing {
	return world_get_parent(stuff.world, kind, child)
}

/* See get_first_child. */
stuff_get_first_child :: proc(stuff: Stuff($K, $S), kind: K, parent: Thing) -> Thing {
	return world_get_first_child(stuff.world, kind, parent)
}

/* See get_next_sibling. */
stuff_get_next_sibling :: proc(stuff: Stuff($K, $S), kind: K, child: Thing) -> Thing {
	return world_get_next_sibling(stuff.world, kind, child)
}

/* See iter_children. */
stuff_iter_children :: proc(
	stuff: Stuff($K, $S),
	kind: K,
	parent: Thing,
) -> Hierarchy_Children_Iter {
	return world_iter_children(stuff.world, kind, parent)
}

/* See iter_roots. */
stuff_iter_roots :: proc(stuff: Stuff($K, $S), kind: K) -> Hierarchy_Children_Iter {
	return world_iter_roots(stuff.world, kind)
}

/* See is_ancestor. */
stuff_is_ancestor :: proc(stuff: Stuff($K, $S), kind: K, ancestor, thing: Thing) -> bool {
	return world_is_ancestor(stuff.world, kind, ancestor, thing)
}

/* See get_hierarchy_order. */
stuff_get_hierarchy_order :: proc(stuff: Stuff($K, $S), kind: K) -> []Thing {
	return world_get_hierarchy_order(stuff.world, kind)
}

/* See get_hierarchy_depths. */
stuff_get_hierarchy_depths :: proc(stuff: Stuff($K, $S), kind: K) -> []Hierarchy_Depth {
	return world_get_hierarchy_depths(stuff.world, kind)
}

/* See get_hierarchy_ends. */
stuff_get_hierarchy_ends :: proc(stuff: Stuff($K, $S), kind: K) -> []Hierarchy_Pos {
	return world_get_hierarchy_ends(stuff.world, kind)
}

/* See get_subtree. */
stuff_get_subtree :: proc(stuff: Stuff($K, $S), kind: K, thing: Thing) -> []Thing {
	return world_get_subtree(stuff.world, kind, thing)
}

// >-------------------------------------------------------------- Stuff Stashes

/* See get_stash. */
stuff_get_stash :: proc(stuff: Stuff($K, $S), kind: K, $T: typeid) -> ^T {
	return world_get_stash(stuff.world, kind, T)
}
