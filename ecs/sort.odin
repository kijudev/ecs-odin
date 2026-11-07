package ecs

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:mem"

// >---------------------------------------------------------------------- Utils

/*
Gathers `src` into `dst` by the permutation: `dst[i] = src[perm[i]]`. `src` and `dst` must not
overlap.

Asserts:
- `src`, `dst` and `perm` have the same length.
*/
sort_apply_perm :: proc(perm: []$I, src, dst: []$T) where intrinsics.type_is_integer(I) {
	fmt.assertf(
		len(src) == len(dst),
		"Source and destination slices must have the same length, got %v and %v.",
		len(src),
		len(dst),
	)
	fmt.assertf(
		len(perm) == len(src),
		"Permutation and source slices must have the same length, got %v and %v.",
		len(perm),
		len(src),
	)

	n := len(src)
	for i := 0; i < n; i += 1 do dst[i] = src[perm[i]]
}

// >-------------------------------------------------------------- Radix Argsort

/*
Fills `perm` with the indices of `keys` in ascending key order, without moving `keys`. The sort is
stable, so equal keys keep their order. `I` has to fit `len(keys) - 1`. Scratch memory comes
from the temp allocator.

Asserts:
- `keys` and `perm` have the same length.
*/
sort_argsort_u32 :: proc(keys: []u32, perm: []$I) where intrinsics.type_is_integer(I) {
	fmt.assertf(
		len(keys) == len(perm),
		"Keys and permutations must have the same length, got %v and %v.",
		len(keys),
		len(perm),
	)

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	n := len(keys)
	for i := 0; i < n; i += 1 do perm[i] = I(i)

	src, dst := perm, make([]I, n, context.temp_allocator)
	count: [256]int

	for shift: uint = 0; shift < 32; shift += 8 {
		for i := 0; i < n; i += 1 do count[(keys[src[i]] >> shift) & 0xFF] += 1
		for i := 1; i < 256; i += 1 do count[i] += count[i - 1]

		for i := n - 1; i >= 0; i -= 1 {
			bucket := (keys[src[i]] >> shift) & 0xFF
			count[bucket] -= 1
			dst[count[bucket]] = src[i]
		}

		src, dst = dst, src
		mem.zero_slice(count[:])
	}
}
