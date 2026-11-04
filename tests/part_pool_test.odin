package ecs_tests

import "core:mem"
import "core:testing"

import ecs "../ecs"

Pool_Part :: enum {
	Position,
	Velocity,
	Tag,
	Target, // shares the Position type
}

Part_Pool :: ecs.Part_Pool(Pool_Part)

@(private = "file")
make_pool :: proc(pool: ^Part_Pool, allocator := context.allocator) {
	ecs.part_pool_init(pool, allocator)
	ecs.part_pool_register(pool, .Position, Position, count_destroyed)
	ecs.part_pool_register(pool, .Velocity, Velocity)
	ecs.part_pool_register(pool, .Tag, Tag)
	ecs.part_pool_register(pool, .Target, Position)
}

// >------------------------------------------------------------------ Lifecycle

@(test)
part_pool_init_creates_empty_pool :: proc(t: ^testing.T) {
	pool: Part_Pool
	ecs.part_pool_init(&pool)
	defer ecs.part_pool_destroy(&pool)

	for kind in Pool_Part {
		testing.expect(t, !ecs.part_pool_is_registered(&pool, kind))
	}
}

@(test)
part_pool_register_creates_empty_sets :: proc(t: ^testing.T) {
	pool: Part_Pool
	make_pool(&pool)
	defer ecs.part_pool_destroy(&pool)

	for kind in Pool_Part {
		testing.expect(t, ecs.part_pool_is_registered(&pool, kind))
		testing.expect_value(t, ecs.part_pool_count_parts(&pool, kind), 0)
	}
}

@(test)
part_pool_destroy_frees_with_init_allocator :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	pool: Part_Pool
	make_pool(&pool, mem.tracking_allocator(&track))

	ecs.part_pool_set_value(&pool, ecs.thing_make(1), .Position, Position{1, 2})
	ecs.part_pool_set_value(&pool, ecs.thing_make(2), .Velocity, Velocity{3, 4})
	testing.expect(t, len(track.allocation_map) > 0)

	destroyed_count = 0

	// Destroy runs under the default context.allocator, not the init one.
	ecs.part_pool_destroy(&pool)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
	testing.expect_value(t, destroyed_count, 1)
}

@(test)
part_pool_reset_removes_parts_keeps_registrations :: proc(t: ^testing.T) {
	pool: Part_Pool
	make_pool(&pool)
	defer ecs.part_pool_destroy(&pool)

	thing := ecs.thing_make(1)
	ecs.part_pool_set_value(&pool, thing, .Position, Position{1, 2})
	ecs.part_pool_set_value(&pool, thing, .Velocity, Velocity{3, 4})

	destroyed_count = 0
	ecs.part_pool_reset(&pool)

	testing.expect_value(t, destroyed_count, 1)
	for kind in Pool_Part {
		testing.expect(t, ecs.part_pool_is_registered(&pool, kind))
		testing.expect_value(t, ecs.part_pool_count_parts(&pool, kind), 0)
	}

	// Usable again after reset.
	ecs.part_pool_set_value(&pool, thing, .Position, Position{5, 6})
	testing.expect_value(t, ecs.part_pool_get(&pool, thing, .Position, Position)^, Position{5, 6})
}

// >------------------------------------------------------------------------ Set

@(test)
part_pool_set_value_and_get :: proc(t: ^testing.T) {
	pool: Part_Pool
	make_pool(&pool)
	defer ecs.part_pool_destroy(&pool)

	thing := ecs.thing_make(1)
	result := ecs.part_pool_set_value(&pool, thing, .Position, Position{1, 2})

	testing.expect(t, ecs.part_pool_has(&pool, thing, .Position))
	testing.expect(t, ecs.part_pool_get(&pool, thing, .Position, Position) == result)
	testing.expect_value(t, result^, Position{1, 2})
}

@(test)
part_pool_set_value_overwrites :: proc(t: ^testing.T) {
	pool: Part_Pool
	make_pool(&pool)
	defer ecs.part_pool_destroy(&pool)

	thing := ecs.thing_make(1)
	ecs.part_pool_set_value(&pool, thing, .Position, Position{1, 2})

	destroyed_count = 0
	ecs.part_pool_set_value(&pool, thing, .Position, Position{3, 4})

	testing.expect_value(t, destroyed_count, 1)
	testing.expect_value(t, ecs.part_pool_count_parts(&pool, .Position), 1)
	testing.expect_value(t, ecs.part_pool_get(&pool, thing, .Position, Position)^, Position{3, 4})
}

