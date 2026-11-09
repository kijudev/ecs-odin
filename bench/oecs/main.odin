package bench

import "core:fmt"
import "core:time"

import ecs "../ecs"

// Quick, uncommitted benchmark. Run with:
//   odin run bench -o:speed
//   odin run bench -o:speed -disable-assert

Kind :: enum {
	Position,
	Velocity,
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

Vec :: struct {
	x, y: f32,
}

Tag :: struct {}

N :: 100_000
RUNS :: 5

// Results are summed in here so the lookups can't be optimized away.
@(thread_local)
sink: f32

// >-------------------------------------------------------------------- Harness

make_world :: proc(world: ^World) {
	ecs.world_init(world, {capacity = 1 << 18, cmd_capacity = N * 2, cmd_parts_capacity = N * 32})
	ecs.register_part(world, .Position, Vec)
	ecs.register_part(world, .Velocity, Vec)
	ecs.register_part(world, .Tag, Tag)
	ecs.register_part(world, .Local, Vec)
	ecs.register_part(world, .Global, Vec)
	ecs.register_hierarchy(world, .Transform)
}

@(thread_local)
things: [N]ecs.Thing

spawn_all :: proc(world: ^World) {
	for i in 0 ..< N do things[i] = ecs.spawn(world)
}

with_parts :: proc(world: ^World) {
	spawn_all(world)
	for thing in things {
		ecs.set_now(world, thing, .Position, Vec{1, 2})
		ecs.set_now(world, thing, .Velocity, Vec{3, 4})
	}
}

// A single 4-ary tree over every thing, depth ~8.
with_tree :: proc(world: ^World) {
	spawn_all(world)
	for i in 1 ..< N do ecs.attach_now(world, .Transform, things[i], things[(i - 1) / 4])
	for thing in things {
		ecs.set_now(world, thing, .Local, Vec{1, 1})
		ecs.set_now(world, thing, .Global, Vec{})
	}
	ecs.world_rebuild_hierarchy(world, .Transform)
}

Case :: struct {
	name:  string,
	ops:   int,
	setup: proc(world: ^World),
	run:   proc(world: ^World),
}

measure :: proc(c: Case) {
	best := max(time.Duration)
	total: time.Duration

	for _ in 0 ..< RUNS {
		world: World
		make_world(&world)
		if c.setup != nil do c.setup(&world)

		start := time.tick_now()
		c.run(&world)
		took := time.tick_since(start)

		ecs.world_destroy(&world)
		best = min(best, took)
		total += took
	}

	fmt.printfln(
		"  %-44s %8s ms  (avg %8s ms)  %7s ns/op",
		c.name,
		fmt.tprintf("%.2f", time.duration_milliseconds(best)),
		fmt.tprintf("%.2f", time.duration_milliseconds(total / RUNS)),
		fmt.tprintf("%.1f", f64(best) / f64(c.ops)),
	)
}

// >---------------------------------------------------------------------- Cases

spawn_case :: proc(world: ^World) {spawn_all(world)}

set_now_case :: proc(world: ^World) {
	for thing in things {
		ecs.set_now(world, thing, .Position, Vec{1, 2})
		ecs.set_now(world, thing, .Velocity, Vec{3, 4})
	}
}

set_later_case :: proc(world: ^World) {
	for thing in things {
		ecs.set_later(world, thing, .Position, Vec{1, 2})
		ecs.set_later(world, thing, .Velocity, Vec{3, 4})
	}
	ecs.world_apply(world)
}

set_later_record_case :: proc(world: ^World) {
	for thing in things {
		ecs.set_later(world, thing, .Position, Vec{1, 2})
		ecs.set_later(world, thing, .Velocity, Vec{3, 4})
	}
}

query_case :: proc(world: ^World) {
	query := ecs.query_make(ecs.stuff_make(world), {.Position, .Velocity}, {})
	for _ in ecs.query_iter(&query) {
		pos := ecs.write_part(&query, .Position, Vec)
		vel := ecs.get_part(&query, .Velocity, Vec)
		pos.x += vel.x
		pos.y += vel.y
	}
}

move_system :: proc(stuff: Stuff) {
	query := ecs.query_make(stuff, {.Position, .Velocity}, {})
	for _ in ecs.query_iter(&query) {
		pos := ecs.write_part(&query, .Position, Vec)
		vel := ecs.get_part(&query, .Velocity, Vec)
		pos.x += vel.x
		pos.y += vel.y
	}
}

query_system_case :: proc(world: ^World) {
	ecs.world_schedule(world, move_system, "move", .Update, {.Velocity}, {.Position})
	ecs.world_run_sync(world)
}

query_one_case :: proc(world: ^World) {
	query := ecs.query_make(ecs.stuff_make(world), {.Velocity}, {})
	for _ in ecs.query_iter(&query) {
		vel := ecs.write_part(&query, .Velocity, Vec)
		vel.x += 1
		vel.y += 1
	}
}

query_exclude_case :: proc(world: ^World) {
	query := ecs.query_make(ecs.stuff_make(world), {.Position, .Velocity}, {.Tag})
	for _ in ecs.query_iter(&query) {
		pos := ecs.write_part(&query, .Position, Vec)
		vel := ecs.get_part(&query, .Velocity, Vec)
		pos.x += vel.x
		pos.y += vel.y
	}
}

slice_case :: proc(world: ^World) {
	for &vel in ecs.write_parts(world, .Velocity, Vec) {
		vel.x += 1
		vel.y += 1
	}
}

add_now_case :: proc(world: ^World) {
	for thing in things do ecs.add_now(world, thing, .Tag)
}

add_later_case :: proc(world: ^World) {
	for thing in things do ecs.add_later(world, thing, .Tag)
	ecs.world_apply(world)
}

with_tags :: proc(world: ^World) {
	with_parts(world)
	for thing in things do ecs.add_now(world, thing, .Tag)
}

remove_now_case :: proc(world: ^World) {
	for thing in things do ecs.remove_now(world, thing, .Tag)
}

remove_later_case :: proc(world: ^World) {
	for thing in things do ecs.remove_later(world, thing, .Tag)
	ecs.world_apply(world)
}

kill_now_case :: proc(world: ^World) {
	for thing in things do ecs.kill_now(world, thing)
}

kill_later_case :: proc(world: ^World) {
	for thing in things do ecs.kill_later(world, thing)
	ecs.world_apply(world)
}

attach_now_case :: proc(world: ^World) {
	for i in 1 ..< N do ecs.attach_now(world, .Transform, things[i], things[(i - 1) / 4])
}

attach_later_case :: proc(world: ^World) {
	for i in 1 ..< N do ecs.attach_later(world, .Transform, things[i], things[(i - 1) / 4])
	ecs.world_apply(world)
}

rebuild_case :: proc(world: ^World) {
	ecs.world_rebuild_hierarchy(world, .Transform)
}

propagate_case :: proc(world: ^World) {
	query := ecs.hierarchy_query_make(ecs.stuff_make(world), .Transform, {.Local, .Global}, {})
	for _ in ecs.hierarchy_query_iter(&query) {
		local := ecs.get_part(&query, .Local, Vec)
		global := ecs.write_part(&query, .Global, Vec)
		parent, has_parent := ecs.hierarchy_query_get_parent_part(&query, .Global, Vec)
		global^ = has_parent ? Vec{parent.x + local.x, parent.y + local.y} : local
	}
}

kill_tree_whole_now_case :: proc(world: ^World) {
	ecs.kill_tree_now(world, .Transform, things[0])
}

kill_tree_whole_later_case :: proc(world: ^World) {
	ecs.kill_tree_later(world, .Transform, things[0])
	ecs.world_apply(world)
}

// The last 1000 parents of the tree: each has up to 4 leaf children.
SMALL_TREES :: 1000
SMALL_TREES_FIRST :: (N - 1) / 4 - SMALL_TREES

kill_tree_small_now_case :: proc(world: ^World) {
	for i in 0 ..< SMALL_TREES {
		ecs.kill_tree_now(world, .Transform, things[SMALL_TREES_FIRST + i])
	}
}

kill_tree_small_later_case :: proc(world: ^World) {
	for i in 0 ..< SMALL_TREES {
		ecs.kill_tree_later(world, .Transform, things[SMALL_TREES_FIRST + i])
	}
	ecs.world_apply(world)
}

get_part_case :: proc(world: ^World) {
	for thing in things {
		pos, _ := ecs.get_part(world, thing, .Position, Vec)
		sink += pos.x
	}
}

write_part_case :: proc(world: ^World) {
	for thing in things do ecs.write_part(world, thing, .Position, Vec).x += 1
}

has_case :: proc(world: ^World) {
	for thing in things do if ecs.has(world, thing, .Velocity) do sink += 1
}

is_alive_case :: proc(world: ^World) {
	for thing in things do if ecs.is_alive(world, thing) do sink += 1
}

lookup_system :: proc(stuff: Stuff) {
	for thing in things {
		pos, _ := ecs.get_part(stuff, thing, .Position, Vec)
		ecs.write_part(stuff, thing, .Velocity, Vec).x += pos.x
	}
}

lookup_system_case :: proc(world: ^World) {
	ecs.world_schedule(world, lookup_system, "lookup", .Update, {.Position}, {.Velocity})
	ecs.world_run_sync(world)
}

get_parent_case :: proc(world: ^World) {
	for thing in things do sink += f32(ecs.get_parent(world, .Transform, thing).idx)
}

iter_children_case :: proc(world: ^World) {
	for thing in things {
		children := ecs.iter_children(world, .Transform, thing)
		for child in ecs.hierarchy_children_iter(&children) do sink += f32(child.idx)
	}
}

// >----------------------------------------------------------------------- Main

main :: proc() {
	when ODIN_DISABLE_ASSERT {
		fmt.printfln("ecs bench, %v things, best of %v runs, asserts OFF", N, RUNS)
	} else {
		fmt.printfln("ecs bench, %v things, best of %v runs, asserts ON", N, RUNS)
	}

	fmt.println("\nthings")
	measure({"spawn", N, nil, spawn_case})
	measure({"kill_now", N, with_parts, kill_now_case})
	measure({"kill_later + apply", N, with_parts, kill_later_case})

	fmt.println("\nparts (2 per thing)")
	measure({"set_now", 2 * N, spawn_all, set_now_case})
	measure({"set_later record only", 2 * N, spawn_all, set_later_record_case})
	measure({"set_later + apply", 2 * N, spawn_all, set_later_case})
	measure({"add_now tag", N, with_parts, add_now_case})
	measure({"add_later tag + apply", N, with_parts, add_later_case})
	measure({"remove_now tag", N, with_tags, remove_now_case})
	measure({"remove_later tag + apply", N, with_tags, remove_later_case})

	fmt.println("\niteration (pos += vel)")
	measure({"query, unrestricted stuff", N, with_parts, query_case})
	measure({"query, in a system (access checked)", N, with_parts, query_system_case})
	measure({"query, 1 part", N, with_parts, query_one_case})
	measure({"query, 2 parts, exclude Tag", N, with_parts, query_exclude_case})
	measure({"write_parts slice, 1 part (baseline)", N, with_parts, slice_case})

	fmt.println("\npoint lookups by handle")
	measure({"get_part (world)", N, with_parts, get_part_case})
	measure({"write_part (world)", N, with_parts, write_part_case})
	measure({"has (world)", N, with_parts, has_case})
	measure({"is_alive (world)", N, with_parts, is_alive_case})
	measure({"get_part + write_part in a system", N, with_parts, lookup_system_case})
	measure({"get_parent", N, with_tree, get_parent_case})
	measure({"iter_children, every thing", N, with_tree, iter_children_case})

	fmt.println("\nhierarchy (one 4-ary tree)")
	measure({"attach_now", N - 1, spawn_all, attach_now_case})
	measure({"attach_later + apply", N - 1, spawn_all, attach_later_case})
	measure({"rebuild", N, with_tree, rebuild_case})
	measure({"hierarchy query propagate", N, with_tree, propagate_case})
	measure({"kill_tree_now whole tree", N, with_tree, kill_tree_whole_now_case})
	measure({"kill_tree_later whole tree + apply", N, with_tree, kill_tree_whole_later_case})
	measure(
		{"kill_tree_now 1000 small subtrees", SMALL_TREES, with_tree, kill_tree_small_now_case},
	)
	measure(
		{"kill_tree_later 1000 small + apply", SMALL_TREES, with_tree, kill_tree_small_later_case},
	)
}
