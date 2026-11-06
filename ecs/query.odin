package ecs

import "base:intrinsics"
import "core:fmt"

// >-------------------------------------------------------- Constants and Types

Query :: struct($K: typeid, $S: typeid) where intrinsics.type_is_enum(K),
	intrinsics.type_is_enum(S) {
	stuff:   Stuff(K, S),
	include: Archetype(K),
	exclude: Archetype(K),
	first:   K,
	thing:   Thing,
	pos:     int,
}

// >---------------------------------------------------------------------- Query

query_make :: proc(stuff: Stuff($K, $S), include: bit_set[K], exclude: bit_set[K]) -> Query(K, S) {
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

query_refresh :: proc(query: ^Query($K, $S)) {
	query.first = find_first_kind(query)
	query.thing = {}
	query.pos = 0
}

query_next :: proc(query: ^Query($K, $S)) -> bool {
	world := query.stuff.world
	things := part_pool_get_things(&world.part_pool, query.first)

	for query.pos < len(things) {
		thing := things[query.pos]
		query.pos += 1
		archetype := archetype_pool_get(world.archetype_pool, thing)

		if satisfies(archetype, query.include, query.exclude) {
			query.thing = thing
			return true
		}
	}

	query.thing = {}
	return false
}

// >-------------------------------------------------------- Query Current Thing

query_has :: proc(query: ^Query($K, $S), kind: K) -> bool {
	return world_has(query.stuff.world, query.thing, kind)
}

query_get_part :: proc(query: ^Query($K, $S), kind: K, $T: typeid) -> ^T {
	fmt.assertf(
		query_has(query, kind),
		"Query does not have part %v for thing %v.",
		kind,
		query.thing,
	)

	return part_pool_get_unchecked(&query.stuff.world.part_pool, query.thing, kind, T)
}

query_get_thing :: proc(query: ^Query($K, $S)) -> Thing {
	return query.thing
}

// >------------------------------------------------------------------ Internals

@(private = "file")
satisfies :: proc(archetype: Archetype($K), include: Archetype(K), exclude: Archetype(K)) -> bool {
	return archetype_contains(archetype, include) && archetype_is_disjoint(archetype, exclude)
}

@(private = "file")
find_first_kind :: proc(query: ^Query($K, $S)) -> K {
	kind := K{}
	size := max(int)

	it := archetype_iter_make(query.include)
	for k in archetype_iter_next(&it) {
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
	for kind in archetype_iter_next(&it) do return kind, false
	return K{}, true
}
