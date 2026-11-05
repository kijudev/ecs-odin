package ecs_tests

import "base:runtime"
import "core:math/rand"
import "core:slice"
import "core:testing"

import ecs "../ecs"

// Reference argsort: stable sort of indices by key.
reference_argsort_u32 :: proc(keys: []u32, allocator := context.allocator) -> []int {
	perm := make([]int, len(keys), allocator)
	for i in 0 ..< len(perm) do perm[i] = i
	// Insertion sort keeps it obviously stable and independent of the code under test.
	for i in 1 ..< len(perm) {
		j := i
		for j > 0 && keys[perm[j - 1]] > keys[perm[j]] {
			perm[j - 1], perm[j] = perm[j], perm[j - 1]
			j -= 1
		}
	}

	return perm
}

expect_argsort_u32 :: proc(t: ^testing.T, keys: []u32, loc := #caller_location) {
	perm := make([]int, len(keys))
	defer delete(perm)
	ecs.sort_argsort_u32(keys, perm)

	expected := reference_argsort_u32(keys)
	defer delete(expected)

	testing.expectf(t, slice.equal(perm, expected), "keys %v: got %v, want %v", keys, perm, expected, loc = loc)
}

// >-------------------------------------------------------------- Radix Argsort

@(test)
sort_argsort_u32_empty :: proc(t: ^testing.T) {
	expect_argsort_u32(t, {})
}

@(test)
sort_argsort_u32_single :: proc(t: ^testing.T) {
	expect_argsort_u32(t, {42})
}

@(test)
sort_argsort_u32_sorted_and_reversed :: proc(t: ^testing.T) {
	expect_argsort_u32(t, {1, 2, 3, 4, 5})
	expect_argsort_u32(t, {5, 4, 3, 2, 1})
}

@(test)
sort_argsort_u32_low_byte_only :: proc(t: ^testing.T) {
	// All keys share the upper three bytes, so only the first pass separates them.
	keys := []u32{3, 1, 2, 0}
	perm := make([]int, len(keys))
	defer delete(perm)

	ecs.sort_argsort_u32(keys, perm)
	testing.expect(t, slice.equal(perm, []int{3, 1, 2, 0}))
}

@(test)
sort_argsort_u32_every_byte_matters :: proc(t: ^testing.T) {
	expect_argsort_u32(t, {0x0000_0100, 0x0000_0001, 0x0001_0000, 0x0100_0000, 0x0000_00FF, 0})
	expect_argsort_u32(t, {0x0102_0304, 0x0102_0403, 0x0201_0304, 0x0102_0304, 0x0101_FFFF})
}

@(test)
sort_argsort_u32_extremes :: proc(t: ^testing.T) {
	expect_argsort_u32(t, {max(u32), 0, max(u32) - 1, 1, 0x8000_0000, 0x7FFF_FFFF})
}

@(test)
sort_argsort_u32_is_stable :: proc(t: ^testing.T) {
	keys := []u32{7, 3, 7, 3, 7, 0x0100_0003, 3}
	perm := make([]int, len(keys))
	defer delete(perm)

	ecs.sort_argsort_u32(keys, perm)
	testing.expect(t, slice.equal(perm, []int{1, 3, 6, 0, 2, 4, 5}), "equal keys must keep index order")
}

@(test)
sort_argsort_u32_random_matches_reference :: proc(t: ^testing.T) {
	state := rand.create(0xEC5)
	context.random_generator = rand.default_random_generator(&state)

	for n in ([]int{2, 3, 17, 255, 256, 257, 1000}) {
		keys := make([]u32, n)
		defer delete(keys)

		// Full range, and a narrow range to force lots of duplicates.
		for &k in keys do k = rand.uint32()
		expect_argsort_u32(t, keys)
		for &k in keys do k = rand.uint32() % 8
		expect_argsort_u32(t, keys)
	}
}

@(test)
sort_argsort_u32_small_index_type :: proc(t: ^testing.T) {
	keys := []u32{0x0300, 0x0001, 0x0200, 0x0002}
	perm := make([]u16, len(keys))
	defer delete(perm)

	ecs.sort_argsort_u32(keys, perm)
	testing.expect(t, slice.equal(perm, []u16{1, 3, 2, 0}))
}

@(test)
sort_argsort_u32_does_not_modify_keys :: proc(t: ^testing.T) {
	keys := []u32{0x0300, 0x0001, 0x0200, 0x0002}
	original := slice.clone(keys)
	defer delete(original)
	perm := make([]int, len(keys))
	defer delete(perm)

	ecs.sort_argsort_u32(keys, perm)
	testing.expect(t, slice.equal(keys, original))
}

@(test)
sort_argsort_u32_leaves_callers_temp_allocations_alone :: proc(t: ^testing.T) {
	temp := (^runtime.Default_Temp_Allocator)(context.temp_allocator.data)

	callers := make([]u8, 64, context.temp_allocator)
	slice.fill(callers, 0xAB)
	used := temp.arena.total_used

	keys := []u32{3, 1, 2}
	perm := make([]int, len(keys))
	defer delete(perm)
	ecs.sort_argsort_u32(keys, perm)

	// Scratch space is released, but the caller's allocations are not.
	testing.expect_value(t, temp.arena.total_used, used)

	// A follow-up temp allocation must not reuse the caller's buffer.
	next := make([]u8, 64, context.temp_allocator)
	slice.fill(next, 0xCD)
	testing.expect(t, slice.all_of(callers, 0xAB), "caller's temp buffer was clobbered")
}

// >---------------------------------------------------------------------- Utils

@(test)
sort_apply_perm_gathers :: proc(t: ^testing.T) {
	src := []string{"a", "b", "c", "d"}
	dst := make([]string, len(src))
	defer delete(dst)

	ecs.sort_apply_perm([]int{2, 0, 3, 1}, src, dst)
	testing.expect(t, slice.equal(dst, []string{"c", "a", "d", "b"}))
}

@(test)
sort_apply_perm_with_argsort_sorts :: proc(t: ^testing.T) {
	keys := []u32{0x0102, 0x0201, 0x0003, 0x0101}
	perm := make([]u32, len(keys))
	defer delete(perm)
	sorted := make([]u32, len(keys))
	defer delete(sorted)

	ecs.sort_argsort_u32(keys, perm)
	ecs.sort_apply_perm(perm, keys, sorted)
	testing.expect(t, slice.equal(sorted, []u32{0x0003, 0x0101, 0x0102, 0x0201}))
}
