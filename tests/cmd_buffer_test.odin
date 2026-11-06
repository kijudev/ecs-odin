package ecs_tests

import "core:testing"

import ecs "../ecs"

@(private = "file")
make_things :: proc(things: ^ecs.Thing_Pool) -> (a, b: ecs.Thing) {
	ecs.thing_pool_init(things, ecs.THING_POOL_MIN_CAPACITY)
	return ecs.thing_pool_spawn(things), ecs.thing_pool_spawn(things)
}

@(private = "file")
record_value :: proc(buffer: ^Cmd_Buffer, thing: ecs.Thing, kind: Kind, part: $T) {
	part := part
	ecs.cmd_buffer_record_set_value(buffer, thing, kind, &part, size_of(T))
}

// >------------------------------------------------------------------ Lifecycle

@(test)
cmd_buffer_init_creates_empty_pool :: proc(t: ^testing.T) {
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer)
	defer ecs.cmd_buffer_destroy(&buffer)

	testing.expect_value(t, len(buffer.cmds), 0)
	testing.expect_value(t, len(buffer.parts), 0)
	testing.expect_value(t, len(buffer.cmds), 0)
}

@(test)
cmd_buffer_init_with_zero_capacity_grows_on_record :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer, 0, 0)
	defer ecs.cmd_buffer_destroy(&buffer)

	record_value(&buffer, a, .Position, Position{1, 2})

	testing.expect_value(t, len(buffer.cmds), 1)
	testing.expect_value(t, len(buffer.parts), size_of(Position))
}

@(test)
cmd_buffer_reset_clears_cmds_and_parts :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, b := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer)
	defer ecs.cmd_buffer_destroy(&buffer)

	record_value(&buffer, a, .Position, Position{1, 2})
	ecs.cmd_buffer_record_kill(&buffer, b)

	ecs.cmd_buffer_reset(&buffer)

	testing.expect_value(t, len(buffer.cmds), 0)
	testing.expect_value(t, len(buffer.parts), 0)

	// Offsets start from zero again after reset.
	record_value(&buffer, b, .Velocity, Velocity{3, 4})
	cmd := buffer.cmds[0].(ecs.Cmd_Set_Value(Kind))
	testing.expect_value(t, cmd.offset, 0)
	testing.expect_value(t, ecs.cmd_buffer_get_part(&buffer, cmd.offset, Velocity), Velocity{3, 4})
}

// >--------------------------------------------------------------------- Record

@(test)
cmd_buffer_record_kill_stores_thing :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer)
	defer ecs.cmd_buffer_destroy(&buffer)

	ecs.cmd_buffer_record_kill(&buffer, a)

	cmd, ok := buffer.cmds[0].(ecs.Cmd_Kill)
	testing.expect(t, ok)
	testing.expect_value(t, cmd.thing, a)
	testing.expect_value(t, len(buffer.parts), 0)
}

@(test)
cmd_buffer_record_set_value_stores_kind_and_part :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer)
	defer ecs.cmd_buffer_destroy(&buffer)

	record_value(&buffer, a, .Target, Position{1, 2})

	cmd, ok := buffer.cmds[0].(ecs.Cmd_Set_Value(Kind))
	testing.expect(t, ok)
	testing.expect_value(t, cmd.thing, a)
	testing.expect_value(t, cmd.kind, Kind.Target)
	testing.expect_value(t, cmd.size, size_of(Position))
	testing.expect_value(t, ecs.cmd_buffer_get_part(&buffer, cmd.offset, Position), Position{1, 2})
}

@(test)
cmd_buffer_record_set_value_copies_part :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer)
	defer ecs.cmd_buffer_destroy(&buffer)

	part := Position{1, 2}
	ecs.cmd_buffer_record_set_value(&buffer, a, .Position, &part, size_of(Position))
	part = Position{5, 6}

	cmd := buffer.cmds[0].(ecs.Cmd_Set_Value(Kind))
	testing.expect_value(t, ecs.cmd_buffer_get_part(&buffer, cmd.offset, Position), Position{1, 2})
}

@(test)
cmd_buffer_record_set_value_packs_parts_in_order :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, b := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer)
	defer ecs.cmd_buffer_destroy(&buffer)

	record_value(&buffer, a, .Position, Position{1, 2})
	record_value(&buffer, b, .Velocity, Velocity{3, 4})

	cmds := buffer.cmds
	first := cmds[0].(ecs.Cmd_Set_Value(Kind))
	second := cmds[1].(ecs.Cmd_Set_Value(Kind))

	testing.expect_value(t, first.offset, 0)
	testing.expect_value(t, second.offset, size_of(Position))
	testing.expect_value(t, len(buffer.parts), size_of(Position) + size_of(Velocity))
	testing.expect_value(t, ecs.cmd_buffer_get_part(&buffer, first.offset, Position), Position{1, 2})
	testing.expect_value(t, ecs.cmd_buffer_get_part(&buffer, second.offset, Velocity), Velocity{3, 4})
}

