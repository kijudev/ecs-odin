package ecs

import "base:intrinsics"
import "core:fmt"

// >-------------------------------------------------------- Constants and Types

/*
What a system gets to work with. It can touch things, parts, hierarchies and stashes, but cannot
register kinds, apply commands, rebuild hierarchies or init/destroy/reset the world.

A restricted stuff checks `access`: every `_now` and read proc asserts that the kinds it touches
are declared in its `reads` or `writes`. An unrestricted one, like the zero value or what
`stuff_make` gives, has full access.
*/
Stuff :: struct($K: typeid, $S: typeid) where intrinsics.type_is_enum(K),
	intrinsics.type_is_enum(S) {
	world:         ^World(K, S),
	access:        Access(K),
	is_restricted: bool,
}

// >---------------------------------------------------------------------- Stuff

/*
Makes a stuff for the world with full access. Systems get one from the world when they run, limited
to what they declared.
*/
stuff_make :: proc(world: ^World($K, $S)) -> Stuff(K, S) {
	return Stuff(K, S){world = world}
}

/* Makes a stuff for the world limited to `access`, the way a running system gets one. */
stuff_make_restricted :: proc(world: ^World($K, $S), access: Access(K)) -> Stuff(K, S) {
	return Stuff(K, S){world = world, access = access, is_restricted = true}
}

// >--------------------------------------------------------------- Stuff Things

/* See spawn. */
stuff_spawn :: proc(stuff: Stuff($K, $S)) -> Thing {
	return world_spawn(stuff.world)
}

/* See kill_now. */
stuff_kill_now :: proc(stuff: Stuff($K, $S), thing: Thing) -> bool {
	assert_kills(stuff, thing)
	return world_kill_now(stuff.world, thing)
}

/* See kill_later. */
stuff_kill_later :: proc(stuff: Stuff($K, $S), thing: Thing) {
	world_kill_later(stuff.world, thing)
}

/* See kill_tree_now. */
stuff_kill_tree_now :: proc(stuff: Stuff($K, $S), kind: K, thing: Thing) -> bool {
	stuff_assert_writes(stuff, kind)
	assert_kills_tree(stuff, kind, thing)
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
	stuff_assert_reads(stuff, kind)
	return world_has(stuff.world, thing, kind)
}

/* See get_part. */
stuff_get_part :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K, $T: typeid) -> (T, bool) {
	stuff_assert_reads(stuff, kind)
	return world_get_part(stuff.world, thing, kind, T)
}

/* See write_part. */
stuff_write_part :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K, $T: typeid) -> ^T {
	stuff_assert_writes(stuff, kind)
	return world_write_part(stuff.world, thing, kind, T)
}

/* See get_parts. */
stuff_get_parts :: proc(stuff: Stuff($K, $S), kind: K, $T: typeid) -> []T {
	stuff_assert_reads(stuff, kind)
	return world_get_parts(stuff.world, kind, T)
}

/* See write_parts. */
stuff_write_parts :: proc(stuff: Stuff($K, $S), kind: K, $T: typeid) -> []T {
	stuff_assert_writes(stuff, kind)
	return world_write_parts(stuff.world, kind, T)
}

/* See get_things. */
stuff_get_things :: proc(stuff: Stuff($K, $S), kind: K) -> []Thing {
	stuff_assert_reads(stuff, kind)
	return world_get_things(stuff.world, kind)
}

/* See count_parts. */
stuff_count_parts :: proc(stuff: Stuff($K, $S), kind: K) -> int {
	stuff_assert_reads(stuff, kind)
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
	stuff_assert_writes(stuff, kind)
	return world_set_value_now(stuff.world, thing, kind, part)
}

/* See set_now. */
stuff_set_pointer_now :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K, part: ^$T) -> ^T {
	stuff_assert_writes(stuff, kind)
	return world_set_pointer_now(stuff.world, thing, kind, part)
}

/* See set_now. */
stuff_set_zero_now :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K, $T: typeid) -> ^T {
	stuff_assert_writes(stuff, kind)
	return world_set_zero_now(stuff.world, thing, kind, T)
}

/* See add_now. */
stuff_add_now :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K) -> bool {
	stuff_assert_writes(stuff, kind)
	return world_add_now(stuff.world, thing, kind)
}

/* See remove_now. */
stuff_remove_now :: proc(stuff: Stuff($K, $S), thing: Thing, kind: K) -> bool {
	stuff_assert_writes(stuff, kind)
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
	stuff_assert_writes(stuff, kind)
	return world_attach_now(stuff.world, kind, child, parent)
}

/* See attach_later. */
stuff_attach_later :: proc(stuff: Stuff($K, $S), kind: K, child, parent: Thing) {
	world_attach_later(stuff.world, kind, child, parent)
}

/* See detach_now. */
stuff_detach_now :: proc(stuff: Stuff($K, $S), kind: K, child: Thing) -> bool {
	stuff_assert_writes(stuff, kind)
	return world_detach_now(stuff.world, kind, child)
}

/* See detach_later. */
stuff_detach_later :: proc(stuff: Stuff($K, $S), kind: K, child: Thing) {
	world_detach_later(stuff.world, kind, child)
}

/* See get_parent. */
stuff_get_parent :: proc(stuff: Stuff($K, $S), kind: K, child: Thing) -> Thing {
	stuff_assert_reads(stuff, kind)
	return world_get_parent(stuff.world, kind, child)
}

