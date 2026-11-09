package bench

import ecs "../../ecs"

// Flat cases, see CASES.md.

// >------------------------------------------------------------------ Lifecycle

spawn_case :: proc(s: ^Sampler, n: int, $parts: bit_set[Kind]) -> f64 {
	w: World
	make_world(&w, n)
	defer ecs.world_destroy(&w)

	for timed(s, n) do spawn(&w, n, parts)

	return parts == {} ? count_alive(&w) : sum_x(&w, .A)
}

kill :: proc(s: ^Sampler, n: int) -> f64 {
	w: World
	make_full(&w, n)
	defer ecs.world_destroy(&w)

	for timed(s, n) {
		for t in things do ecs.kill_now(&w, t)
	}

	return count_alive(&w)
}

kill_later :: proc(s: ^Sampler, n: int) -> f64 {
	w: World
	make_full(&w, n)
	defer ecs.world_destroy(&w)

	for timed(s, n) {
		for t in things do ecs.kill_later(&w, t)
		ecs.world_apply(&w)
	}

	return count_alive(&w)
}

// >------------------------------------------------------------------ Structure

add_tag :: proc(s: ^Sampler, n: int) -> f64 {
	w: World
	make_full(&w, n)
	defer ecs.world_destroy(&w)

	for timed(s, n) {
		for t in things do ecs.add_now(&w, t, .Tag)
	}

	return f64(ecs.count_parts(&w, .Tag))
}

add_tag_later :: proc(s: ^Sampler, n: int) -> f64 {
	w: World
	make_full(&w, n)
	defer ecs.world_destroy(&w)

	for timed(s, n) {
		for t in things do ecs.add_later(&w, t, .Tag)
		ecs.world_apply(&w)
	}

	return f64(ecs.count_parts(&w, .Tag))
}

remove_tag :: proc(s: ^Sampler, n: int) -> f64 {
	w: World
	make_full(&w, n)
	defer ecs.world_destroy(&w)
	for t in things do ecs.add_now(&w, t, .Tag)

	for timed(s, n) {
		for t in things do ecs.remove_now(&w, t, .Tag)
	}

	return f64(ecs.count_parts(&w, .Tag))
}

add_d :: proc(s: ^Sampler, n: int) -> f64 {
	w: World
	make_world(&w, n)
	defer ecs.world_destroy(&w)
	spawn(&w, n, {.A, .B, .C})

	for timed(s, n) {
		for t in things do ecs.set_now(&w, t, .D, PART)
	}

	return sum_x(&w, .D)
}

remove_d :: proc(s: ^Sampler, n: int) -> f64 {
	w: World
	make_full(&w, n)
	defer ecs.world_destroy(&w)

	for timed(s, n) {
		for t in things do ecs.remove_now(&w, t, .D)
	}

	return f64(ecs.count_parts(&w, .D))
}

// >-------------------------------------------------------------------- Queries

/* A.x += 1 + the x of every other part in `include`. A is always included. */
query :: proc(stuff: Stuff, $include: bit_set[Kind], exclude: bit_set[Kind] = {}) {
	q := ecs.query_make(stuff, include, exclude)
	for _ in ecs.query_iter(&q) {
		a := ecs.write_part(&q, .A, Part)
		x: f32 = 1
		when .B in include do x += ecs.get_part(&q, .B, Part).x
		when .C in include do x += ecs.get_part(&q, .C, Part).x
		when .D in include do x += ecs.get_part(&q, .D, Part).x
		a.x += x
	}
}

uniform :: proc(s: ^Sampler, n: int, $include: bit_set[Kind]) -> f64 {
	w: World
	make_full(&w, n)
	defer ecs.world_destroy(&w)

	for repeated(s, n) do query(ecs.stuff_make(&w), include)

	return sum_x(&w, .A)
}

exclude :: proc(s: ^Sampler, n: int) -> f64 {
	w: World
	make_full(&w, n)
	defer ecs.world_destroy(&w)
	for i := 0; i < n; i += 2 do ecs.add_now(&w, things[i], .Tag)

	for repeated(s, n) do query(ecs.stuff_make(&w), {.A, .B}, {.Tag})

	return sum_x(&w, .A)
}

sparse :: proc(s: ^Sampler, n: int, permille: int) -> f64 {
	w: World
	make_sparse(&w, n, permille)
	defer ecs.world_destroy(&w)

	for repeated(s, n) do query(ecs.stuff_make(&w), {.A, .B})

	return sum_x(&w, .A)
}

