package ecs_tests

import "core:testing"

import ecs "../ecs"

Position :: struct {
	x, y: f32,
}

Tag :: struct {}

Aligned :: struct #align (64) {
	value: int,
}

@(thread_local)
destroyed_count: int

count_destroyed :: proc(part: rawptr) {
	destroyed_count += 1
}

// >------------------------------------------------------------------ Lifecycle

@(test)
part_pool_init_creates_empty_pool :: proc(t: ^testing.T) {
	pool: ecs.Part_Pool
	ecs.part_pool_init(&pool, type_info_of(Position))
	defer ecs.part_pool_destroy(&pool)

	testing.expect_value(t, ecs.part_pool_count(&pool), 0)
	testing.expect_value(t, ecs.part_pool_capacity(&pool), 0)
}

@(test)
part_pool_reset_removes_all_parts :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	pool: ecs.Part_Pool
	ecs.part_pool_init(&pool, type_info_of(Position), count_destroyed)
	defer ecs.part_pool_destroy(&pool)
	destroyed_count = 0

	a := ecs.thing_pool_spawn(&things)
	b := ecs.thing_pool_spawn(&things)
	ecs.part_pool_insert(&pool, a)
	ecs.part_pool_insert(&pool, b)

	ecs.part_pool_reset(&pool)

	testing.expect_value(t, destroyed_count, 2)
	testing.expect_value(t, ecs.part_pool_count(&pool), 0)
	testing.expect(t, !ecs.part_pool_has(&pool, a))
	testing.expect(t, !ecs.part_pool_has(&pool, b))

	// Pool is usable again after reset.
	ecs.part_pool_insert(&pool, a)
	testing.expect(t, ecs.part_pool_has(&pool, a))
}

@(test)
part_pool_destroy_destroys_parts :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	pool: ecs.Part_Pool
	ecs.part_pool_init(&pool, type_info_of(Position), count_destroyed)
	destroyed_count = 0

	ecs.part_pool_insert(&pool, ecs.thing_pool_spawn(&things))
	ecs.part_pool_insert(&pool, ecs.thing_pool_spawn(&things))
	ecs.part_pool_destroy(&pool)

	testing.expect_value(t, destroyed_count, 2)
}

// >--------------------------------------------------------------------- Insert

@(test)
part_pool_insert_copies_part :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	pool: ecs.Part_Pool
	ecs.part_pool_init(&pool, type_info_of(Position))
	defer ecs.part_pool_destroy(&pool)

	thing := ecs.thing_pool_spawn(&things)
	value := Position{1, 2}
	ecs.part_pool_insert(&pool, thing, &value)
	value = {}

	part := (^Position)(ecs.part_pool_get(&pool, thing))
	testing.expect(t, part != nil)
	testing.expect_value(t, part^, Position{1, 2})
	testing.expect_value(t, ecs.part_pool_count(&pool), 1)
}

@(test)
part_pool_insert_nil_zero_initialises :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	pool: ecs.Part_Pool
	ecs.part_pool_init(&pool, type_info_of(Position))
	defer ecs.part_pool_destroy(&pool)

	a := ecs.thing_pool_spawn(&things)
	b := ecs.thing_pool_spawn(&things)

	value := Position{1, 2}
	ecs.part_pool_insert(&pool, a, &value)
	ecs.part_pool_remove(&pool, a) // leaves old bytes in the freed slot
	part := (^Position)(ecs.part_pool_insert(&pool, b))

	testing.expect_value(t, part^, Position{})
}

@(test)
part_pool_insert_existing_overwrites :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	pool: ecs.Part_Pool
	ecs.part_pool_init(&pool, type_info_of(Position), count_destroyed)
	defer ecs.part_pool_destroy(&pool)
	destroyed_count = 0

	thing := ecs.thing_pool_spawn(&things)
	first := Position{1, 2}
	second := Position{3, 4}
	ecs.part_pool_insert(&pool, thing, &first)
	ecs.part_pool_insert(&pool, thing, &second)

	testing.expect_value(t, destroyed_count, 1)
	testing.expect_value(t, ecs.part_pool_count(&pool), 1)
	testing.expect_value(t, (^Position)(ecs.part_pool_get(&pool, thing))^, second)
}

