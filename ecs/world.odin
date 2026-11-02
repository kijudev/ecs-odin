package ecs

import "base:intrinsics"

// >-------------------------------------------------------- Constants and Types

World :: struct($P: typeid) where intrinsics.type_is_enum(P) {
	thing_pool:     Thing_Pool,
	part_pool:      Part_Pool,
	archetype_pool: Archetype_Pool(P),
	type_part:      map[typeid]P,
	part_type:      map[P]typeid,
}

// >---------------------------------------------------------------------- World

world_register_part :: proc(
	world: ^World($P),
	kind: P,
	$T: typeid,
	destroy: proc(part: rawptr) = nil,
) {
}
