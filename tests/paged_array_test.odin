package ecs_tests

import "core:mem"
import "core:testing"

import ecs "../ecs"

Small_Array :: ecs.Inline_Paged_Array(u32, 4, 8)
Struct_Array :: ecs.Inline_Paged_Array(Position, 2, 4)

// >------------------------------------------------------------------ Lifecycle

@(test)
inline_paged_array_init_creates_empty_array :: proc(t: ^testing.T) {
	arr: Small_Array
	ecs.inline_paged_array_init(&arr)
	defer ecs.inline_paged_array_destroy(&arr)

	testing.expect_value(t, ecs.inline_paged_array_capacity(&arr), 32)
	testing.expect_value(t, ecs.inline_paged_array_count_pages(&arr), 0)

	for i in 0 ..< 32 {
		testing.expect_value(t, ecs.inline_paged_array_get(&arr, i), 0)
		testing.expect(t, ecs.inline_paged_array_get_ptr(&arr, i) == nil)
		testing.expect(t, !ecs.inline_paged_array_has_page(&arr, i))
	}
}

@(test)
inline_paged_array_destroy_frees_with_init_allocator :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	arr: Small_Array
	ecs.inline_paged_array_init(&arr, mem.tracking_allocator(&track))
	ecs.inline_paged_array_set(&arr, 0, 1)
	ecs.inline_paged_array_set(&arr, 31, 2)
	testing.expect_value(t, len(track.allocation_map), 2)

	// Destroy runs under the default context.allocator, not the init one.
	ecs.inline_paged_array_destroy(&arr)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
	testing.expect_value(t, ecs.inline_paged_array_count_pages(&arr), 0)
}

@(test)
inline_paged_array_reset_zeroes_and_keeps_pages :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	arr: Small_Array
	ecs.inline_paged_array_init(&arr, mem.tracking_allocator(&track))
	defer ecs.inline_paged_array_destroy(&arr)

	ecs.inline_paged_array_set(&arr, 1, 10)
	ecs.inline_paged_array_set(&arr, 20, 20)
	ecs.inline_paged_array_reset(&arr)

	testing.expect_value(t, ecs.inline_paged_array_count_pages(&arr), 2)
	testing.expect_value(t, len(track.allocation_map), 2)

	for i in 0 ..< 32 {
		testing.expect_value(t, ecs.inline_paged_array_get(&arr, i), 0)
	}

	// Refilling a kept page does not allocate.
	ecs.inline_paged_array_set(&arr, 1, 11)
	testing.expect_value(t, len(track.allocation_map), 2)
	testing.expect_value(t, ecs.inline_paged_array_get(&arr, 1), 11)
}

// >------------------------------------------------------------------ Accessing

@(test)
inline_paged_array_set_allocates_only_its_page :: proc(t: ^testing.T) {
	arr: Small_Array
	ecs.inline_paged_array_init(&arr)
	defer ecs.inline_paged_array_destroy(&arr)

	ecs.inline_paged_array_set(&arr, 9, 7)

	testing.expect_value(t, ecs.inline_paged_array_count_pages(&arr), 1)
	testing.expect(t, !ecs.inline_paged_array_has_page(&arr, 7))
	testing.expect(t, ecs.inline_paged_array_has_page(&arr, 8))
	testing.expect(t, ecs.inline_paged_array_has_page(&arr, 15))
	testing.expect(t, !ecs.inline_paged_array_has_page(&arr, 16))

	testing.expect_value(t, ecs.inline_paged_array_get(&arr, 9), 7)
	testing.expect_value(t, ecs.inline_paged_array_get(&arr, 8), 0)
}

