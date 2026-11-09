package ecs

import "base:intrinsics"
import "core:fmt"

// >-------------------------------------------------------- Constants and Types

/* What both query types share: the stuff they run in, the kinds to match and the current thing. */
Query_Base :: struct($K: typeid, $S: typeid) where intrinsics.type_is_enum(K),
	intrinsics.type_is_enum(S) {
	stuff:   Stuff(K, S),
	include: bit_set[K],
	exclude: bit_set[K],
	thing:   Thing,
	pos:     int,
}

/*
Iterates the things that have every kind of `include` and none of `exclude`. It walks the smallest
part set of `include`, the one of `first`.
*/
Query :: struct($K: typeid, $S: typeid) where intrinsics.type_is_enum(K),
	intrinsics.type_is_enum(S) {
	using base:  Query_Base(K, S),
	first:       K,
	first_set:   ^Part_Set,
	is_filtered: bool,
}

/*
Iterates the things that have every kind of `include` and none of `exclude` in the order of the
`hierarchy` kind, so a parent always comes before its children.
*/
Hierarchy_Query :: struct($K: typeid, $S: typeid) where intrinsics.type_is_enum(K),
	intrinsics.type_is_enum(S) {
	using base: Query_Base(K, S),
	hierarchy:  K,
	set:        ^Hierarchy_Set,
}

// >---------------------------------------------------------------------- Query

/*
Makes a query ready for the first `query_iter`. It walks the smallest part set of `include`.

Asserts:
- `include` is not empty.
- no kind is in both `include` and `exclude`.
- every kind of `include` is a registered part.
- the system declared every kind of `include` and `exclude` in its reads or writes.
*/
query_make :: proc(stuff: Stuff($K, $S), include: bit_set[K], exclude: bit_set[K]) -> Query(K, S) {
	query := Query(K, S) {
		base = base_make(stuff, include, exclude),
	}

	query_refresh(&query)
	return query
}

/*
Picks the smallest part set of `include` again and starts the iteration over.

Asserts:
- every kind of `include` is a registered part.
*/
query_refresh :: proc(query: ^Query($K, $S)) {
	query.first = find_first_kind(&query.base)
	query.first_set = &query.stuff.world.part_pool.sets[query.first]
	query.is_filtered = query.include != {query.first} || query.exclude != {}
	query.thing = {}
	query.pos = 0
}

/*
Moves to the next matching thing, for `for thing in query_iter(&query)`.

Returns the thing and true, or false once there are no more things, and clears the current thing.
Adding or removing parts of the included kinds while iterating can skip or repeat things, use the
`_later` procs for that.
*/
query_iter :: #force_inline proc(query: ^Query($K, $S)) -> (Thing, bool) {
	things := part_set_get_things(query.first_set)

	#no_bounds_check for query.pos < len(things) {
		thing := things[query.pos]
		query.pos += 1

		if query.is_filtered && !base_matches(&query.base, thing) do continue

		query.thing = thing
		return thing, true
	}

	query.thing = {}
	return {}, false
}

/* See has. */
query_has :: proc(query: ^Query($K, $S), kind: K) -> bool {
	return stuff_has(query.stuff, query.thing, kind)
}

/* See get_thing. */
query_get_thing :: proc(query: ^Query($K, $S)) -> Thing {
	return query.thing
}

/* See get_part. */
query_get_part :: #force_inline proc(query: ^Query($K, $S), kind: K, $T: typeid) -> T {
	stuff_assert_reads(query.stuff, kind)
	return query_part(query, kind, T)^
}

/* See write_part. */
query_write_part :: #force_inline proc(query: ^Query($K, $S), kind: K, $T: typeid) -> ^T {
	stuff_assert_writes(query.stuff, kind)
	return query_part(query, kind, T)
}

// >------------------------------------------------------------ Hierarchy_Query

/*
Makes a query ready for the first `hierarchy_query_iter` that walks the order of the hierarchy of
`kind`. It sees the order of the last rebuild: things killed since then are skipped, things
attached since then only show up after the next rebuild. Things in the hierarchy without the parts
are skipped, their children are still visited.

Asserts:
- `kind` is a registered hierarchy.
- `include` is not empty.
- no kind is in both `include` and `exclude`.
- every kind of `include` is a registered part.
- the system declared `kind` and every kind of `include` and `exclude` in its reads or writes.
*/
hierarchy_query_make :: proc(
	stuff: Stuff($K, $S),
	kind: K,
	include: bit_set[K],
	exclude: bit_set[K],
) -> Hierarchy_Query(K, S) {
	set := hierarchy_pool_get_set(&stuff.world.hierarchy_pool, kind)
	stuff_assert_reads(stuff, kind)

	return Hierarchy_Query(K, S) {
		base = base_make(stuff, include, exclude),
		hierarchy = kind,
		set = set,
	}
}

/* Starts the iteration over. */
hierarchy_query_refresh :: proc(query: ^Hierarchy_Query($K, $S)) {
	query.thing = {}
	query.pos = 0
}

/*
Moves to the next matching thing, for `for thing in hierarchy_query_iter(&query)`.

Returns the thing and true, or false once there are no more things, and clears the current thing.
Adding or removing parts of the included kinds while iterating can skip or repeat things, use the
`_later` procs for that. Rebuilding the hierarchy while iterating is not supported.
*/
hierarchy_query_iter :: #force_inline proc(query: ^Hierarchy_Query($K, $S)) -> (Thing, bool) {
	order := hierarchy_set_order(query.set)
	things := &query.stuff.world.thing_pool

	#no_bounds_check for query.pos < len(order) {
		thing := order[query.pos]
		query.pos += 1

		if !thing_pool_is_alive(things, thing) || !base_matches(&query.base, thing) do continue

		query.thing = thing
		return thing, true
	}

	query.thing = {}
	return {}, false
}