fragmented :: proc(s: ^Sampler, n: int, $include: bit_set[Kind]) -> f64 {
	w: World
	make_fragmented(&w, n)
	defer ecs.world_destroy(&w)

	for repeated(s, n) do query(ecs.stuff_make(&w), include)

	return sum_x(&w, .A)
}

system :: proc(s: ^Sampler, n: int) -> f64 {
	w: World
	make_full(&w, n)
	defer ecs.world_destroy(&w)
	update :: proc(stuff: Stuff) {query(stuff, {.A, .B})}
	ecs.world_schedule(&w, update, "update", .Update, {.B}, {.A})

	for repeated(s, n) do ecs.world_run_sync(&w)

	return sum_x(&w, .A)
}

baseline :: proc(s: ^Sampler, n: int) -> f64 {
	w: World
	make_full(&w, n)
	defer ecs.world_destroy(&w)

	for repeated(s, n) {
		for &a in ecs.write_parts(&w, .A, Part) do a.x += 1
	}

	return sum_x(&w, .A)
}

// >--------------------------------------------------------------------- Access

// The j-th thing in spawn order, or in shuffled order. rand is a constant at every call, so the
// branch folds away.
handle :: #force_inline proc(rand: bool, j: int) -> Thing {
	return rand ? things[perm[j]] : things[j]
}

get_1 :: proc(s: ^Sampler, n: int, $rand: bool) -> f64 {
	w: World
	make_full(&w, n)
	defer ecs.world_destroy(&w)

	sum: f64
	for repeated(s, n) {
		for j in 0 ..< n {
			a, _ := ecs.get_part(&w, handle(rand, j), .A, Part)
			sum += f64(a.x)
		}
	}

	return sum
}

get_4 :: proc(s: ^Sampler, n: int, $rand: bool) -> f64 {
	w: World
	make_full(&w, n)
	defer ecs.world_destroy(&w)

	sum: f64
	for repeated(s, n) {
		for j in 0 ..< n {
			t := handle(rand, j)
			a, _ := ecs.get_part(&w, t, .A, Part)
			b, _ := ecs.get_part(&w, t, .B, Part)
			c, _ := ecs.get_part(&w, t, .C, Part)
			d, _ := ecs.get_part(&w, t, .D, Part)
			sum += f64(a.x + b.x + c.x + d.x)
		}
	}

	return sum
}

write_1 :: proc(s: ^Sampler, n: int, $rand: bool) -> f64 {
	w: World
	make_full(&w, n)
	defer ecs.world_destroy(&w)

	for repeated(s, n) {
		for j in 0 ..< n do ecs.write_part(&w, handle(rand, j), .A, Part).x += 1
	}

	return sum_x(&w, .A)
}

has :: proc(s: ^Sampler, n: int, $rand: bool) -> f64 {
	w: World
	make_sparse(&w, n, 500)
	defer ecs.world_destroy(&w)

	count: f64
	for repeated(s, n) {
		for j in 0 ..< n do if ecs.has(&w, handle(rand, j), .B) do count += 1
	}

	return count
}

alive :: proc(s: ^Sampler, n: int, $rand: bool) -> f64 {
	w: World
	make_full(&w, n)
	defer ecs.world_destroy(&w)
	for i := 0; i < n; i += 2 do ecs.kill_now(&w, things[i])

	count: f64
	for repeated(s, n) {
		for j in 0 ..< n do if ecs.is_alive(&w, handle(rand, j)) do count += 1
	}

	return count
}

// >---------------------------------------------------------------------- Churn

FRAMES :: 100

churn_frame :: proc(w: ^World, n, frame: int) {
	per := n / FRAMES
	first := frame * per

	for j in first ..< first + per do ecs.kill_now(w, things[perm[j]])

	for j in first ..< first + per {
		t := ecs.spawn(w)
		ecs.set_now(w, t, .A, PART)
		ecs.set_now(w, t, .B, PART)
		ecs.set_now(w, t, .C, PART)
		ecs.set_now(w, t, .D, PART)
		things[perm[j]] = t
	}

	query(ecs.stuff_make(w), {.A, .B})
}

