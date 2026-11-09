package ecs_tests

import "core:mem"
import "core:testing"

import ecs "../ecs"

@(private = "file")
make_world :: proc(world: ^World) {
	ecs.world_init(world, {capacity = ecs.THING_POOL_MIN_CAPACITY})
	ecs.register_part(world, .Position, Position)
	ecs.register_part(world, .Velocity, Velocity)
	ecs.register_part(world, .Tag, Tag)
	ecs.register_stash(world, .Time, Time)
}

// Every call goes through the short names with a Stuff, so this also checks that the groups
// pick the stuff procs.

// >--------------------------------------------------------------------- Things

@(test)
stuff_spawns_and_kills_in_the_world :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	stuff := ecs.stuff_make(&world)

	a := ecs.spawn(stuff)
	b := ecs.spawn(stuff)
	testing.expect(t, ecs.is_alive(stuff, a))
	testing.expect(t, ecs.world_is_alive(&world, b))
	testing.expect_value(t, ecs.count_alive(stuff), 2)

	testing.expect(t, ecs.kill_now(stuff, a))
	testing.expect(t, !ecs.kill_now(stuff, a))
	testing.expect(t, !ecs.is_alive(stuff, a))
	testing.expect_value(t, ecs.count_free(stuff), 1)

	ecs.kill_later(stuff, b)
	testing.expect(t, ecs.is_alive(stuff, b))
	ecs.world_apply(&world)
	testing.expect(t, !ecs.is_alive(stuff, b))
	testing.expect_value(t, ecs.count_alive(stuff), 0)
	testing.expect_value(t, ecs.count_free(stuff), 2)
}

// >---------------------------------------------------------------------- Parts

@(test)
stuff_now_procs_change_the_world :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	stuff := ecs.stuff_make(&world)

	thing := ecs.spawn(stuff)
	pos := ecs.set_now(stuff, thing, .Position, Position{1, 2})
	testing.expect(t, pos == ecs.world_write_part(&world, thing, .Position, Position))
	testing.expect(t, pos == ecs.write_part(stuff, thing, .Position, Position))
	expect_part(t, &world, thing, .Position, Position{1, 2})

	vel := Velocity{3, 4}
	testing.expect_value(t, ecs.set_now(stuff, thing, .Velocity, &vel)^, vel)
	testing.expect_value(t, ecs.set_now(stuff, thing, .Velocity, Velocity)^, Velocity{})

	testing.expect(t, ecs.add_now(stuff, thing, .Tag))
	testing.expect(t, ecs.has(stuff, thing, .Tag))
	testing.expect(t, ecs.remove_now(stuff, thing, .Tag))
	testing.expect(t, !ecs.world_has(&world, thing, .Tag))

	testing.expect_value(t, ecs.count_parts(stuff, .Position), 1)
	testing.expect_value(t, len(ecs.get_parts(stuff, .Position, Position)), 1)
	testing.expect_value(t, ecs.get_parts(stuff, .Position, Position)[0], Position{1, 2})
	testing.expect_value(t, ecs.get_things(stuff, .Position)[0], thing)
}

@(test)
stuff_later_procs_record_into_the_world :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	stuff := ecs.stuff_make(&world)

	a := ecs.spawn(stuff)
	b := ecs.spawn(stuff)
	ecs.add_now(stuff, b, .Tag)

	vel := Velocity{3, 4}
	ecs.set_later(stuff, a, .Position, Position{1, 2})
	ecs.set_later(stuff, a, .Velocity, &vel)
	ecs.set_later(stuff, b, .Position, Position)
	ecs.add_later(stuff, a, .Tag)
	ecs.remove_later(stuff, b, .Tag)

	testing.expect_value(t, ecs.world_count_cmds(&world), 5)
	testing.expect(t, !ecs.has(stuff, a, .Position))

	ecs.world_apply(&world)
	expect_part(t, &world, a, .Position, Position{1, 2})
	expect_part(t, &world, a, .Velocity, vel)
	expect_part(t, &world, b, .Position, Position{})
	testing.expect(t, ecs.has(stuff, a, .Tag))
	testing.expect(t, !ecs.has(stuff, b, .Tag))
}

