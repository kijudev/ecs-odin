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

// >---------------------------------------------------------------- Paged_Array

@(test)
paged_array_init_creates_empty_array :: proc(t: ^testing.T) {
	arr: ecs.Paged_Array(u32)
	ecs.paged_array_init(&arr, 4, 8)
	defer ecs.paged_array_destroy(&arr)

	testing.expect_value(t, ecs.paged_array_capacity(&arr), 32)
	testing.expect_value(t, ecs.paged_array_count_pages(&arr), 0)

	for i in 0 ..< 32 {
		testing.expect_value(t, ecs.paged_array_get(&arr, i), 0)
		testing.expect(t, ecs.paged_array_get_ptr(&arr, i) == nil)
		testing.expect(t, !ecs.paged_array_has_page(&arr, i))
	}
}

@(test)
paged_array_destroy_frees_with_init_allocator :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	arr: ecs.Paged_Array(u32)
	ecs.paged_array_init(&arr, 4, 8, mem.tracking_allocator(&track))
	testing.expect_value(t, len(track.allocation_map), 1) // the page table

	ecs.paged_array_set(&arr, 0, 1)
	ecs.paged_array_set(&arr, 31, 2)
	testing.expect_value(t, len(track.allocation_map), 3)

	// Destroy runs under the default context.allocator, not the init one.
	ecs.paged_array_destroy(&arr)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
paged_array_reset_zeroes_and_keeps_pages :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	arr: ecs.Paged_Array(u32)
	ecs.paged_array_init(&arr, 4, 8, mem.tracking_allocator(&track))
	defer ecs.paged_array_destroy(&arr)

	ecs.paged_array_set(&arr, 1, 10)
	ecs.paged_array_set(&arr, 20, 20)
	ecs.paged_array_reset(&arr)

	testing.expect_value(t, ecs.paged_array_count_pages(&arr), 2)
	testing.expect_value(t, len(track.allocation_map), 3)

	for i in 0 ..< 32 {
		testing.expect_value(t, ecs.paged_array_get(&arr, i), 0)
	}

	// Refilling a kept page does not allocate.
	ecs.paged_array_set(&arr, 1, 11)
	testing.expect_value(t, len(track.allocation_map), 3)
	testing.expect_value(t, ecs.paged_array_get(&arr, 1), 11)
}

@(test)
paged_array_set_allocates_only_its_page :: proc(t: ^testing.T) {
	arr: ecs.Paged_Array(u32)
	ecs.paged_array_init(&arr, 4, 8)
	defer ecs.paged_array_destroy(&arr)

	ecs.paged_array_set(&arr, 9, 7)

	testing.expect_value(t, ecs.paged_array_count_pages(&arr), 1)
	testing.expect(t, !ecs.paged_array_has_page(&arr, 7))
	testing.expect(t, ecs.paged_array_has_page(&arr, 8))
	testing.expect(t, ecs.paged_array_has_page(&arr, 15))
	testing.expect(t, !ecs.paged_array_has_page(&arr, 16))

	testing.expect_value(t, ecs.paged_array_get(&arr, 9), 7)
	testing.expect_value(t, ecs.paged_array_get(&arr, 8), 0)
}

@(test)
paged_array_page_boundaries :: proc(t: ^testing.T) {
	arr: ecs.Paged_Array(u32)
	ecs.paged_array_init(&arr, 4, 8)
	defer ecs.paged_array_destroy(&arr)

	for i in 0 ..< 32 {
		ecs.paged_array_set(&arr, i, u32(i + 100))
	}

	testing.expect_value(t, ecs.paged_array_count_pages(&arr), 4)

	for i in 0 ..< 32 {
		testing.expect_value(t, ecs.paged_array_get(&arr, i), u32(i + 100))
		testing.expect_value(t, ecs.paged_array_get_unchecked(&arr, i), u32(i + 100))
	}
}

@(test)
paged_array_runtime_page_sizes :: proc(t: ^testing.T) {
	sizes := [?]int{1, 2, 16, 1024}

	for size in sizes {
		arr: ecs.Paged_Array(u32)
		ecs.paged_array_init(&arr, 3, size)
		defer ecs.paged_array_destroy(&arr)

		capacity := ecs.paged_array_capacity(&arr)
		testing.expect_value(t, capacity, 3 * size)

		// First and last slot of every page.
		for page in 0 ..< 3 {
			first := page * size
			last := first + size - 1
			ecs.paged_array_set(&arr, first, u32(first + 1))
			ecs.paged_array_set(&arr, last, u32(last + 1))
		}

		for page in 0 ..< 3 {
			first := page * size
			last := first + size - 1
			testing.expect_value(t, ecs.paged_array_get(&arr, first), u32(first + 1))
			testing.expect_value(t, ecs.paged_array_get(&arr, last), u32(last + 1))
		}

		testing.expect_value(t, ecs.paged_array_count_pages(&arr), 3)
	}
}