@(test)
part_pool_set_pointer_copies_or_zeroes :: proc(t: ^testing.T) {
	pool: Part_Pool
	make_pool(&pool)
	defer ecs.part_pool_destroy(&pool)

	a := ecs.thing_make(1)
	b := ecs.thing_make(2)

	value := Velocity{1, 2}
	result := ecs.part_pool_set_pointer(&pool, a, .Velocity, &value)
	testing.expect(t, result != &value)
	testing.expect_value(t, result^, Velocity{1, 2})

	zeroed := ecs.part_pool_set_pointer(&pool, b, .Velocity, (^Velocity)(nil))
	testing.expect_value(t, zeroed^, Velocity{})
}

@(test)
part_pool_set_raw_copies_or_zeroes :: proc(t: ^testing.T) {
	pool: Part_Pool
	make_pool(&pool)
	defer ecs.part_pool_destroy(&pool)

	a := ecs.thing_make(1)
	b := ecs.thing_make(2)

	value := Velocity{1, 2}
	ecs.part_pool_set_raw(&pool, a, .Velocity, &value)
	ecs.part_pool_set_raw(&pool, b, .Velocity, nil)

	testing.expect_value(t, ecs.part_pool_get(&pool, a, .Velocity, Velocity)^, Velocity{1, 2})
	testing.expect_value(t, ecs.part_pool_get(&pool, b, .Velocity, Velocity)^, Velocity{})
}

@(test)
part_pool_kinds_can_share_a_type :: proc(t: ^testing.T) {
	pool: Part_Pool
	make_pool(&pool)
	defer ecs.part_pool_destroy(&pool)

	thing := ecs.thing_make(1)
	ecs.part_pool_set_value(&pool, thing, .Position, Position{1, 2})
	ecs.part_pool_set_value(&pool, thing, .Target, Position{3, 4})

	testing.expect_value(t, ecs.part_pool_get(&pool, thing, .Position, Position)^, Position{1, 2})
	testing.expect_value(t, ecs.part_pool_get(&pool, thing, .Target, Position)^, Position{3, 4})

	ecs.part_pool_remove(&pool, thing, .Target)
	testing.expect(t, ecs.part_pool_has(&pool, thing, .Position))
}

@(test)
part_pool_zero_sized_parts :: proc(t: ^testing.T) {
	pool: Part_Pool
	make_pool(&pool)
	defer ecs.part_pool_destroy(&pool)

	thing := ecs.thing_make(1)
	ecs.part_pool_set_value(&pool, thing, .Tag, Tag{})

	testing.expect(t, ecs.part_pool_has(&pool, thing, .Tag))
	testing.expect(t, ecs.part_pool_get(&pool, thing, .Tag, Tag) != nil)
	testing.expect_value(t, len(ecs.part_pool_get_parts(&pool, .Tag, Tag)), 1)
}

// >------------------------------------------------------------------------ Get

@(test)
part_pool_get_missing_part_returns_nil :: proc(t: ^testing.T) {
	pool: Part_Pool
	make_pool(&pool)
	defer ecs.part_pool_destroy(&pool)

	thing := ecs.thing_make(1)
	ecs.part_pool_set_value(&pool, thing, .Position, Position{1, 2})

	testing.expect(t, !ecs.part_pool_has(&pool, thing, .Velocity))
	testing.expect(t, ecs.part_pool_get(&pool, thing, .Velocity, Velocity) == nil)
}

@(test)
part_pool_stale_thing_does_not_see_part :: proc(t: ^testing.T) {
	pool: Part_Pool
	make_pool(&pool)
	defer ecs.part_pool_destroy(&pool)

	old := ecs.thing_make(1, 0)
	current := ecs.thing_make(1, 1)
	ecs.part_pool_set_value(&pool, current, .Position, Position{1, 2})

	testing.expect(t, !ecs.part_pool_has(&pool, old, .Position))
	testing.expect(t, ecs.part_pool_get(&pool, old, .Position, Position) == nil)
	testing.expect(t, !ecs.part_pool_remove(&pool, old, .Position))
	testing.expect(t, ecs.part_pool_has(&pool, current, .Position))
}

@(test)
part_pool_get_parts_and_things_match_up :: proc(t: ^testing.T) {
	pool: Part_Pool
	make_pool(&pool)
	defer ecs.part_pool_destroy(&pool)

	for i in 1 ..= 5 {
		ecs.part_pool_set_value(&pool, ecs.thing_make(u32(i)), .Position, Position{f32(i), 0})
	}
	ecs.part_pool_remove(&pool, ecs.thing_make(2), .Position)

	parts := ecs.part_pool_get_parts(&pool, .Position, Position)
	things := ecs.part_pool_get_things(&pool, .Position)

	testing.expect_value(t, len(parts), 4)
	testing.expect_value(t, len(things), 4)
	for thing, i in things {
		testing.expect_value(t, parts[i].x, f32(thing.idx))
	}
}

