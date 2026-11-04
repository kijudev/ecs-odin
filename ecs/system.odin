package ecs

import "base:intrinsics"
import "core:slice"

// >-------------------------------------------------------- Constants and Types

Context :: struct($P: typeid, $S: typeid) where intrinsics.type_is_enum(P),
	intrinsics.type_is_enum(S) {
	world: ^World(P),
}

System_Info :: struct($P: typeid, $S: typeid) where intrinsics.type_is_enum(P),
	intrinsics.type_is_enum(S) {
	reads:  bit_set[P],
	writes: bit_set[P],
	stage:  S,
}

System_Pool :: struct($P: typeid, $S: typeid) where intrinsics.type_is_enum(P),
	intrinsics.type_is_proc(R),
	intrinsics.type_is_enum(S) {
	systems:   [dynamic]System_Info(P, S),
	allocator: mem.Allocator,
}

// >--------------------------------------------------------------------- System

// >---------------------------------------------------------------- System_Pool