// >-------------------------------------------------------------------- Stashes

@(test)
stuff_get_stash_is_the_worlds :: proc(t: ^testing.T) {
	world: World
	make_world(&world)
	defer ecs.world_destroy(&world)
	stuff := ecs.stuff_make(&world)

	time := ecs.write_stash(stuff, .Time, Time)
	testing.expect(t, time == ecs.write_stash(&world, .Time, Time))

	time.delta = 0.5
	testing.expect_value(t, ecs.get_stash(stuff, .Time, Time), Time{0.5, 0})
}

// >--------------------------------------------------------------------- Access

// The things the access systems below work on: a has Position and Velocity, b is its Transform
// child with Position and Tag.
@(private = "file", thread_local)
access_things: [2]ecs.Thing

@(private = "file")
make_access_world :: proc(world: ^World, allocator := context.allocator) {
	ecs.world_init(
		world,
		{
			capacity = ecs.THING_POOL_MIN_CAPACITY,
			stash_capacity = 64,
			static_allocator = allocator,
			dynamic_allocator = allocator,
		},
	)
	ecs.register_part(world, .Position, Position)
	ecs.register_part(world, .Velocity, Velocity)
	ecs.register_part(world, .Tag, Tag)
	ecs.register_stash(world, .Time, Time)
	ecs.register_hierarchy(world, .Transform)

	a, b := ecs.spawn(world), ecs.spawn(world)
	ecs.set_now(world, a, .Position, Position{1, 2})
	ecs.set_now(world, a, .Velocity, Velocity{3, 4})
	ecs.set_now(world, b, .Position, Position{5, 6})
	ecs.add_now(world, b, .Tag)
	ecs.attach_now(world, .Transform, b, a)
	ecs.world_rebuild_hierarchy(world, .Transform)
	access_things = {a, b}
}

@(private = "file")
access_everything_system :: proc(stuff: Stuff) {
	a, b := access_things[0], access_things[1]

	// Reads, some covered only by writes.
	_ = ecs.has(stuff, a, .Velocity)
	_, _ = ecs.get_part(stuff, a, .Position, Position)
	_ = ecs.get_parts(stuff, .Velocity, Velocity)
	_ = ecs.get_things(stuff, .Position)
	_ = ecs.count_parts(stuff, .Tag)
	_ = ecs.get_stash(stuff, .Time, Time)
	_ = ecs.get_parent(stuff, .Transform, b)
	_ = ecs.get_first_child(stuff, .Transform, a)
	_ = ecs.get_next_sibling(stuff, .Transform, b)
	children := ecs.iter_children(stuff, .Transform, a)
	for _ in ecs.hierarchy_children_iter(&children) {}
	roots := ecs.iter_roots(stuff, .Transform)
	for _ in ecs.hierarchy_children_iter(&roots) {}
	_ = ecs.is_ancestor(stuff, .Transform, a, b)
	_ = ecs.get_hierarchy_order(stuff, .Transform)
	_ = ecs.get_hierarchy_depths(stuff, .Transform)
	_ = ecs.get_hierarchy_ends(stuff, .Transform)
	_ = ecs.get_subtree(stuff, .Transform, a)

	query := ecs.query_make_hierarchy(stuff, .Transform, {.Position}, {.Velocity})
	for _ in ecs.query_iter(&query) {
		_ = ecs.get_part(&query, .Position, Position)
		_, _ = ecs.query_get_parent_part(&query, .Position, Position)
		ecs.write_part(&query, .Position, Position).x += 1
	}

	// Writes.
	ecs.write_part(stuff, a, .Velocity, Velocity).y += 1
	_ = ecs.write_parts(stuff, .Position, Position)
	ecs.write_stash(stuff, .Time, Time).delta = 0.5
	c := ecs.spawn(stuff)
	ecs.set_now(stuff, c, .Position, Position{})
	ecs.add_now(stuff, c, .Tag)
	ecs.remove_now(stuff, c, .Tag)
	ecs.attach_now(stuff, .Transform, c, b)
	ecs.detach_now(stuff, .Transform, c)
	ecs.kill_now(stuff, c)
	ecs.kill_tree_now(stuff, .Transform, a)

	append(&system_log, 40)
}