/* See has. */
hierarchy_query_has :: proc(query: ^Hierarchy_Query($K, $S), kind: K) -> bool {
	return stuff_has(query.stuff, query.thing, kind)
}

/* See get_thing. */
hierarchy_query_get_thing :: proc(query: ^Hierarchy_Query($K, $S)) -> Thing {
	return query.thing
}

/* See get_part. */
hierarchy_query_get_part :: #force_inline proc(
	query: ^Hierarchy_Query($K, $S),
	kind: K,
	$T: typeid,
) -> T {
	stuff_assert_reads(query.stuff, kind)
	return base_part(&query.base, kind, T)^
}

/* See write_part. */
hierarchy_query_write_part :: #force_inline proc(
	query: ^Hierarchy_Query($K, $S),
	kind: K,
	$T: typeid,
) -> ^T {
	stuff_assert_writes(query.stuff, kind)
	return base_part(&query.base, kind, T)
}

/* See get_parent. */
hierarchy_query_get_parent :: proc(query: ^Hierarchy_Query($K, $S)) -> Thing {
	assert_current(&query.base)
	return world_get_parent(query.stuff.world, query.hierarchy, query.thing)
}

/*
Gets the part of the current thing's parent. Meant for propagating values down a tree: the parent
was visited before the current thing, unless the thing moved to a new parent since the last
rebuild. Rebuild before the pass to rule that out.

Returns a copy of the part and true, or false if the current thing is a root or its parent
doesn't have the part.

Asserts:
- the query has a current thing.
- `kind` is a registered part.
- `T` is the type `kind` was registered with.
- the system declared `kind` in its reads or writes.
*/
hierarchy_query_get_parent_part :: proc(
	query: ^Hierarchy_Query($K, $S),
	kind: K,
	$T: typeid,
) -> (
	T,
	bool,
) {
	return stuff_get_part(query.stuff, hierarchy_query_get_parent(query), kind, T)
}

/*
Gets the depth of the current thing, as of the last rebuild. Roots are at depth 0.

Asserts:
- the query has a current thing.
*/
hierarchy_query_get_depth :: proc(query: ^Hierarchy_Query($K, $S)) -> Hierarchy_Depth {
	assert_current(&query.base)
	return hierarchy_set_depths(query.set)[query.pos - 1]
}

/*
Skips the descendants of the current thing, so the next `hierarchy_query_iter` continues after its
subtree. The current thing stays current until then.

Asserts:
- the query has a current thing.
*/
hierarchy_query_skip_subtree :: proc(query: ^Hierarchy_Query($K, $S)) {
	assert_current(&query.base)
	query.pos = int(hierarchy_set_ends(query.set)[query.pos - 1])
}

// >------------------------------------------------------------------ Internals

@(private = "file")
base_make :: proc(
	stuff: Stuff($K, $S),
	include: bit_set[K],
	exclude: bit_set[K],
) -> Query_Base(K, S) {
	for kind in include | exclude do stuff_assert_reads(stuff, kind)
	assert(include != {}, "Query needs at least one part to iterate.")

	kind, ok := check_conflicts(include, exclude)
	fmt.assertf(ok, "Query has conflicting parts: %v is in both include and exclude.", kind)

	for k in include do part_pool_assert_registered(&stuff.world.part_pool, k)

	return Query_Base(K, S){stuff = stuff, include = include, exclude = exclude}
}

@(private = "file")
base_matches :: #force_inline proc(base: ^Query_Base($K, $S), thing: Thing) -> bool {
	archetype := archetype_pool_get_unchecked(&base.stuff.world.archetype_pool, thing)
	return archetype & base.include == base.include && archetype & base.exclude == {}
}

@(private = "file")
base_part :: #force_inline proc(base: ^Query_Base($K, $S), kind: K, $T: typeid) -> ^T {
	fmt.assertf(base.thing != {}, "Query has no current thing to get part %v from.", kind)
	fmt.assertf(
		world_has(base.stuff.world, base.thing, kind),
		"Query does not have part %v for thing %v.",
		kind,
		base.thing,
	)

	return part_pool_get_unchecked(&base.stuff.world.part_pool, base.thing, kind, T)
}

@(private = "file")
query_part :: #force_inline proc(
	query: ^Query($K, $S),
	kind: K,
	$T: typeid,
) -> ^T #no_bounds_check {
	if kind != query.first do return base_part(&query.base, kind, T)

	set := query.first_set
	idx := query.pos - 1
	part_pool_assert_type(&query.stuff.world.part_pool, kind, T)
	fmt.assertf(query.thing != {}, "Query has no current thing to get part %v from.", kind)
	fmt.assertf(
		idx < set.parts_size && set.things[idx] == query.thing,
		"Query does not have part %v for thing %v.",
		kind,
		query.thing,
	)

	return cast(^T)part_set_get_at_unchecked(set, idx)
}

@(private = "file")
assert_current :: proc(base: ^Query_Base($K, $S), loc := #caller_location) {
	fmt.assertf(base.thing != {}, "Query has no current thing.", loc = loc)
}

@(private = "file")
find_first_kind :: proc(base: ^Query_Base($K, $S)) -> K {
	kind := K{}
	size := max(int)

	for k in base.include {
		count := part_pool_count_parts(&base.stuff.world.part_pool, k)
		if count < size {
			size = count
			kind = k
		}
	}

	return kind
}

@(private = "file")
check_conflicts :: proc(include: bit_set[$K], exclude: bit_set[K]) -> (K, bool) {
	for kind in include & exclude do return kind, false
	return K{}, true
}
