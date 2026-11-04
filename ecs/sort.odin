package ecs

import "base:intrinsics"
import "core:fmt"
import "core:mem"

// >---------------------------------------------------------------------- Utils

sort_apply_perm :: proc(perm: []$I, src, dst: []$T) where intrinsics.type_is_integer($I) {
	fmt.assertf(
		len(src) == len(dst),
		"Source and destination slices must have the same length, got %v and %v.",
		len(src),
		len(dst),
	)

	n := len(src)
	for i := 0; i < n; i += 1 do dst[i] = src[perm[i]]
}

// >-------------------------------------------------------------- Radix Argsort

sort_argsort_u32 :: proc(keys: []u32, perm: []$I) where intrinsics.type_is_integer($I) {
	fmt.assertf(
		len(keys) == len(perm),
		"Keys and permutations must have the same length, got %v and %v.",
		len(keys),
		len(perm),
	)

	mem.zero_slice(perm)

	n := len(keys)
	temp := make([]$I, n, context.temp_allocator)
	count: [256]int

	for shift := 0; shift < 32; shift += 8 {
		for i := 0; i < n; i += 1 do count[(keys[i] >> shift) & 0xFF] += 1
		for i := 1; i < 256; i += 1 do count[i] += count[i - 1]

		for i := n - 1; i >= 0; i -= 1 {
			bucket := (keys[i] >> shift) & 0xFF
			count[bucket] -= 1
			temp[count[bucket]] = $I(i)
		}

		perm, temp = temp, perm
		mem.zero_slice(count[:])
	}

	free_all(context.temp_allocator)
}
