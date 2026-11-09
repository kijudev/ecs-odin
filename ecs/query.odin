package ecs

import "base:intrinsics"
import "core:fmt"

// >-------------------------------------------------------- Constants and Types

/*
Iterates the things that have every kind of `include` and none of `exclude`. A plain query walks
the smallest part set of `include`; a hierarchy query walks the order of the `hierarchy` kind.
*/
Query :: struct($K: typeid, $S: typeid) where intrinsics.type_is_enum(K),
	intrinsics.type_is_enum(S) {
	stuff:        Stuff(K, S),
	include:      Archetype(K),
	exclude:      Archetype(K),
	first:        K,
	hierarchy:    K,
	is_hierarchy: bool,
	thing:        Thing,
	pos:          int,
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
	for kind in include | exclude do stuff_assert_reads(stuff, kind)

	query := Query(K, S) {
		stuff   = stuff,
		include = archetype_make(include),
		exclude = archetype_make(exclude),
	}

	assert(!archetype_is_empty(query.include), "Query needs at least one part to iterate.")

	kind, ok := check_conflicts(query.include, query.exclude)
	fmt.assertf(ok, "Query has conflicting parts: %v is in both include and exclude.", kind)

	query_refresh(&query)
	return query
}

/*
Makes a query ready for the first `query_iter` that walks the order of the hierarchy of `kind`,
so a parent always comes before its children. It sees the order of the last rebuild: things
killed since then are skipped, things attached since then only show up after the next rebuild.
Things in the hierarchy without the parts are skipped, their children are still visited.

Asserts:
- `kind` is a registered hierarchy.
- `include` is not empty.
- no kind is in both `include` and `exclude`.
- every kind of `include` is a registered part.
- the system declared `kind` and every kind of `include` and `exclude` in its reads or writes.
*/
query_make_hierarchy :: proc(
	stuff: Stuff($K, $S),
	kind: K,
	include: bit_set[K],
	exclude: bit_set[K],
) -> Query(K, S) {
	hierarchy_pool_assert_registered(&stuff.world.hierarchy_pool, kind)
	stuff_assert_reads(stuff, kind)

	query := query_make(stuff, include, exclude)
	query.hierarchy = kind
	query.is_hierarchy = true
	return query
}

/*
Starts the iteration over. A plain query picks the smallest part set of `include` again.

Asserts:
- every kind of `include` is a registered part.
*/
query_refresh :: proc(query: ^Query($K, $S)) {
	if !query.is_hierarchy do query.first = find_first_kind(query)
	query.thing = {}
	query.pos = 0
}

/*
Moves to the next matching thing, for `for thing in query_iter(&query)`.

Returns the thing and true, or false once there are no more things, and clears the current thing.
Adding or removing parts of the included kinds while iterating can skip or repeat things, use the
`_later` procs for that. Rebuilding the hierarchy of a hierarchy query while iterating is not
supported.
*/
query_iter :: proc(query: ^Query($K, $S)) -> (Thing, bool) {
	world := query.stuff.world
	things: []Thing

	if query.is_hierarchy {
		things = hierarchy_set_order(&world.hierarchy_pool.sets[query.hierarchy])
	} else {
		things = part_pool_get_things(&world.part_pool, query.first)
	}

	for query.pos < len(things) {
		thing := things[query.pos]
		query.pos += 1

		if query.is_hierarchy && !thing_pool_is_alive(world.thing_pool, thing) do continue

		archetype := archetype_pool_get(world.archetype_pool, thing)
		if satisfies(archetype, query.include, query.exclude) {
			query.thing = thing
			return thing, true
		}
	}

	query.thing = {}
	return {}, false
}

// >-------------------------------------------------------- Query Current Thing

/* See has. */
query_has :: proc(query: ^Query($K, $S), kind: K) -> bool {
	return stuff_has(query.stuff, query.thing, kind)
}

/* See get_part. */
query_get_part :: proc(query: ^Query($K, $S), kind: K, $T: typeid) -> T {
	stuff_assert_reads(query.stuff, kind)
	return current_part(query, kind, T)^
}