@(test)
inline_paged_array_page_boundaries :: proc(t: ^testing.T) {
	arr: Small_Array
	ecs.inline_paged_array_init(&arr)
	defer ecs.inline_paged_array_destroy(&arr)

	for i in 0 ..< 32 {
		ecs.inline_paged_array_set(&arr, i, u32(i + 100))
	}

	testing.expect_value(t, ecs.inline_paged_array_count_pages(&arr), 4)

	for i in 0 ..< 32 {
		testing.expect_value(t, ecs.inline_paged_array_get(&arr, i), u32(i + 100))
		testing.expect_value(t, ecs.inline_paged_array_get_unchecked(&arr, i), u32(i + 100))
	}
}

@(test)
inline_paged_array_get_ptr_writes_through :: proc(t: ^testing.T) {
	arr: Struct_Array
	ecs.inline_paged_array_init(&arr)
	defer ecs.inline_paged_array_destroy(&arr)

	ptr := ecs.inline_paged_array_ensure(&arr, 5)
	testing.expect_value(t, ptr^, Position{})

	ptr.x = 3
	testing.expect_value(t, ecs.inline_paged_array_get_ptr(&arr, 5)^, Position{3, 0})
	testing.expect_value(t, ecs.inline_paged_array_get(&arr, 5), Position{3, 0})
}

@(test)
inline_paged_array_ensure_keeps_existing_values :: proc(t: ^testing.T) {
	arr: Small_Array
	ecs.inline_paged_array_init(&arr)
	defer ecs.inline_paged_array_destroy(&arr)

	ecs.inline_paged_array_set(&arr, 4, 42)
	ecs.inline_paged_array_ensure(&arr, 5)

	testing.expect_value(t, ecs.inline_paged_array_get(&arr, 4), 42)
	testing.expect_value(t, ecs.inline_paged_array_count_pages(&arr), 1)
}

@(test)
inline_paged_array_set_unchecked_overwrites :: proc(t: ^testing.T) {
	arr: Small_Array
	ecs.inline_paged_array_init(&arr)
	defer ecs.inline_paged_array_destroy(&arr)

	ecs.inline_paged_array_set(&arr, 2, 1)
	ecs.inline_paged_array_set_unchecked(&arr, 2, 2)
	ecs.inline_paged_array_set_unchecked(&arr, 3, 3)

	testing.expect_value(t, ecs.inline_paged_array_get(&arr, 2), 2)
	testing.expect_value(t, ecs.inline_paged_array_get(&arr, 3), 3)
}

// >---------------------------------------------------------------------- Pages

@(test)
inline_paged_array_get_page_and_pages :: proc(t: ^testing.T) {
	arr: Small_Array
	ecs.inline_paged_array_init(&arr)
	defer ecs.inline_paged_array_destroy(&arr)

	testing.expect(t, ecs.inline_paged_array_get_page(&arr, 1) == nil)

	ecs.inline_paged_array_set(&arr, 9, 7)

	page := ecs.inline_paged_array_get_page(&arr, 1)
	testing.expect_value(t, len(page), 8)
	testing.expect_value(t, page[1], 7)

	// The slice aliases the page.
	page[2] = 5
	testing.expect_value(t, ecs.inline_paged_array_get(&arr, 10), 5)

	pages := arr.pages[:]
	testing.expect_value(t, len(pages), 4)
	testing.expect(t, pages[0] == nil)
	testing.expect(t, pages[1] == raw_data(page))
	testing.expect(t, pages[2] == nil)
	testing.expect(t, pages[3] == nil)
}

// >-------------------------------------------------------------------- Asserts

@(test)
inline_paged_array_index_out_of_range_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	arr: Small_Array
	ecs.inline_paged_array_init(&arr)

	testing.expect_assert_message(t, "Paged array index 32 is out of range, the capacity is 32.")
	ecs.inline_paged_array_get(&arr, 32)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
inline_paged_array_page_out_of_range_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	arr: Small_Array
	ecs.inline_paged_array_init(&arr)

	testing.expect_assert_message(t, "Paged array page 4 is out of range, the page count is 4.")
	ecs.inline_paged_array_get_page(&arr, 4)
	testing.fail_now(t, "The call did not assert.")
}
