package ecs_tests

import "core:testing"

import ecs "../ecs"

Cmd_Pool :: ecs.Cmd_Pool(World_Part)

@(private = "file")
make_things :: proc(things: ^ecs.Thing_Pool) -> (a, b: ecs.Thing) {
	ecs.thing_pool_init(things, ecs.THING_POOL_MIN_CAPACITY)
	return ecs.thing_pool_spawn(things), ecs.thing_pool_spawn(things)
}

@(private = "file")
record_value :: proc(pool: ^Cmd_Pool, thing: ecs.Thing, kind: World_Part, part: $T) {
	part := part
	ecs.cmd_pool_record_set_value(pool, thing, kind, &part, size_of(T))
}

// >------------------------------------------------------------------ Lifecycle

@(test)
cmd_pool_init_creates_empty_pool :: proc(t: ^testing.T) {
	pool: Cmd_Pool
	ecs.cmd_pool_init(&pool)
	defer ecs.cmd_pool_destroy(&pool)

	testing.expect_value(t, ecs.cmd_pool_count(&pool), 0)
	testing.expect_value(t, ecs.cmd_pool_parts_size(&pool), 0)
	testing.expect_value(t, len(ecs.cmd_pool_slice(&pool)), 0)
}

@(test)
cmd_pool_init_with_zero_capacity_grows_on_record :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	pool: Cmd_Pool
	ecs.cmd_pool_init(&pool, 0, 0)
	defer ecs.cmd_pool_destroy(&pool)

	record_value(&pool, a, .Position, Position{1, 2})

	testing.expect_value(t, ecs.cmd_pool_count(&pool), 1)
	testing.expect_value(t, ecs.cmd_pool_parts_size(&pool), size_of(Position))
}

@(test)
cmd_pool_reset_clears_commands_and_parts :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, b := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	pool: Cmd_Pool
	ecs.cmd_pool_init(&pool)
	defer ecs.cmd_pool_destroy(&pool)

	record_value(&pool, a, .Position, Position{1, 2})
	ecs.cmd_pool_record_kill(&pool, b)

	ecs.cmd_pool_reset(&pool)

	testing.expect_value(t, ecs.cmd_pool_count(&pool), 0)
	testing.expect_value(t, ecs.cmd_pool_parts_size(&pool), 0)

	// Offsets start from zero again after reset.
	record_value(&pool, b, .Velocity, Velocity{3, 4})
	cmd := ecs.cmd_pool_slice(&pool)[0].(ecs.Cmd_Set_Value(World_Part))
	testing.expect_value(t, cmd.offset, 0)
	testing.expect_value(t, ecs.cmd_pool_get_part(&pool, cmd.offset, Velocity), Velocity{3, 4})
}

// >--------------------------------------------------------------------- Record

@(test)
cmd_pool_record_kill_stores_thing :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	pool: Cmd_Pool
	ecs.cmd_pool_init(&pool)
	defer ecs.cmd_pool_destroy(&pool)

	ecs.cmd_pool_record_kill(&pool, a)

	cmd, ok := ecs.cmd_pool_slice(&pool)[0].(ecs.Cmd_Kill)
	testing.expect(t, ok)
	testing.expect_value(t, cmd.thing, a)
	testing.expect_value(t, ecs.cmd_pool_parts_size(&pool), 0)
}

@(test)
cmd_pool_record_set_value_stores_kind_and_part :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	pool: Cmd_Pool
	ecs.cmd_pool_init(&pool)
	defer ecs.cmd_pool_destroy(&pool)

	record_value(&pool, a, .Target, Position{1, 2})

	cmd, ok := ecs.cmd_pool_slice(&pool)[0].(ecs.Cmd_Set_Value(World_Part))
	testing.expect(t, ok)
	testing.expect_value(t, cmd.thing, a)
	testing.expect_value(t, cmd.kind, World_Part.Target)
	testing.expect_value(t, cmd.size, size_of(Position))
	testing.expect_value(t, ecs.cmd_pool_get_part(&pool, cmd.offset, Position), Position{1, 2})
}

@(test)
cmd_pool_record_set_value_copies_part :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	pool: Cmd_Pool
	ecs.cmd_pool_init(&pool)
	defer ecs.cmd_pool_destroy(&pool)

	part := Position{1, 2}
	ecs.cmd_pool_record_set_value(&pool, a, .Position, &part, size_of(Position))
	part = Position{5, 6}

	cmd := ecs.cmd_pool_slice(&pool)[0].(ecs.Cmd_Set_Value(World_Part))
	testing.expect_value(t, ecs.cmd_pool_get_part(&pool, cmd.offset, Position), Position{1, 2})
}

@(test)
cmd_pool_record_set_value_packs_parts_in_order :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, b := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	pool: Cmd_Pool
	ecs.cmd_pool_init(&pool)
	defer ecs.cmd_pool_destroy(&pool)

	record_value(&pool, a, .Position, Position{1, 2})
	record_value(&pool, b, .Velocity, Velocity{3, 4})

	cmds := ecs.cmd_pool_slice(&pool)
	first := cmds[0].(ecs.Cmd_Set_Value(World_Part))
	second := cmds[1].(ecs.Cmd_Set_Value(World_Part))

	testing.expect_value(t, first.offset, 0)
	testing.expect_value(t, second.offset, size_of(Position))
	testing.expect_value(t, ecs.cmd_pool_parts_size(&pool), size_of(Position) + size_of(Velocity))
	testing.expect_value(t, ecs.cmd_pool_get_part(&pool, first.offset, Position), Position{1, 2})
	testing.expect_value(t, ecs.cmd_pool_get_part(&pool, second.offset, Velocity), Velocity{3, 4})
}

