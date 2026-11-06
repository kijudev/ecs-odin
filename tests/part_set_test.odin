package ecs_tests

import "core:testing"

import ecs "../ecs"

// >------------------------------------------------------------------ Lifecycle

@(test)
part_set_init_creates_empty_set :: proc(t: ^testing.T) {
	set: ecs.Part_Set
	ecs.part_set_init(&set, type_info_of(Position))
	defer ecs.part_set_destroy(&set)

	testing.expect_value(t, set.parts_size, 0)
	testing.expect_value(t, set.parts_capacity, 0)
}

@(test)
part_set_reset_removes_all_parts :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	set: ecs.Part_Set
	ecs.part_set_init(&set, type_info_of(Position), count_destroyed)
	defer ecs.part_set_destroy(&set)
	destroyed_count = 0

	a := ecs.thing_pool_spawn(&things)
	b := ecs.thing_pool_spawn(&things)
	ecs.part_set_insert(&set, a)
	ecs.part_set_insert(&set, b)

	ecs.part_set_reset(&set)

	testing.expect_value(t, destroyed_count, 2)
	testing.expect_value(t, set.parts_size, 0)
	testing.expect(t, !ecs.part_set_has(&set, a))
	testing.expect(t, !ecs.part_set_has(&set, b))

	// Pool is usable again after reset.
	ecs.part_set_insert(&set, a)
	testing.expect(t, ecs.part_set_has(&set, a))
}

@(test)
part_set_destroy_destroys_parts :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	set: ecs.Part_Set
	ecs.part_set_init(&set, type_info_of(Position), count_destroyed)
	destroyed_count = 0

	ecs.part_set_insert(&set, ecs.thing_pool_spawn(&things))
	ecs.part_set_insert(&set, ecs.thing_pool_spawn(&things))
	ecs.part_set_destroy(&set)

	testing.expect_value(t, destroyed_count, 2)
}

// >--------------------------------------------------------------------- Insert

@(test)
part_set_insert_copies_part :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	set: ecs.Part_Set
	ecs.part_set_init(&set, type_info_of(Position))
	defer ecs.part_set_destroy(&set)

	thing := ecs.thing_pool_spawn(&things)
	value := Position{1, 2}
	ecs.part_set_insert(&set, thing, &value)
	value = {}

	part := (^Position)(ecs.part_set_get_part(&set, thing))
	testing.expect(t, part != nil)
	testing.expect_value(t, part^, Position{1, 2})
	testing.expect_value(t, set.parts_size, 1)
}

@(test)
part_set_insert_nil_zero_initialises :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	set: ecs.Part_Set
	ecs.part_set_init(&set, type_info_of(Position))
	defer ecs.part_set_destroy(&set)

	a := ecs.thing_pool_spawn(&things)
	b := ecs.thing_pool_spawn(&things)

	value := Position{1, 2}
	ecs.part_set_insert(&set, a, &value)
	ecs.part_set_remove(&set, a) // leaves old bytes in the freed slot
	part := (^Position)(ecs.part_set_insert(&set, b))

	testing.expect_value(t, part^, Position{})
}

@(test)
part_set_insert_existing_overwrites :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	set: ecs.Part_Set
	ecs.part_set_init(&set, type_info_of(Position), count_destroyed)
	defer ecs.part_set_destroy(&set)
	destroyed_count = 0

	thing := ecs.thing_pool_spawn(&things)
	first := Position{1, 2}
	second := Position{3, 4}
	ecs.part_set_insert(&set, thing, &first)
	ecs.part_set_insert(&set, thing, &second)

	testing.expect_value(t, destroyed_count, 1)
	testing.expect_value(t, set.parts_size, 1)
	testing.expect_value(t, (^Position)(ecs.part_set_get_part(&set, thing))^, second)
}

