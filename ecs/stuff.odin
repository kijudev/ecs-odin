package ecs

import "base:intrinsics"

// >-------------------------------------------------------- Constants and Types

Stuff :: struct($P: typeid, $R: typeid, $S: typeid) where intrinsics.type_is_enum(P),
	intrinsics.type_is_enum(R),
	intrinsics.type_is_enum(S) {
	world: ^World(P, R),
}

// >---------------------------------------------------------------------- Stuff

stuff_make :: proc(world: ^World($P, $R), $S: typeid) -> Stuff(P, R, S) {
	return Stuff(P, R, S){world = world}
}