@(test)
cmd_pool_record_set_value_survives_growth :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	pool: Cmd_Pool
	ecs.cmd_pool_init(&pool, 0, 0)
	defer ecs.cmd_pool_destroy(&pool)

	for i in 0 ..< 100 {
		record_value(&pool, a, .Position, Position{f32(i), f32(-i)})
	}

	testing.expect_value(t, ecs.cmd_pool_count(&pool), 100)
	for cmd, i in ecs.cmd_pool_slice(&pool) {
		set := cmd.(ecs.Cmd_Set_Value(World_Part))
		got := ecs.cmd_pool_get_part(&pool, set.offset, Position)
		testing.expect_value(t, got, Position{f32(i), f32(-i)})
	}
}

@(test)
cmd_pool_record_set_value_handles_zero_sized_part :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	pool: Cmd_Pool
	ecs.cmd_pool_init(&pool)
	defer ecs.cmd_pool_destroy(&pool)

	record_value(&pool, a, .Tag, Tag{})

	cmd := ecs.cmd_pool_slice(&pool)[0].(ecs.Cmd_Set_Value(World_Part))
	testing.expect_value(t, cmd.size, 0)
	testing.expect_value(t, ecs.cmd_pool_parts_size(&pool), 0)
	testing.expect_value(t, len(ecs.cmd_pool_get_bytes(&pool, cmd.offset, cmd.size)), 0)
	testing.expect_value(t, ecs.cmd_pool_get_part(&pool, cmd.offset, Tag), Tag{})
}

@(test)
cmd_pool_record_set_zero_stores_kind :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	pool: Cmd_Pool
	ecs.cmd_pool_init(&pool)
	defer ecs.cmd_pool_destroy(&pool)

	ecs.cmd_pool_record_set_zero(&pool, a, .Velocity)

	cmd, ok := ecs.cmd_pool_slice(&pool)[0].(ecs.Cmd_Set_Zero(World_Part))
	testing.expect(t, ok)
	testing.expect_value(t, cmd.thing, a)
	testing.expect_value(t, cmd.kind, World_Part.Velocity)
	testing.expect_value(t, ecs.cmd_pool_parts_size(&pool), 0)
}

@(test)
cmd_pool_record_remove_stores_kind :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	pool: Cmd_Pool
	ecs.cmd_pool_init(&pool)
	defer ecs.cmd_pool_destroy(&pool)

	ecs.cmd_pool_record_remove(&pool, a, .Position)

	cmd, ok := ecs.cmd_pool_slice(&pool)[0].(ecs.Cmd_Remove(World_Part))
	testing.expect(t, ok)
	testing.expect_value(t, cmd.thing, a)
	testing.expect_value(t, cmd.kind, World_Part.Position)
}

@(test)
cmd_pool_keeps_record_order :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, b := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	pool: Cmd_Pool
	ecs.cmd_pool_init(&pool)
	defer ecs.cmd_pool_destroy(&pool)

	record_value(&pool, a, .Position, Position{1, 2})
	ecs.cmd_pool_record_set_zero(&pool, b, .Velocity)
	ecs.cmd_pool_record_remove(&pool, a, .Tag)
	ecs.cmd_pool_record_kill(&pool, b)

	cmds := ecs.cmd_pool_slice(&pool)
	testing.expect_value(t, len(cmds), 4)

	_, is_set := cmds[0].(ecs.Cmd_Set_Value(World_Part))
	_, is_zero := cmds[1].(ecs.Cmd_Set_Zero(World_Part))
	_, is_remove := cmds[2].(ecs.Cmd_Remove(World_Part))
	_, is_kill := cmds[3].(ecs.Cmd_Kill)
	testing.expect(t, is_set)
	testing.expect(t, is_zero)
	testing.expect(t, is_remove)
	testing.expect(t, is_kill)
}

// >------------------------------------------------------------------------ Get

@(test)
cmd_pool_get_bytes_returns_part_bytes :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	pool: Cmd_Pool
	ecs.cmd_pool_init(&pool)
	defer ecs.cmd_pool_destroy(&pool)

	record_value(&pool, a, .Position, Position{1, 2})
	record_value(&pool, a, .Velocity, Velocity{3, 4})

	cmd := ecs.cmd_pool_slice(&pool)[1].(ecs.Cmd_Set_Value(World_Part))
	bytes := ecs.cmd_pool_get_bytes(&pool, cmd.offset, cmd.size)

	testing.expect_value(t, len(bytes), size_of(Velocity))
	testing.expect_value(t, (^Velocity)(raw_data(bytes))^, Velocity{3, 4})
}

@(test)
cmd_pool_get_part_reads_misaligned_offset :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	pool: Cmd_Pool
	ecs.cmd_pool_init(&pool)
	defer ecs.cmd_pool_destroy(&pool)

	// A single byte first pushes the next part to an odd offset.
	record_value(&pool, a, .Tag, u8(7))
	record_value(&pool, a, .Target, Aligned{value = 42})

	cmds := ecs.cmd_pool_slice(&pool)
	byte_cmd := cmds[0].(ecs.Cmd_Set_Value(World_Part))
	aligned_cmd := cmds[1].(ecs.Cmd_Set_Value(World_Part))

	testing.expect_value(t, aligned_cmd.offset, 1)
	testing.expect_value(t, ecs.cmd_pool_get_part(&pool, byte_cmd.offset, u8), 7)
	testing.expect_value(t, ecs.cmd_pool_get_part(&pool, aligned_cmd.offset, Aligned).value, 42)
}