@(test)
part_set_insert_grows_capacity :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	set: ecs.Part_Set
	ecs.part_set_init(&set, type_info_of(Position))
	defer ecs.part_set_destroy(&set)

	spawned: [ecs.THING_POOL_MIN_CAPACITY - 1]ecs.Thing
	for &thing, i in spawned {
		thing = ecs.thing_pool_spawn(&things)
		value := Position{f32(i), f32(-i)}
		ecs.part_set_insert(&set, thing, &value)
	}

	testing.expect_value(t, set.parts_size, len(spawned))
	testing.expect(t, set.parts_capacity >= len(spawned))

	for thing, i in spawned {
		part := (^Position)(ecs.part_set_get_part(&set, thing))
		testing.expect_value(t, part^, Position{f32(i), f32(-i)})
	}
}

@(test)
part_set_insert_from_own_part_survives_growth :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	set: ecs.Part_Set
	ecs.part_set_init(&set, type_info_of(Position))
	defer ecs.part_set_destroy(&set)

	a := ecs.thing_pool_spawn(&things)
	b := ecs.thing_pool_spawn(&things)
	value := Position{1, 2}
	ecs.part_set_insert(&set, a, &value)

	// Capacity is 1 here, so this insert reallocates the data `get` points into.
	testing.expect_value(t, set.parts_capacity, 1)
	ecs.part_set_insert(&set, b, ecs.part_set_get_part(&set, a))

	testing.expect_value(t, (^Position)(ecs.part_set_get_part(&set, b))^, value)
}

@(test)
part_set_insert_across_pages :: proc(t: ^testing.T) {
	set: ecs.Part_Set
	ecs.part_set_init(&set, type_info_of(Position))
	defer ecs.part_set_destroy(&set)

	low := ecs.thing_make(1)
	high := ecs.thing_make(ecs.PART_SET_PAGE_SIZE + 1)
	last := ecs.thing_make(ecs.THING_MAX_IDX - 1)

	values := [3]Position{{1, 1}, {2, 2}, {3, 3}}
	ecs.part_set_insert(&set, low, &values[0])
	ecs.part_set_insert(&set, high, &values[1])
	ecs.part_set_insert(&set, last, &values[2])

	testing.expect_value(t, (^Position)(ecs.part_set_get_part(&set, low))^, values[0])
	testing.expect_value(t, (^Position)(ecs.part_set_get_part(&set, high))^, values[1])
	testing.expect_value(t, (^Position)(ecs.part_set_get_part(&set, last))^, values[2])
}

@(test)
part_set_parts_are_aligned :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	set: ecs.Part_Set
	ecs.part_set_init(&set, type_info_of(Aligned))
	defer ecs.part_set_destroy(&set)

	for _ in 0 ..< 8 {
		part := ecs.part_set_insert(&set, ecs.thing_pool_spawn(&things))
		testing.expect_value(t, uintptr(part) % align_of(Aligned), 0)
	}
}

// >------------------------------------------------------------------------ Get

@(test)
part_set_get_missing_returns_nil :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	set: ecs.Part_Set
	ecs.part_set_init(&set, type_info_of(Position))
	defer ecs.part_set_destroy(&set)

	a := ecs.thing_pool_spawn(&things)
	b := ecs.thing_pool_spawn(&things)
	ecs.part_set_insert(&set, a)

	testing.expect(t, ecs.part_set_get_part(&set, b) == nil)
	testing.expect(t, ecs.part_set_get_part(&set, ecs.THING_NIL) == nil)
	testing.expect(t, !ecs.part_set_has(&set, b))
	testing.expect(t, !ecs.part_set_has(&set, ecs.THING_NIL))
}

@(test)
part_set_stale_thing_does_not_see_part :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	set: ecs.Part_Set
	ecs.part_set_init(&set, type_info_of(Position))
	defer ecs.part_set_destroy(&set)

	old := ecs.thing_pool_spawn(&things)
	ecs.thing_pool_kill(&things, old)
	new := ecs.thing_pool_spawn(&things)
	ecs.part_set_insert(&set, new)

	testing.expect_value(t, old.idx, new.idx)
	testing.expect(t, ecs.part_set_get_part(&set, old) == nil)
	testing.expect(t, !ecs.part_set_remove(&set, old))
	testing.expect(t, ecs.part_set_has(&set, new))
}

