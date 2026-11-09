package bench

import "core:strings"

import ecs "../../ecs"

// Hierarchy cases, see CASES.md.

// >-------------------------------------------------------------------- Helpers

attach_all :: proc(w: ^World, $shape: Shape, n: int) {
	for i in 0 ..< n {
		if p := parent_of(shape, i); p >= 0 do ecs.attach_now(w, .Transform, things[i], things[p])
	}
}

propagate :: proc(w: ^World) {
	q := ecs.hierarchy_query_make(ecs.stuff_make(w), .Transform, {.Local, .Global}, {})
	for _ in ecs.hierarchy_query_iter(&q) {
		local := ecs.get_part(&q, .Local, Vec2)
		global := ecs.write_part(&q, .Global, Vec2)
		parent, has_parent := ecs.hierarchy_query_get_parent_part(&q, .Global, Vec2)
		global^ = has_parent ? Vec2{parent.x + local.x, parent.y + local.y} : local
	}
}

make_nodes :: proc(w: ^World, n: int) {
	make_world(w, n, hierarchy = true)
	spawn(w, n, {.Local, .Global})
}

make_shape :: proc(w: ^World, $shape: Shape, n: int) {
	make_nodes(w, n)
	attach_all(w, shape, n)
	ecs.world_rebuild_hierarchy(w, .Transform)
}

global_sum :: proc(w: ^World) -> f64 {
	sum: f64
	for g in ecs.get_parts(w, .Global, Vec2) do sum += f64(g.x + g.y)
	return sum
}

count_children :: proc(w: ^World) -> f64 {
	count: f64
	for t in things {
		if ecs.is_alive(w, t) && ecs.get_parent(w, .Transform, t) != ecs.THING_NIL do count += 1
	}
	return count
}

// >---------------------------------------------------------------------- Cases

attach_case :: proc(s: ^Sampler, n: int, $shape: Shape) -> f64 {
	w: World
	make_nodes(&w, n)
	defer ecs.world_destroy(&w)

	for timed(s, n - count_roots(shape, n)) do attach_all(&w, shape, n)

	return count_children(&w)
}

attach_later_case :: proc(s: ^Sampler, n: int, $shape: Shape) -> f64 {
	w: World
	make_nodes(&w, n)
	defer ecs.world_destroy(&w)

	for timed(s, n - count_roots(shape, n)) {
		for i in 0 ..< n {
			if p := parent_of(shape, i); p >= 0 do ecs.attach_later(&w, .Transform, things[i], things[p])
		}
		ecs.world_apply(&w)
	}

	return count_children(&w)
}

rebuild_case :: proc(s: ^Sampler, n: int, $shape: Shape) -> f64 {
	w: World
	make_nodes(&w, n)
	defer ecs.world_destroy(&w)
	attach_all(&w, shape, n)

	for timed(s, n) do ecs.world_rebuild_hierarchy(&w, .Transform)

	return 0
}

propagate_case :: proc(s: ^Sampler, n: int, $shape: Shape) -> f64 {
	w: World
	make_shape(&w, shape, n)
	defer ecs.world_destroy(&w)

	for repeated(s, n) do propagate(&w)

	return global_sum(&w)
}

parent_case :: proc(s: ^Sampler, n: int, $shape: Shape, $rand: bool) -> f64 {
	w: World
	make_shape(&w, shape, n)
	defer ecs.world_destroy(&w)

	count: f64
	for repeated(s, n) {
		for j in 0 ..< n {
			if ecs.get_parent(&w, .Transform, handle(rand, j)) != ecs.THING_NIL do count += 1
		}
	}

	return count
}

children_case :: proc(s: ^Sampler, n: int, $shape: Shape) -> f64 {
	w: World
	make_shape(&w, shape, n)
	defer ecs.world_destroy(&w)

	count: f64
	for repeated(s, n) {
		for t in things {
			children := ecs.iter_children(&w, .Transform, t)
			for _ in ecs.hierarchy_children_iter(&children) do count += 1
		}
	}

	return count
}

reparent_case :: proc(s: ^Sampler, n: int, $shape: Shape) -> f64 {
	w: World
	make_shape(&w, shape, n)
	defer ecs.world_destroy(&w)
	propagate(&w) // As in a running game: roots that lose all children keep a fresh Global.

	for timed(s, n / 10) {
		for j in 0 ..< n / 10 {
			if c := perm[j]; c > 0 {
				ecs.attach_now(&w, .Transform, things[c], things[reparent_target(shape, c)])
			}
		}
	}

	ecs.world_rebuild_hierarchy(&w, .Transform)
	propagate(&w)
	return global_sum(&w)
}

kill_whole_case :: proc(s: ^Sampler, n: int, $shape: Shape) -> f64 {
	w: World
	make_shape(&w, shape, n)
	defer ecs.world_destroy(&w)

	for timed(s, n) {
		for i in 0 ..< n {
			if parent_of(shape, i) < 0 do ecs.kill_tree_now(&w, .Transform, things[i])
		}
	}

	return count_alive(&w)
}

kill_small_case :: proc(s: ^Sampler, n: int, $shape: Shape) -> f64 {
	w: World
	make_shape(&w, shape, n)
	defer ecs.world_destroy(&w)

	for timed(s, n / 100) {
		for j in 0 ..< n / 100 do ecs.kill_tree_now(&w, .Transform, things[perm[j]])
	}

	return count_alive(&w)
}

// >---------------------------------------------------------------------- Cases

shape_cases :: proc($shape: Shape, name: string) -> [10]Case {
	n :: proc(prefix, name: string) -> string {return strings.concatenate({prefix, name})}

	// odinfmt: disable
	return {
		{"hierarchy", n("attach.", name), proc(s: ^Sampler, n: int) -> f64 {return attach_case(s, n, shape)}},
		{"hierarchy", n("attach.later.", name), proc(s: ^Sampler, n: int) -> f64 {return attach_later_case(s, n, shape)}},
		{"hierarchy", n("rebuild.", name), proc(s: ^Sampler, n: int) -> f64 {return rebuild_case(s, n, shape)}},
		{"hierarchy", n("propagate.", name), proc(s: ^Sampler, n: int) -> f64 {return propagate_case(s, n, shape)}},
		{"hierarchy", n("parent.seq.", name), proc(s: ^Sampler, n: int) -> f64 {return parent_case(s, n, shape, false)}},
		{"hierarchy", n("parent.rand.", name), proc(s: ^Sampler, n: int) -> f64 {return parent_case(s, n, shape, true)}},
		{"hierarchy", n("children.", name), proc(s: ^Sampler, n: int) -> f64 {return children_case(s, n, shape)}},
		{"hierarchy", n("reparent.", name), proc(s: ^Sampler, n: int) -> f64 {return reparent_case(s, n, shape)}},
		{"hierarchy", n("kill.whole.", name), proc(s: ^Sampler, n: int) -> f64 {return kill_whole_case(s, n, shape)}},
		{"hierarchy", n("kill.small.", name), proc(s: ^Sampler, n: int) -> f64 {return kill_small_case(s, n, shape)}},
	}
	// odinfmt: enable
}