@(test)
paged_array_get_ptr_writes_through :: proc(t: ^testing.T) {
	arr: ecs.Paged_Array(Position)
	ecs.paged_array_init(&arr, 2, 4)
	defer ecs.paged_array_destroy(&arr)

	ptr := ecs.paged_array_ensure(&arr, 5)
	testing.expect_value(t, ptr^, Position{})

	ptr.x = 3
	testing.expect_value(t, ecs.paged_array_get_ptr(&arr, 5)^, Position{3, 0})
	testing.expect_value(t, ecs.paged_array_get(&arr, 5), Position{3, 0})
}

@(test)
paged_array_ensure_keeps_existing_values :: proc(t: ^testing.T) {
	arr: ecs.Paged_Array(u32)
	ecs.paged_array_init(&arr, 4, 8)
	defer ecs.paged_array_destroy(&arr)

	ecs.paged_array_set(&arr, 4, 42)
	ecs.paged_array_ensure(&arr, 5)

	testing.expect_value(t, ecs.paged_array_get(&arr, 4), 42)
	testing.expect_value(t, ecs.paged_array_count_pages(&arr), 1)
}

@(test)
paged_array_set_unchecked_overwrites :: proc(t: ^testing.T) {
	arr: ecs.Paged_Array(u32)
	ecs.paged_array_init(&arr, 4, 8)
	defer ecs.paged_array_destroy(&arr)

	ecs.paged_array_set(&arr, 2, 1)
	ecs.paged_array_set_unchecked(&arr, 2, 2)
	ecs.paged_array_set_unchecked(&arr, 3, 3)

	testing.expect_value(t, ecs.paged_array_get(&arr, 2), 2)
	testing.expect_value(t, ecs.paged_array_get(&arr, 3), 3)
}

@(test)
paged_array_aligned_values :: proc(t: ^testing.T) {
	arr: ecs.Paged_Array(Aligned)
	ecs.paged_array_init(&arr, 2, 4)
	defer ecs.paged_array_destroy(&arr)

	for i in 0 ..< 8 {
		ptr := ecs.paged_array_ensure(&arr, i)
		testing.expect_value(t, uintptr(ptr) % align_of(Aligned), 0)
		ptr.value = i
	}

	for i in 0 ..< 8 {
		testing.expect_value(t, ecs.paged_array_get(&arr, i).value, i)
	}
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

@(test)
paged_array_get_page_and_pages :: proc(t: ^testing.T) {
	arr: ecs.Paged_Array(u32)
	ecs.paged_array_init(&arr, 4, 8)
	defer ecs.paged_array_destroy(&arr)

	testing.expect(t, ecs.paged_array_get_page(&arr, 1) == nil)

	ecs.paged_array_set(&arr, 9, 7)

	page := ecs.paged_array_get_page(&arr, 1)
	testing.expect_value(t, len(page), 8)
	testing.expect_value(t, page[1], 7)

	// The slice aliases the page.
	page[2] = 5
	testing.expect_value(t, ecs.paged_array_get(&arr, 10), 5)

	pages := arr.pages
	testing.expect_value(t, len(pages), 4)
	testing.expect(t, pages[0] == nil)
	testing.expect(t, pages[1] == raw_data(page))
	testing.expect(t, pages[2] == nil)
	testing.expect(t, pages[3] == nil)
}

@(test)
paged_array_reset_keeps_page_slices_valid :: proc(t: ^testing.T) {
	arr: ecs.Paged_Array(u32)
	ecs.paged_array_init(&arr, 2, 4)
	defer ecs.paged_array_destroy(&arr)

	for i in 0 ..< 8 {
		ecs.paged_array_set(&arr, i, u32(i + 1))
	}

	page := ecs.paged_array_get_page(&arr, 1)
	ecs.paged_array_reset(&arr)

	testing.expect(t, raw_data(ecs.paged_array_get_page(&arr, 1)) == raw_data(page))
	for value in page {
		testing.expect_value(t, value, 0)
	}
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

@(test)
paged_array_page_out_of_range_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	// The assert skips any cleanup, so take the page table from the stack instead of the heap.
	backing: [256]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])

	arr: ecs.Paged_Array(u32)
	ecs.paged_array_init(&arr, 4, 8, mem.arena_allocator(&arena))

	testing.expect_assert_message(t, "Paged array page -1 is out of range, the page count is 4.")
	ecs.paged_array_get_page(&arr, -1)
	testing.fail_now(t, "The call did not assert.")
}

@(test)
paged_array_page_size_not_power_of_two_asserts :: proc(t: ^testing.T) {
	// Nothing to check when asserts are compiled out.
	when ODIN_DISABLE_ASSERT do return

	arr: ecs.Paged_Array(u32)

	testing.expect_assert_message(t, "Paged array page size has to be a power of two, got 6.")
	ecs.paged_array_init(&arr, 4, 6)
	testing.fail_now(t, "The call did not assert.")
}