@(test)
part_set_insert_for_reused_idx_takes_over_slot :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	set: ecs.Part_Set
	ecs.part_set_init(&set, type_info_of(Position))
	defer ecs.part_set_destroy(&set)

	// Old thing dies without its part being removed.
	old := ecs.thing_pool_spawn(&things)
	ecs.part_set_insert(&set, old)
	ecs.thing_pool_kill(&things, old)
	new := ecs.thing_pool_spawn(&things)
	ecs.part_set_insert(&set, new)

	testing.expect_value(t, set.parts_size, 1)
	testing.expect(t, ecs.part_set_has(&set, new))
	testing.expect(t, !ecs.part_set_has(&set, old))
}

// >--------------------------------------------------------------------- Remove

@(test)
part_set_remove_keeps_other_parts :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	set: ecs.Part_Set
	ecs.part_set_init(&set, type_info_of(Position), count_destroyed)
	defer ecs.part_set_destroy(&set)
	destroyed_count = 0

	spawned: [4]ecs.Thing
	for &thing, i in spawned {
		thing = ecs.thing_pool_spawn(&things)
		value := Position{f32(i), 0}
		ecs.part_set_insert(&set, thing, &value)
	}

	// Removing the first part moves the last one into its slot.
	testing.expect(t, ecs.part_set_remove(&set, spawned[0]))
	testing.expect_value(t, destroyed_count, 1)
	testing.expect_value(t, set.parts_size, 3)
	testing.expect(t, !ecs.part_set_has(&set, spawned[0]))

	for thing, i in spawned[1:] {
		part := (^Position)(ecs.part_set_get_part(&set, thing))
		testing.expect_value(t, part^, Position{f32(i + 1), 0})
	}

	// Removing the last part needs no move.
	testing.expect(t, ecs.part_set_remove(&set, spawned[2]))
	testing.expect_value(t, (^Position)(ecs.part_set_get_part(&set, spawned[1]))^, Position{1, 0})
	testing.expect_value(t, (^Position)(ecs.part_set_get_part(&set, spawned[3]))^, Position{3, 0})
}

@(test)
part_set_remove_missing_returns_false :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	set: ecs.Part_Set
	ecs.part_set_init(&set, type_info_of(Position), count_destroyed)
	defer ecs.part_set_destroy(&set)
	destroyed_count = 0

	thing := ecs.thing_pool_spawn(&things)

	testing.expect(t, !ecs.part_set_remove(&set, thing))
	testing.expect(t, !ecs.part_set_remove(&set, ecs.THING_NIL))

	ecs.part_set_insert(&set, thing)
	testing.expect(t, ecs.part_set_remove(&set, thing))
	testing.expect(t, !ecs.part_set_remove(&set, thing))
	testing.expect_value(t, destroyed_count, 1)
}

// >----------------------------------------------------------------------- Tags

@(test)
part_set_supports_zero_sized_parts :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	ecs.thing_pool_init(&things, ecs.THING_POOL_MIN_CAPACITY)
	defer ecs.thing_pool_destroy(&things)
	set: ecs.Part_Set
	ecs.part_set_init(&set, type_info_of(Tag))
	defer ecs.part_set_destroy(&set)

	a := ecs.thing_pool_spawn(&things)
	b := ecs.thing_pool_spawn(&things)
	ecs.part_set_insert(&set, a)
	ecs.part_set_insert(&set, b)

	testing.expect(t, ecs.part_set_get_part(&set, a) != nil)
	testing.expect(t, ecs.part_set_has(&set, b))
	testing.expect_value(t, set.parts_size, 2)

	testing.expect(t, ecs.part_set_remove(&set, a))
	testing.expect(t, ecs.part_set_get_part(&set, a) == nil)
	testing.expect(t, ecs.part_set_has(&set, b))
}