/* See write_part. */
query_write_part :: proc(query: ^Query($K, $S), kind: K, $T: typeid) -> ^T {
	stuff_assert_writes(query.stuff, kind)
	return current_part(query, kind, T)
}

/* See get_thing. */
query_get_thing :: proc(query: ^Query($K, $S)) -> Thing {
	return query.thing
}

/* See get_parent. */
query_get_parent :: proc(query: ^Query($K, $S)) -> Thing {
	assert_hierarchy_thing(query)
	return world_get_parent(query.stuff.world, query.hierarchy, query.thing)
}

/*
Gets the part of the current thing's parent in the query's hierarchy. Meant for propagating
values down a tree: the parent was visited before the current thing, unless the thing moved to a
new parent since the last rebuild. Rebuild before the pass to rule that out.

Returns a copy of the part and true, or false if the current thing is a root or its parent
doesn't have the part.

Asserts:
- the query is a hierarchy query and has a current thing.
- `kind` is a registered part.
- `T` is the type `kind` was registered with.
- the system declared `kind` in its reads or writes.
*/
query_get_parent_part :: proc(query: ^Query($K, $S), kind: K, $T: typeid) -> (T, bool) {
	return stuff_get_part(query.stuff, query_get_parent(query), kind, T)
}

/*
Gets the depth of the current thing in the query's hierarchy, as of the last rebuild. Roots are at
depth 0.

Asserts:
- the query is a hierarchy query and has a current thing.
*/
query_get_depth :: proc(query: ^Query($K, $S)) -> Hierarchy_Depth {
	assert_hierarchy_thing(query)

	depths := hierarchy_set_depths(&query.stuff.world.hierarchy_pool.sets[query.hierarchy])
	return depths[query.pos - 1]
}

/*
Skips the descendants of the current thing, so the next `query_iter` continues after its subtree.
The current thing stays current until then.

Asserts:
- the query is a hierarchy query and has a current thing.
*/
query_skip_subtree :: proc(query: ^Query($K, $S)) {
	assert_hierarchy_thing(query)

	ends := hierarchy_set_ends(&query.stuff.world.hierarchy_pool.sets[query.hierarchy])
	query.pos = int(ends[query.pos - 1])
}

// >------------------------------------------------------------------ Internals

@(private = "file")
current_part :: proc(query: ^Query($K, $S), kind: K, $T: typeid) -> ^T {
	fmt.assertf(query.thing != {}, "Query has no current thing to get part %v from.", kind)
	fmt.assertf(
		world_has(query.stuff.world, query.thing, kind),
		"Query does not have part %v for thing %v.",
		kind,
		query.thing,
	)

	return part_pool_get_unchecked(&query.stuff.world.part_pool, query.thing, kind, T)
}

@(private = "file")
assert_hierarchy_thing :: proc(query: ^Query($K, $S), loc := #caller_location) {
	fmt.assertf(
		query.is_hierarchy,
		"Query has no hierarchy, make it with query_make_hierarchy.",
		loc = loc,
	)
	fmt.assertf(query.thing != {}, "Query has no current thing.", loc = loc)
}

@(private = "file")
satisfies :: proc(archetype: Archetype($K), include: Archetype(K), exclude: Archetype(K)) -> bool {
	return archetype_contains(archetype, include) && archetype_is_disjoint(archetype, exclude)
}

@(private = "file")
find_first_kind :: proc(query: ^Query($K, $S)) -> K {
	kind := K{}
	size := max(int)

	it := archetype_iter_make(query.include)
	for k in archetype_iter(&it) {
		count := part_pool_count_parts(&query.stuff.world.part_pool, k)
		if count < size {
			size = count
			kind = k
		}
	}

	return kind
}

@(private = "file")
check_conflicts :: proc(include: Archetype($K), exclude: Archetype(K)) -> (K, bool) {
	it := archetype_iter_make(archetype_intersect(include, exclude))
	for kind in archetype_iter(&it) do return kind, false
	return K{}, true
}