/* See get_first_child. */
stuff_get_first_child :: proc(stuff: Stuff($K, $S), kind: K, parent: Thing) -> Thing {
	stuff_assert_reads(stuff, kind)
	return world_get_first_child(stuff.world, kind, parent)
}

/* See get_next_sibling. */
stuff_get_next_sibling :: proc(stuff: Stuff($K, $S), kind: K, child: Thing) -> Thing {
	stuff_assert_reads(stuff, kind)
	return world_get_next_sibling(stuff.world, kind, child)
}

/* See iter_children. */
stuff_iter_children :: proc(
	stuff: Stuff($K, $S),
	kind: K,
	parent: Thing,
) -> Hierarchy_Children_Iter {
	stuff_assert_reads(stuff, kind)
	return world_iter_children(stuff.world, kind, parent)
}

/* See iter_roots. */
stuff_iter_roots :: proc(stuff: Stuff($K, $S), kind: K) -> Hierarchy_Children_Iter {
	stuff_assert_reads(stuff, kind)
	return world_iter_roots(stuff.world, kind)
}

/* See is_ancestor. */
stuff_is_ancestor :: proc(stuff: Stuff($K, $S), kind: K, ancestor, thing: Thing) -> bool {
	stuff_assert_reads(stuff, kind)
	return world_is_ancestor(stuff.world, kind, ancestor, thing)
}

/* See get_hierarchy_order. */
stuff_get_hierarchy_order :: proc(stuff: Stuff($K, $S), kind: K) -> []Thing {
	stuff_assert_reads(stuff, kind)
	return world_get_hierarchy_order(stuff.world, kind)
}

/* See get_hierarchy_depths. */
stuff_get_hierarchy_depths :: proc(stuff: Stuff($K, $S), kind: K) -> []Hierarchy_Depth {
	stuff_assert_reads(stuff, kind)
	return world_get_hierarchy_depths(stuff.world, kind)
}

/* See get_hierarchy_ends. */
stuff_get_hierarchy_ends :: proc(stuff: Stuff($K, $S), kind: K) -> []Hierarchy_Pos {
	stuff_assert_reads(stuff, kind)
	return world_get_hierarchy_ends(stuff.world, kind)
}

/* See get_subtree. */
stuff_get_subtree :: proc(stuff: Stuff($K, $S), kind: K, thing: Thing) -> []Thing {
	stuff_assert_reads(stuff, kind)
	return world_get_subtree(stuff.world, kind, thing)
}

// >-------------------------------------------------------------- Stuff Stashes

/* See get_stash. */
stuff_get_stash :: proc(stuff: Stuff($K, $S), kind: K, $T: typeid) -> T {
	stuff_assert_reads(stuff, kind)
	return world_get_stash(stuff.world, kind, T)
}

/* See write_stash. */
stuff_write_stash :: proc(stuff: Stuff($K, $S), kind: K, $T: typeid) -> ^T {
	stuff_assert_writes(stuff, kind)
	return world_write_stash(stuff.world, kind, T)
}

// >------------------------------------------------------------------ Internals

@(private, disabled = ODIN_DISABLE_ASSERT)
stuff_assert_reads :: proc(stuff: Stuff($K, $S), kind: K, loc := #caller_location) {
	if !stuff.is_restricted do return
	access := stuff.access

	fmt.assertf(
		kind in access.reads || kind in access.writes,
		"System %v reads %v without declaring it.",
		access.name,
		kind,
		loc = loc,
	)
}

@(private, disabled = ODIN_DISABLE_ASSERT)
stuff_assert_writes :: proc(stuff: Stuff($K, $S), kind: K, loc := #caller_location) {
	if !stuff.is_restricted do return
	access := stuff.access

	fmt.assertf(
		kind in access.writes,
		"System %v writes %v without declaring it in writes.",
		access.name,
		kind,
		loc = loc,
	)
}

@(private = "file", disabled = ODIN_DISABLE_ASSERT)
assert_kills :: proc(stuff: Stuff($K, $S), thing: Thing, loc := #caller_location) {
	access := stuff.access
	world := stuff.world
	if !stuff.is_restricted || !thing_pool_is_alive(&world.thing_pool, thing) do return

	archetype := archetype_pool_get(&world.archetype_pool, thing)
	for kind in archetype.kinds - access.writes {
		fmt.assertf(
			false,
			"System %v kills thing %v with part %v without declaring it in writes.",
			access.name,
			thing.idx,
			kind,
			loc = loc,
		)
	}

	pool := &world.hierarchy_pool
	for kind in pool.registered - access.writes {
		fmt.assertf(
			!hierarchy_set_contains(&pool.sets[kind], thing),
			"System %v kills thing %v in hierarchy %v without declaring it in writes.",
			access.name,
			thing.idx,
			kind,
			loc = loc,
		)
	}
}

@(private = "file", disabled = ODIN_DISABLE_ASSERT)
assert_kills_tree :: proc(stuff: Stuff($K, $S), kind: K, thing: Thing, loc := #caller_location) {
	world := stuff.world
	if !stuff.is_restricted || !thing_pool_is_alive(&world.thing_pool, thing) do return

	it := hierarchy_set_iter_subtree(hierarchy_pool_get_set(&world.hierarchy_pool, kind), thing)
	for tree_thing in hierarchy_subtree_iter(&it) do assert_kills(stuff, tree_thing, loc)
}
