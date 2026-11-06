package ecs

import "base:intrinsics"
import "core:fmt"

// >-------------------------------------------------------- Constants and Types

Query :: struct($P: typeid, $R: typeid, $S: typeid) where intrinsics.type_is_enum(P),
	intrinsics.type_is_enum(R),
	intrinsics.type_is_enum(S) {
	stuff:      Stuff(P, R, S),
	include:      Archetype(P),
	exclude:   Archetype(P),
	first_kind: P,
	thing:      Thing,
	iter_pos:   int,
}

// >---------------------------------------------------------------------- Query

query_make :: proc(
	stuff: Stuff($P, $R, $S),
	include: bit_set[P],
	exclude: bit_set[P],
) -> Query(P, R, S) {
	query := Query(P, R, S) {
		stuff    = stuff,
		include    = archetype_make(include),
		exclude = archetype_make(exclude),
	}

	assert(!archetype_is_empty(query.include), "Query needs at least one part to iterate.")

	kind, ok := check_conflicts(query.include, query.exclude)
	fmt.assertf(ok, "Query has conflicting parts: %v is in both include and exclude.", kind)

	query_refresh(&query)
	return query
}

query_refresh :: proc(query: ^Query($P, $R, $S)) {
	query.first_kind = find_first_kind(query)
	query.thing = {}
	query.iter_pos = 0
}

query_next :: proc(query: ^Query($P, $R, $S)) -> bool {
	world := query.stuff.world
	things := part_pool_get_things(&world.part_pool, query.first_kind)

	for query.iter_pos < len(things) {
		thing := things[query.iter_pos]
		query.iter_pos += 1
		archetype := archetype_pool_get(world.archetype_pool, thing)

		if satisfies(archetype, query.include, query.exclude) {
			query.thing = thing
			return true
		}
	}

	query.thing = {}
	return false
}

// >---------------------------------------------------------- Query Current Thing

query_has :: proc(query: ^Query($P, $R, $S), kind: P) -> bool {
	return world_has(query.stuff.world, query.thing, kind)
}

query_get_part :: proc(query: ^Query($P, $R, $S), kind: P, $T: typeid) -> ^T {
	return world_get_part(query.stuff.world, query.thing, kind, T)
}

query_get_thing :: proc(query: ^Query($P, $R, $S)) -> Thing {
	return query.thing
}

// >------------------------------------------------------------------ Internals

@(private = "file")
satisfies :: proc(archetype: Archetype($P), include: Archetype(P), exclude: Archetype(P)) -> bool {
	return archetype_contains(archetype, include) && archetype_is_disjoint(archetype, exclude)
}

@(private = "file")
find_first_kind :: proc(query: ^Query($P, $R, $S)) -> P {
	kind := P{}
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
check_conflicts :: proc(include: Archetype($P), exclude: Archetype(P)) -> (P, bool) {
	it := archetype_iter_make(archetype_intersect(include, exclude))
	for kind in archetype_iter_next(&it) do return kind, false
	return P{}, true
}