// >--------------------------------------------------------------------- Remove

@(test)
part_pool_remove_removes_part :: proc(t: ^testing.T) {
	pool: Part_Pool
	make_pool(&pool)
	defer ecs.part_pool_destroy(&pool)

	thing := ecs.thing_make(1)
	ecs.part_pool_set_value(&pool, thing, .Position, Position{1, 2})

	destroyed_count = 0
	testing.expect(t, ecs.part_pool_remove(&pool, thing, .Position))
	testing.expect_value(t, destroyed_count, 1)
	testing.expect(t, !ecs.part_pool_has(&pool, thing, .Position))

	// Removing twice fails.
	testing.expect(t, !ecs.part_pool_remove(&pool, thing, .Position))
}

@(test)
part_pool_remove_all_removes_every_kind :: proc(t: ^testing.T) {
	pool: Part_Pool
	make_pool(&pool)
	defer ecs.part_pool_destroy(&pool)

	a := ecs.thing_make(1)
	b := ecs.thing_make(2)
	ecs.part_pool_set_value(&pool, a, .Position, Position{1, 2})
	ecs.part_pool_set_value(&pool, a, .Velocity, Velocity{3, 4})
	ecs.part_pool_set_value(&pool, a, .Tag, Tag{})
	ecs.part_pool_set_value(&pool, b, .Position, Position{5, 6})

	ecs.part_pool_remove_all(&pool, a)

	for kind in Pool_Part {
		testing.expect(t, !ecs.part_pool_has(&pool, a, kind))
	}
	testing.expect_value(t, ecs.part_pool_get(&pool, b, .Position, Position)^, Position{5, 6})
}

// >------------------------------------------------------------------ Unchecked

@(test)
part_pool_unchecked_variants :: proc(t: ^testing.T) {
	pool: Part_Pool
	make_pool(&pool)
	defer ecs.part_pool_destroy(&pool)

	a := ecs.thing_make(1)
	b := ecs.thing_make(2)
	c := ecs.thing_make(3)

	value := Velocity{3, 4}
	ecs.part_pool_set_value_unchecked(&pool, a, .Velocity, Velocity{1, 2})
	ecs.part_pool_set_pointer_unchecked(&pool, b, .Velocity, &value)
	ecs.part_pool_set_raw_unchecked(&pool, c, .Velocity, nil)

	testing.expect_value(
		t,
		ecs.part_pool_get_unchecked(&pool, a, .Velocity, Velocity)^,
		Velocity{1, 2},
	)
	testing.expect_value(
		t,
		ecs.part_pool_get_unchecked(&pool, b, .Velocity, Velocity)^,
		Velocity{3, 4},
	)
	testing.expect_value(
		t,
		ecs.part_pool_get_unchecked(&pool, c, .Velocity, Velocity)^,
		Velocity{},
	)

	ecs.part_pool_remove_unchecked(&pool, b, .Velocity)
	testing.expect(t, !ecs.part_pool_has(&pool, b, .Velocity))
	testing.expect_value(t, ecs.part_pool_count_parts(&pool, .Velocity), 2)
}

// >-------------------------------------------------------------------- Asserts

@(test)
part_pool_register_twice_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	pool: Part_Pool
	ecs.part_pool_init(&pool)
	ecs.part_pool_register(&pool, .Position, Position)

	testing.expect_assert_message(t, "Part kind Position is already registered.")
	ecs.part_pool_register(&pool, .Position, Position)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
part_pool_unregistered_kind_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	pool: Part_Pool
	ecs.part_pool_init(&pool)

	testing.expect_assert_message(t, "Part kind Velocity is not registered.")
	ecs.part_pool_has(&pool, ecs.thing_make(1), .Velocity)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
part_pool_wrong_type_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	pool: Part_Pool
	ecs.part_pool_init(&pool)
	ecs.part_pool_register(&pool, .Target, Position)

	testing.expect_assert_message(t, "Part kind Target is a Position, not a Velocity.")
	ecs.part_pool_get(&pool, ecs.thing_make(1), .Target, Velocity)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
part_pool_unchecked_still_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	pool: Part_Pool
	ecs.part_pool_init(&pool)
	ecs.part_pool_register(&pool, .Target, Position)

	testing.expect_assert_message(t, "Part kind Target is a Position, not a Velocity.")
	ecs.part_pool_set_value_unchecked(&pool, ecs.thing_make(1), .Target, Velocity{})
	testing.fail_now(t, "The call did not assert.")
}