@(test)
access_declared_system_reaches_everything :: proc(t: ^testing.T) {
	world: World
	make_access_world(&world)
	defer ecs.world_destroy(&world)

	ecs.world_schedule(
		&world,
		access_everything_system,
		"access_everything_system",
		.Update,
		{},
		{.Position, .Velocity, .Tag, .Transform, .Time},
	)
	clear(&system_log)
	ecs.world_run_sync(&world)

	testing.expect_value(t, system_log_count(40), 1)
	testing.expect_value(t, ecs.world_get_stash(&world, .Time, Time).delta, 0.5)
	testing.expect_value(t, ecs.world_count_alive(&world), 0)
}

@(private = "file")
access_reads_system :: proc(stuff: Stuff) {
	a, b := access_things[0], access_things[1]

	_, _ = ecs.get_part(stuff, a, .Position, Position)
	_ = ecs.get_stash(stuff, .Time, Time)
	_ = ecs.get_parent(stuff, .Transform, b)

	query := ecs.query_make_hierarchy(stuff, .Transform, {.Position}, {})
	for _ in ecs.query_iter(&query) do _ = ecs.get_part(&query, .Position, Position)

	append(&system_log, 42)
}

@(test)
access_reads_only_system_reads :: proc(t: ^testing.T) {
	world: World
	make_access_world(&world)
	defer ecs.world_destroy(&world)

	ecs.world_schedule(
		&world,
		access_reads_system,
		"access_reads_system",
		.Update,
		{.Position, .Time, .Transform},
		{},
	)
	clear(&system_log)
	ecs.world_run_sync(&world)

	testing.expect_value(t, system_log_count(42), 1)
}

@(private = "file")
access_later_system :: proc(stuff: Stuff) {
	a, b := access_things[0], access_things[1]

	ecs.set_later(stuff, a, .Position, Position{9, 9})
	ecs.add_later(stuff, a, .Tag)
	ecs.remove_later(stuff, b, .Tag)
	ecs.detach_later(stuff, .Transform, b)
	ecs.attach_later(stuff, .Transform, a, b)
	ecs.kill_tree_later(stuff, .Transform, b)
	ecs.kill_later(stuff, a)
	append(&system_log, 41)
}

@(test)
access_later_procs_need_no_declaration :: proc(t: ^testing.T) {
	world: World
	make_access_world(&world)
	defer ecs.world_destroy(&world)

	ecs.world_schedule(&world, access_later_system, "access_later_system", .Update, {}, {})
	clear(&system_log)
	ecs.world_run_sync(&world)

	testing.expect_value(t, system_log_count(41), 1)
	testing.expect_value(t, ecs.world_count_cmds(&world), 7)

	ecs.world_apply(&world)
	testing.expect_value(t, ecs.world_count_alive(&world), 0)
}

@(test)
restricted_stuff_allows_what_it_declares :: proc(t: ^testing.T) {
	world: World
	make_access_world(&world)
	defer ecs.world_destroy(&world)
	a := access_things[0]

	stuff := ecs.stuff_make_restricted(
		&world,
		{name = "manual", reads = {.Position}, writes = {.Velocity}},
	)
	pos, ok := ecs.get_part(stuff, a, .Position, Position)
	testing.expect(t, ok)
	testing.expect_value(t, pos, Position{1, 2})

	ecs.write_part(stuff, a, .Velocity, Velocity).x = 7
	expect_part(t, &world, a, .Velocity, Velocity{7, 4})
}