@(test)
cmd_buffer_record_set_value_survives_growth :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer, 0, 0)
	defer ecs.cmd_buffer_destroy(&buffer)

	for i in 0 ..< 100 {
		record_value(&buffer, a, .Position, Position{f32(i), f32(-i)})
	}

	testing.expect_value(t, len(buffer.cmds), 100)
	for cmd, i in buffer.cmds {
		set := cmd.(ecs.Cmd_Set_Value(Kind))
		got := ecs.cmd_buffer_get_part(&buffer, set.offset, Position)
		testing.expect_value(t, got, Position{f32(i), f32(-i)})
	}
}

@(test)
cmd_buffer_record_set_value_handles_zero_sized_part :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer)
	defer ecs.cmd_buffer_destroy(&buffer)

	record_value(&buffer, a, .Tag, Tag{})

	cmd := buffer.cmds[0].(ecs.Cmd_Set_Value(Kind))
	testing.expect_value(t, cmd.size, 0)
	testing.expect_value(t, len(buffer.parts), 0)
	testing.expect_value(t, len(ecs.cmd_buffer_get_bytes(&buffer, cmd.offset, cmd.size)), 0)
	testing.expect_value(t, ecs.cmd_buffer_get_part(&buffer, cmd.offset, Tag), Tag{})
}

@(test)
cmd_buffer_record_set_zero_stores_kind :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer)
	defer ecs.cmd_buffer_destroy(&buffer)

	ecs.cmd_buffer_record_set_zero(&buffer, a, .Velocity)

	cmd, ok := buffer.cmds[0].(ecs.Cmd_Set_Zero(Kind))
	testing.expect(t, ok)
	testing.expect_value(t, cmd.thing, a)
	testing.expect_value(t, cmd.kind, Kind.Velocity)
	testing.expect_value(t, len(buffer.parts), 0)
}

@(test)
cmd_buffer_record_remove_stores_kind :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer)
	defer ecs.cmd_buffer_destroy(&buffer)

	ecs.cmd_buffer_record_remove(&buffer, a, .Position)

	cmd, ok := buffer.cmds[0].(ecs.Cmd_Remove(Kind))
	testing.expect(t, ok)
	testing.expect_value(t, cmd.thing, a)
	testing.expect_value(t, cmd.kind, Kind.Position)
}

@(test)
cmd_buffer_keeps_record_order :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, b := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer)
	defer ecs.cmd_buffer_destroy(&buffer)

	record_value(&buffer, a, .Position, Position{1, 2})
	ecs.cmd_buffer_record_set_zero(&buffer, b, .Velocity)
	ecs.cmd_buffer_record_remove(&buffer, a, .Tag)
	ecs.cmd_buffer_record_kill(&buffer, b)

	cmds := buffer.cmds
	testing.expect_value(t, len(cmds), 4)

	_, is_set := cmds[0].(ecs.Cmd_Set_Value(Kind))
	_, is_zero := cmds[1].(ecs.Cmd_Set_Zero(Kind))
	_, is_remove := cmds[2].(ecs.Cmd_Remove(Kind))
	_, is_kill := cmds[3].(ecs.Cmd_Kill)
	testing.expect(t, is_set)
	testing.expect(t, is_zero)
	testing.expect(t, is_remove)
	testing.expect(t, is_kill)
}

// >------------------------------------------------------------------------ Get

@(test)
cmd_buffer_get_bytes_returns_part_bytes :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer)
	defer ecs.cmd_buffer_destroy(&buffer)

	record_value(&buffer, a, .Position, Position{1, 2})
	record_value(&buffer, a, .Velocity, Velocity{3, 4})

	cmd := buffer.cmds[1].(ecs.Cmd_Set_Value(Kind))
	bytes := ecs.cmd_buffer_get_bytes(&buffer, cmd.offset, cmd.size)

	testing.expect_value(t, len(bytes), size_of(Velocity))
	testing.expect_value(t, (^Velocity)(raw_data(bytes))^, Velocity{3, 4})
}

@(test)
cmd_buffer_get_part_reads_misaligned_offset :: proc(t: ^testing.T) {
	things: ecs.Thing_Pool
	a, _ := make_things(&things)
	defer ecs.thing_pool_destroy(&things)
	buffer: Cmd_Buffer
	ecs.cmd_buffer_init(&buffer)
	defer ecs.cmd_buffer_destroy(&buffer)

	// A single byte first pushes the next part to an odd offset.
	record_value(&buffer, a, .Tag, u8(7))
	record_value(&buffer, a, .Target, Aligned{value = 42})

	cmds := buffer.cmds
	byte_cmd := cmds[0].(ecs.Cmd_Set_Value(Kind))
	aligned_cmd := cmds[1].(ecs.Cmd_Set_Value(Kind))

	testing.expect_value(t, aligned_cmd.offset, 1)
	testing.expect_value(t, ecs.cmd_buffer_get_part(&buffer, byte_cmd.offset, u8), 7)
	testing.expect_value(t, ecs.cmd_buffer_get_part(&buffer, aligned_cmd.offset, Aligned).value, 42)
}
