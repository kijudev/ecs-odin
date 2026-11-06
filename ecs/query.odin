package ecs

import "base:intrinsics"
import "core:fmt"

// >-------------------------------------------------------- Constants and Types

Query :: struct($P: typeid, $R: typeid, $S: typeid) where intrinsics.type_is_enum(P),
	intrinsics.type_is_enum(R),
	intrinsics.type_is_enum(S) {
	stuff:           Stuff(P, R, S),
	qwith:           bit_set[P],
	qwithout:        bit_set[P],
	first_pool_kind: P,
	first_pool_size: int,
	iter_thing:      Thing,
	iter_pos:        int,
}

// >---------------------------------------------------------------------- Query

query_make :: proc(
	stuff: Stuff($P, $R, $S),
	qwith: bit_set[P],
	qwithout: bit_set[P],
) -> Query(P, R, S) {
	// fmt.assertf(qwith == bit_set[P]{}, "Query with no parts is not allowed.")

	kind, ok := check_conflicts(qwith, qwithout)
	fmt.assertf(ok, "Query has conflicting parts: %v is in both with and without.", kind)

	query := Query(P, R, S) {
		stuff    = stuff,
		qwith    = qwith,
		qwithout = qwithout,
	}

	first_kind, first_size := find_first_pool(&query)
	query.first_pool_kind = first_kind
	query.first_pool_size = first_size

	return query
}

query_refresh :: proc(query: ^Query($P, $R, $S)) {
	query.first_pool_kind = R{}
	query.first_pool_size = 0
	query.iter_thing = {}
}

query_next :: proc(query: ^Query($P, $R, $S)) -> bool {
	world := query.stuff.world
	things := part_set_get_things(&world.part_pool.sets[query.first_pool_kind])

	for query.iter_pos < len(things) {
		thing := things[query.iter_pos]
		query.iter_pos += 1
		archetype := archetype_pool_get_mask(world.archetype_pool, thing)

		if satifies(archetype, query.qwith, query.qwithout) {
			query.iter_thing = thing
			return true
		}
	}

	return false
}

query_get_thing :: proc(query: ^Query($P, $R, $S)) -> Thing {
	return query.iter_thing
}

query_get_part :: proc(query: ^Query($P, $R, $S), kind: P, $T: typeid) -> ^T {
	thing := query.iter_thing
	return get_part(query.stuff.world, thing, kind, T)
}

// >------------------------------------------------------------------ Internals

@(private = "file")
satifies :: proc(archetype: bit_set[$P], qwith: bit_set[P], qwithout: bit_set[P]) -> bool {
	return (archetype & qwith) == qwith && (archetype & qwithout) == {}
}

@(private = "file")
find_first_pool :: proc(query: ^Query($P, $R, $S)) -> (P, int) {
	size := 0
	kind := P{}

	for k in query.qwith {
		sz := part_set_count_parts(&query.stuff.world.part_pool.sets[k])
		if sz < size {
			size = sz
			kind = k
		}
	}

	return kind, size
}

@(private = "file")
check_conflicts :: proc(qwith: bit_set[$P], qwithout: bit_set[P]) -> (P, bool) {
	for kind in qwith do if kind in qwithout do return kind, false
	return P{}, true
}