@(test)
zero_stuff_has_full_access :: proc(t: ^testing.T) {
	world: World
	make_access_world(&world)
	defer ecs.world_destroy(&world)
	a := access_things[0]

	stuff := Stuff {
		world = &world,
	}
	ecs.write_part(stuff, a, .Position, Position).x = 7
	ecs.write_stash(stuff, .Time, Time).delta = 1
	expect_part(t, &world, a, .Position, Position{7, 2})

	// Kills check the whole footprint, which an unrestricted stuff skips too.
	testing.expect(t, ecs.kill_now(stuff, access_things[1]))
	testing.expect(t, ecs.kill_tree_now(stuff, .Transform, a))
	testing.expect_value(t, ecs.world_count_alive(&world), 0)
}

@(test)
get_part_returns_a_copy :: proc(t: ^testing.T) {
	world: World
	make_access_world(&world)
	defer ecs.world_destroy(&world)
	stuff := ecs.stuff_make(&world)
	a, b := access_things[0], access_things[1]

	pos, ok := ecs.get_part(stuff, a, .Position, Position)
	testing.expect(t, ok)
	pos.x = 100
	expect_part(t, &world, a, .Position, Position{1, 2})

	ecs.write_part(stuff, a, .Position, Position).x = 100
	expect_part(t, &world, a, .Position, Position{100, 2})

	_, ok = ecs.get_part(stuff, b, .Velocity, Velocity)
	testing.expect(t, !ok)
	testing.expect(t, ecs.write_part(stuff, b, .Velocity, Velocity) == nil)

	time := ecs.get_stash(stuff, .Time, Time)
	time.delta = 1
	testing.expect_value(t, ecs.get_stash(stuff, .Time, Time), Time{})
}

@(private = "file")
access_get_part_undeclared_system :: proc(stuff: Stuff) {
	_, _ = ecs.get_part(stuff, access_things[0], .Position, Position)
}

@(test)
access_get_part_undeclared_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_access_world(&world, mem.arena_allocator(&arena))
	ecs.world_schedule(&world, access_get_part_undeclared_system, "sys", .Update, {.Velocity}, {})

	testing.expect_assert_message(t, "System sys reads Position without declaring it.")
	ecs.world_run_sync(&world)
	testing.fail_now(t, "The call did not assert.")
}

@(private = "file")
access_get_stash_undeclared_system :: proc(stuff: Stuff) {
	_ = ecs.get_stash(stuff, .Time, Time)
}

@(test)
access_get_stash_undeclared_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_access_world(&world, mem.arena_allocator(&arena))
	ecs.world_schedule(&world, access_get_stash_undeclared_system, "sys", .Update, {}, {.Position})

	testing.expect_assert_message(t, "System sys reads Time without declaring it.")
	ecs.world_run_sync(&world)
	testing.fail_now(t, "The call did not assert.")
}

@(private = "file")
access_hierarchy_link_read_undeclared_system :: proc(stuff: Stuff) {
	_ = ecs.get_parent(stuff, .Transform, access_things[1])
}

@(test)
access_hierarchy_link_read_undeclared_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_access_world(&world, mem.arena_allocator(&arena))
	ecs.world_schedule(
		&world,
		access_hierarchy_link_read_undeclared_system,
		"sys",
		.Update,
		{.Position},
		{},
	)

	testing.expect_assert_message(t, "System sys reads Transform without declaring it.")
	ecs.world_run_sync(&world)
	testing.fail_now(t, "The call did not assert.")
}

@(private = "file")
access_hierarchy_order_read_undeclared_system :: proc(stuff: Stuff) {
	_ = ecs.get_hierarchy_order(stuff, .Transform)
}

