package bench

import ecs "../../ecs"

// oecs setups shared by the flat and hierarchy cases.

Kind :: enum {
	A,
	B,
	C,
	D,
	Tag,
	Local,
	Global,
	Transform,
}

Stage :: enum {
	Update,
}

World :: ecs.World(Kind, Stage)
Stuff :: ecs.Stuff(Kind, Stage)
Thing :: ecs.Thing

Part :: struct {
	x, y, z, w: f32,
}

Vec2 :: struct {
	x, y: f32,
}

Tag :: struct {}

PART :: Part {
	x = 1,
}
LOCAL :: Vec2{1, 1}

// things[i] is the i-th spawned thing.
things: []Thing

// >---------------------------------------------------------------------- Setup

/*
Initializes the world with room for n things, the least oecs needs. Only hierarchy cases register
the hierarchy, since it allocates room for every thing up front.
*/
make_world :: proc(w: ^World, n: int, hierarchy := false) {
	ecs.world_init(w, {capacity = max(n + 1, ecs.THING_POOL_MIN_CAPACITY)})
	ecs.register_part(w, .A, Part)
	ecs.register_part(w, .B, Part)
	ecs.register_part(w, .C, Part)
	ecs.register_part(w, .D, Part)
	ecs.register_part(w, .Tag, Tag)
	ecs.register_part(w, .Local, Vec2)
	ecs.register_part(w, .Global, Vec2)
	if hierarchy do ecs.register_hierarchy(w, .Transform)
}

/* Spawns n things, setting `parts` on each in A, B, C, D, Local, Global order. */
spawn :: proc(w: ^World, n: int, $parts: bit_set[Kind]) {
	if len(things) != n {
		delete(things)
		things = make([]Thing, n)
	}

	for &t in things {
		t = ecs.spawn(w)
		when .A in parts do ecs.set_now(w, t, .A, PART)
		when .B in parts do ecs.set_now(w, t, .B, PART)
		when .C in parts do ecs.set_now(w, t, .C, PART)
		when .D in parts do ecs.set_now(w, t, .D, PART)
		when .Local in parts do ecs.set_now(w, t, .Local, LOCAL)
		when .Global in parts do ecs.set_now(w, t, .Global, Vec2{})
	}
}

make_full :: proc(w: ^World, n: int) {
	make_world(w, n)
	spawn(w, n, {.A, .B, .C, .D})
}

make_sparse :: proc(w: ^World, n, permille: int) {
	make_world(w, n)
	spawn(w, n, {.A})
	for i in 0 ..< n do if is_sparse(i, permille) do ecs.set_now(w, things[i], .B, PART)
}

make_fragmented :: proc(w: ^World, n: int) {
	make_world(w, n)
	spawn(w, n, {})
	for t, i in things {
		bits := i % 16
		if bits & 1 != 0 do ecs.set_now(w, t, .A, PART)
		if bits & 2 != 0 do ecs.set_now(w, t, .B, PART)
		if bits & 4 != 0 do ecs.set_now(w, t, .C, PART)
		if bits & 8 != 0 do ecs.set_now(w, t, .D, PART)
		if bits == 0 do ecs.add_now(w, t, .Tag)
	}
}

// >------------------------------------------------------------------ Checksums

sum_x :: proc(w: ^World, kind: Kind) -> f64 {
	sum: f64
	for part in ecs.get_parts(w, kind, Part) do sum += f64(part.x)
	return sum
}

count_alive :: proc(w: ^World) -> f64 {
	alive: f64
	for t in things do if ecs.is_alive(w, t) do alive += 1
	return alive
}