@(test)
part_pool_insert_grows_capacity :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	pool: ecs.Part_Pool
	ecs.part_pool_init(&pool, type_info_of(Position))
	defer ecs.part_pool_destroy(&pool)

	spawned: [ecs.THING_POOL_MIN_CAPACITY - 1]ecs.Thing
	for &thing, i in spawned {
		thing = ecs.thing_pool_spawn(&things)
		value := Position{f32(i), f32(-i)}
		ecs.part_pool_insert(&pool, thing, &value)
	}

	testing.expect_value(t, ecs.part_pool_count(&pool), len(spawned))
	testing.expect(t, ecs.part_pool_capacity(&pool) >= len(spawned))

	for thing, i in spawned {
		part := (^Position)(ecs.part_pool_get(&pool, thing))
		testing.expect_value(t, part^, Position{f32(i), f32(-i)})
	}
}

@(test)
part_pool_insert_from_own_part_survives_growth :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	pool: ecs.Part_Pool
	ecs.part_pool_init(&pool, type_info_of(Position))
	defer ecs.part_pool_destroy(&pool)

	a := ecs.thing_pool_spawn(&things)
	b := ecs.thing_pool_spawn(&things)
	value := Position{1, 2}
	ecs.part_pool_insert(&pool, a, &value)

	// Capacity is 1 here, so this insert reallocates the data `get` points into.
	testing.expect_value(t, ecs.part_pool_capacity(&pool), 1)
	ecs.part_pool_insert(&pool, b, ecs.part_pool_get(&pool, a))

	testing.expect_value(t, (^Position)(ecs.part_pool_get(&pool, b))^, value)
}

@(test)
part_pool_insert_across_pages :: proc(t: ^testing.T) {
	pool: ecs.Part_Pool
	ecs.part_pool_init(&pool, type_info_of(Position))
	defer ecs.part_pool_destroy(&pool)

	low := ecs.thing_make(1)
	high := ecs.thing_make(ecs.PART_POOL_PAGE_SIZE + 1)
	last := ecs.thing_make(ecs.THING_MAX_IDX - 1)

	values := [3]Position{{1, 1}, {2, 2}, {3, 3}}
	ecs.part_pool_insert(&pool, low, &values[0])
	ecs.part_pool_insert(&pool, high, &values[1])
	ecs.part_pool_insert(&pool, last, &values[2])

	testing.expect_value(t, (^Position)(ecs.part_pool_get(&pool, low))^, values[0])
	testing.expect_value(t, (^Position)(ecs.part_pool_get(&pool, high))^, values[1])
	testing.expect_value(t, (^Position)(ecs.part_pool_get(&pool, last))^, values[2])
}

@(test)
part_pool_parts_are_aligned :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	pool: ecs.Part_Pool
	ecs.part_pool_init(&pool, type_info_of(Aligned))
	defer ecs.part_pool_destroy(&pool)

	for _ in 0 ..< 8 {
		part := ecs.part_pool_insert(&pool, ecs.thing_pool_spawn(&things))
		testing.expect_value(t, uintptr(part) % align_of(Aligned), 0)
	}
}

// >------------------------------------------------------------------------ Get

@(test)
part_pool_get_missing_returns_nil :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	pool: ecs.Part_Pool
	ecs.part_pool_init(&pool, type_info_of(Position))
	defer ecs.part_pool_destroy(&pool)

	a := ecs.thing_pool_spawn(&things)
	b := ecs.thing_pool_spawn(&things)
	ecs.part_pool_insert(&pool, a)

	testing.expect(t, ecs.part_pool_get(&pool, b) == nil)
	testing.expect(t, ecs.part_pool_get(&pool, ecs.THING_NIL) == nil)
	testing.expect(t, !ecs.part_pool_has(&pool, b))
	testing.expect(t, !ecs.part_pool_has(&pool, ecs.THING_NIL))
}