@(test)
access_hierarchy_order_read_undeclared_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_access_world(&world, mem.arena_allocator(&arena))
	ecs.world_schedule(
		&world,
		access_hierarchy_order_read_undeclared_system,
		"sys",
		.Update,
		{},
		{},
	)

	testing.expect_assert_message(t, "System sys reads Transform without declaring it.")
	ecs.world_run_sync(&world)
	testing.fail_now(t, "The call did not assert.")
}

@(private = "file")
access_write_part_only_read_system :: proc(stuff: Stuff) {
	ecs.write_part(stuff, access_things[0], .Position, Position).x = 0
}

@(test)
access_write_part_only_read_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_access_world(&world, mem.arena_allocator(&arena))
	ecs.world_schedule(&world, access_write_part_only_read_system, "sys", .Update, {.Position}, {})

	testing.expect_assert_message(t, "System sys writes Position without declaring it in writes.")
	ecs.world_run_sync(&world)
	testing.fail_now(t, "The call did not assert.")
}

@(private = "file")
access_write_stash_only_read_system :: proc(stuff: Stuff) {
	ecs.write_stash(stuff, .Time, Time).delta = 0
}

@(test)
access_write_stash_only_read_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_access_world(&world, mem.arena_allocator(&arena))
	ecs.world_schedule(&world, access_write_stash_only_read_system, "sys", .Update, {.Time}, {})

	testing.expect_assert_message(t, "System sys writes Time without declaring it in writes.")
	ecs.world_run_sync(&world)
	testing.fail_now(t, "The call did not assert.")
}

@(private = "file")
access_set_now_undeclared_system :: proc(stuff: Stuff) {
	ecs.set_now(stuff, access_things[0], .Velocity, Velocity{})
}

@(test)
access_set_now_undeclared_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_access_world(&world, mem.arena_allocator(&arena))
	ecs.world_schedule(
		&world,
		access_set_now_undeclared_system,
		"sys",
		.Update,
		{.Velocity},
		{.Position},
	)

	testing.expect_assert_message(t, "System sys writes Velocity without declaring it in writes.")
	ecs.world_run_sync(&world)
	testing.fail_now(t, "The call did not assert.")
}

@(private = "file")
access_attach_now_undeclared_system :: proc(stuff: Stuff) {
	ecs.attach_now(stuff, .Transform, ecs.spawn(stuff), access_things[0])
}

@(test)
access_attach_now_undeclared_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_access_world(&world, mem.arena_allocator(&arena))
	ecs.world_schedule(
		&world,
		access_attach_now_undeclared_system,
		"sys",
		.Update,
		{.Transform},
		{},
	)

	testing.expect_assert_message(t, "System sys writes Transform without declaring it in writes.")
	ecs.world_run_sync(&world)
	testing.fail_now(t, "The call did not assert.")
}

@(private = "file")
access_query_include_undeclared_system :: proc(stuff: Stuff) {
	_ = ecs.query_make(stuff, {.Position, .Velocity}, {})
}

@(test)
access_query_include_undeclared_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_access_world(&world, mem.arena_allocator(&arena))
	ecs.world_schedule(
		&world,
		access_query_include_undeclared_system,
		"sys",
		.Update,
		{.Position},
		{},
	)

	testing.expect_assert_message(t, "System sys reads Velocity without declaring it.")
	ecs.world_run_sync(&world)
	testing.fail_now(t, "The call did not assert.")
}

@(private = "file")
access_query_exclude_undeclared_system :: proc(stuff: Stuff) {
	_ = ecs.query_make(stuff, {.Position}, {.Tag})
}

@(test)
access_query_exclude_undeclared_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_access_world(&world, mem.arena_allocator(&arena))
	ecs.world_schedule(
		&world,
		access_query_exclude_undeclared_system,
		"sys",
		.Update,
		{.Position},
		{},
	)

	testing.expect_assert_message(t, "System sys reads Tag without declaring it.")
	ecs.world_run_sync(&world)
	testing.fail_now(t, "The call did not assert.")
}