churn_frames :: proc(s: ^Sampler, n: int) -> f64 {
	w: World
	make_full(&w, n)
	defer ecs.world_destroy(&w)

	for timed(s, FRAMES) {
		for frame in 0 ..< FRAMES do churn_frame(&w, n, frame)
	}

	return sum_x(&w, .A)
}

churn_after :: proc(s: ^Sampler, n: int) -> f64 {
	w: World
	make_full(&w, n)
	defer ecs.world_destroy(&w)
	for frame in 0 ..< FRAMES do churn_frame(&w, n, frame)

	for repeated(s, n) do query(ecs.stuff_make(&w), {.A, .B})

	return sum_x(&w, .A)
}

// >---------------------------------------------------------------------- Cases

// odinfmt: disable
flat_cases := []Case {
	{"lifecycle", "spawn.0", proc(s: ^Sampler, n: int) -> f64 {return spawn_case(s, n, {})}},
	{"lifecycle", "spawn.1", proc(s: ^Sampler, n: int) -> f64 {return spawn_case(s, n, {.A})}},
	{"lifecycle", "spawn.2", proc(s: ^Sampler, n: int) -> f64 {return spawn_case(s, n, {.A, .B})}},
	{"lifecycle", "spawn.3", proc(s: ^Sampler, n: int) -> f64 {return spawn_case(s, n, {.A, .B, .C})}},
	{"lifecycle", "spawn.4", proc(s: ^Sampler, n: int) -> f64 {return spawn_case(s, n, {.A, .B, .C, .D})}},
	{"lifecycle", "kill", kill},
	{"lifecycle", "kill.later", kill_later},

	{"structure", "add.tag", add_tag},
	{"structure", "add.tag.later", add_tag_later},
	{"structure", "remove.tag", remove_tag},
	{"structure", "add.D", add_d},
	{"structure", "remove.D", remove_d},

	{"query", "uniform.1", proc(s: ^Sampler, n: int) -> f64 {return uniform(s, n, {.A})}},
	{"query", "uniform.2", proc(s: ^Sampler, n: int) -> f64 {return uniform(s, n, {.A, .B})}},
	{"query", "uniform.3", proc(s: ^Sampler, n: int) -> f64 {return uniform(s, n, {.A, .B, .C})}},
	{"query", "uniform.4", proc(s: ^Sampler, n: int) -> f64 {return uniform(s, n, {.A, .B, .C, .D})}},
	{"query", "exclude", exclude},
	{"query", "sparse.10", proc(s: ^Sampler, n: int) -> f64 {return sparse(s, n, 10)}},
	{"query", "sparse.100", proc(s: ^Sampler, n: int) -> f64 {return sparse(s, n, 100)}},
	{"query", "sparse.500", proc(s: ^Sampler, n: int) -> f64 {return sparse(s, n, 500)}},
	{"query", "fragmented.1", proc(s: ^Sampler, n: int) -> f64 {return fragmented(s, n, {.A})}},
	{"query", "fragmented.2", proc(s: ^Sampler, n: int) -> f64 {return fragmented(s, n, {.A, .B})}},
	{"query", "system", system},
	{"query", "baseline", baseline},

	{"access", "get.1.seq", proc(s: ^Sampler, n: int) -> f64 {return get_1(s, n, false)}},
	{"access", "get.1.rand", proc(s: ^Sampler, n: int) -> f64 {return get_1(s, n, true)}},
	{"access", "get.4.seq", proc(s: ^Sampler, n: int) -> f64 {return get_4(s, n, false)}},
	{"access", "get.4.rand", proc(s: ^Sampler, n: int) -> f64 {return get_4(s, n, true)}},
	{"access", "write.1.seq", proc(s: ^Sampler, n: int) -> f64 {return write_1(s, n, false)}},
	{"access", "write.1.rand", proc(s: ^Sampler, n: int) -> f64 {return write_1(s, n, true)}},
	{"access", "has.seq", proc(s: ^Sampler, n: int) -> f64 {return has(s, n, false)}},
	{"access", "has.rand", proc(s: ^Sampler, n: int) -> f64 {return has(s, n, true)}},
	{"access", "alive.seq", proc(s: ^Sampler, n: int) -> f64 {return alive(s, n, false)}},
	{"access", "alive.rand", proc(s: ^Sampler, n: int) -> f64 {return alive(s, n, true)}},

	{"churn", "frames", churn_frames},
	{"churn", "after", churn_after},
}
// odinfmt: enable