@(test)
part_pool_stale_thing_does_not_see_part :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	pool: ecs.Part_Pool
	ecs.part_pool_init(&pool, type_info_of(Position))
	defer ecs.part_pool_destroy(&pool)

	old := ecs.thing_pool_spawn(&things)
	ecs.thing_pool_kill(&things, old)
	new := ecs.thing_pool_spawn(&things)
	ecs.part_pool_insert(&pool, new)

	testing.expect_value(t, old.idx, new.idx)
	testing.expect(t, ecs.part_pool_get(&pool, old) == nil)
	testing.expect(t, !ecs.part_pool_remove(&pool, old))
	testing.expect(t, ecs.part_pool_has(&pool, new))
}

@(test)
part_pool_insert_for_reused_idx_takes_over_slot :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	pool: ecs.Part_Pool
	ecs.part_pool_init(&pool, type_info_of(Position))
	defer ecs.part_pool_destroy(&pool)

	// Old thing dies without its part being removed.
	old := ecs.thing_pool_spawn(&things)
	ecs.part_pool_insert(&pool, old)
	ecs.thing_pool_kill(&things, old)
	new := ecs.thing_pool_spawn(&things)
	ecs.part_pool_insert(&pool, new)

	testing.expect_value(t, ecs.part_pool_count(&pool), 1)
	testing.expect(t, ecs.part_pool_has(&pool, new))
	testing.expect(t, !ecs.part_pool_has(&pool, old))
}

// >--------------------------------------------------------------------- Remove

@(test)
part_pool_remove_keeps_other_parts :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	pool: ecs.Part_Pool
	ecs.part_pool_init(&pool, type_info_of(Position), count_destroyed)
	defer ecs.part_pool_destroy(&pool)
	destroyed_count = 0

	spawned: [4]ecs.Thing
	for &thing, i in spawned {
		thing = ecs.thing_pool_spawn(&things)
		value := Position{f32(i), 0}
		ecs.part_pool_insert(&pool, thing, &value)
	}

	// Removing the first part moves the last one into its slot.
	testing.expect(t, ecs.part_pool_remove(&pool, spawned[0]))
	testing.expect_value(t, destroyed_count, 1)
	testing.expect_value(t, ecs.part_pool_count(&pool), 3)
	testing.expect(t, !ecs.part_pool_has(&pool, spawned[0]))

	for thing, i in spawned[1:] {
		part := (^Position)(ecs.part_pool_get(&pool, thing))
		testing.expect_value(t, part^, Position{f32(i + 1), 0})
	}

	// Removing the last part needs no move.
	testing.expect(t, ecs.part_pool_remove(&pool, spawned[2]))
	testing.expect_value(t, (^Position)(ecs.part_pool_get(&pool, spawned[1]))^, Position{1, 0})
	testing.expect_value(t, (^Position)(ecs.part_pool_get(&pool, spawned[3]))^, Position{3, 0})
}

@(test)
part_pool_remove_missing_returns_false :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	pool: ecs.Part_Pool
	ecs.part_pool_init(&pool, type_info_of(Position), count_destroyed)
	defer ecs.part_pool_destroy(&pool)
	destroyed_count = 0

	thing := ecs.thing_pool_spawn(&things)

	testing.expect(t, !ecs.part_pool_remove(&pool, thing))
	testing.expect(t, !ecs.part_pool_remove(&pool, ecs.THING_NIL))

	ecs.part_pool_insert(&pool, thing)
	testing.expect(t, ecs.part_pool_remove(&pool, thing))
	testing.expect(t, !ecs.part_pool_remove(&pool, thing))
	testing.expect_value(t, destroyed_count, 1)
}

// >----------------------------------------------------------------------- Tags

@(test)
part_pool_supports_zero_sized_parts :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	pool: ecs.Part_Pool
	ecs.part_pool_init(&pool, type_info_of(Tag))
	defer ecs.part_pool_destroy(&pool)

	a := ecs.thing_pool_spawn(&things)
	b := ecs.thing_pool_spawn(&things)
	ecs.part_pool_insert(&pool, a)
	ecs.part_pool_insert(&pool, b)

	testing.expect(t, ecs.part_pool_get(&pool, a) != nil)
	testing.expect(t, ecs.part_pool_has(&pool, b))
	testing.expect_value(t, ecs.part_pool_count(&pool), 2)

	testing.expect(t, ecs.part_pool_remove(&pool, a))
	testing.expect(t, ecs.part_pool_get(&pool, a) == nil)
	testing.expect(t, ecs.part_pool_has(&pool, b))
}