@(private = "file")
access_query_hierarchy_undeclared_system :: proc(stuff: Stuff) {
	_ = ecs.query_make_hierarchy(stuff, .Transform, {.Position}, {})
}

@(test)
access_query_hierarchy_undeclared_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_access_world(&world, mem.arena_allocator(&arena))
	ecs.world_schedule(
		&world,
		access_query_hierarchy_undeclared_system,
		"sys",
		.Update,
		{.Position},
		{},
	)

	testing.expect_assert_message(t, "System sys reads Transform without declaring it.")
	ecs.world_run_sync(&world)
	testing.fail_now(t, "The call did not assert.")
}

@(private = "file")
access_query_write_part_only_read_system :: proc(stuff: Stuff) {
	query := ecs.query_make(stuff, {.Position}, {})
	for _ in ecs.query_iter(&query) do ecs.write_part(&query, .Position, Position).x = 0
}

@(test)
access_query_write_part_only_read_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_access_world(&world, mem.arena_allocator(&arena))
	ecs.world_schedule(
		&world,
		access_query_write_part_only_read_system,
		"sys",
		.Update,
		{.Position},
		{},
	)

	testing.expect_assert_message(t, "System sys writes Position without declaring it in writes.")
	ecs.world_run_sync(&world)
	testing.fail_now(t, "The call did not assert.")
}

@(private = "file")
access_kill_now_undeclared_part_system :: proc(stuff: Stuff) {
	ecs.kill_now(stuff, access_things[0])
}

@(test)
access_kill_now_undeclared_part_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_access_world(&world, mem.arena_allocator(&arena))
	ecs.world_schedule(
		&world,
		access_kill_now_undeclared_part_system,
		"sys",
		.Update,
		{},
		{.Position, .Transform},
	)

	testing.expect_assert_message(
		t,
		"System sys kills thing 1 with part Velocity without declaring it in writes.",
	)
	ecs.world_run_sync(&world)
	testing.fail_now(t, "The call did not assert.")
}

@(private = "file")
access_kill_now_undeclared_hierarchy_system :: proc(stuff: Stuff) {
	ecs.kill_now(stuff, access_things[0])
}

@(test)
access_kill_now_undeclared_hierarchy_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_access_world(&world, mem.arena_allocator(&arena))
	ecs.world_schedule(
		&world,
		access_kill_now_undeclared_hierarchy_system,
		"sys",
		.Update,
		{},
		{.Position, .Velocity},
	)

	testing.expect_assert_message(
		t,
		"System sys kills thing 1 in hierarchy Transform without declaring it in writes.",
	)
	ecs.world_run_sync(&world)
	testing.fail_now(t, "The call did not assert.")
}

@(private = "file")
access_kill_tree_now_undeclared_descendant_system :: proc(stuff: Stuff) {
	ecs.kill_tree_now(stuff, .Transform, access_things[0])
}

@(test)
access_kill_tree_now_undeclared_descendant_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_access_world(&world, mem.arena_allocator(&arena))
	ecs.world_schedule(
		&world,
		access_kill_tree_now_undeclared_descendant_system,
		"sys",
		.Update,
		{},
		{.Position, .Velocity, .Transform},
	)

	testing.expect_assert_message(
		t,
		"System sys kills thing 2 with part Tag without declaring it in writes.",
	)
	ecs.world_run_sync(&world)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
restricted_stuff_asserts_without_a_system :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the pools from an arena instead of the heap.
	@(static) backing: [512 * mem.Kilobyte]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	world: World
	make_access_world(&world, mem.arena_allocator(&arena))
	stuff := ecs.stuff_make_restricted(&world, {name = "manual", reads = {.Position}})

	testing.expect_assert_message(
		t,
		"System manual writes Position without declaring it in writes.",
	)
	ecs.write_part(stuff, access_things[0], .Position, Position)
	testing.fail_now(t, "The call did not assert.")
}
