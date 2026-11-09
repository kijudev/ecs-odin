package bench

// Shuffles and hierarchy shapes shared by every case. Mirrors common/data.hpp exactly, so the
// checksums of all libraries can be compared.

// >------------------------------------------------------------------ Shuffling

// splitmix64 finalizer.
hash :: proc(i: u64) -> u64 {
	i := i
	i += 0x9E3779B97F4A7C15
	i = (i ~ (i >> 30)) * 0xBF58476D1CE4E5B9
	i = (i ~ (i >> 27)) * 0x94D049BB133111EB
	return i ~ (i >> 31)
}

// 0 .. n-1, shuffled. Filled by the harness before the cases of each size run.
perm: []int

make_perm :: proc(n: int) {
	delete(perm)
	perm = make([]int, n)
	for i in 0 ..< n do perm[i] = i
	for i := n - 1; i > 0; i -= 1 {
		j := int(hash(u64(n) + u64(i)) % u64(i + 1))
		perm[i], perm[j] = perm[j], perm[i]
	}
}

// Whether entity i is in the `permille` part of a sparse setup.
is_sparse :: proc(i, permille: int) -> bool {
	return hash(u64(i)) % 1000 < u64(permille)
}

// >---------------------------------------------------------- Hierarchy shapes

Shape :: enum {
	Tree,
	Forest,
	Chain,
}

// The parent index of entity i, or -1 for a root. Always lower than i.
parent_of :: #force_inline proc(shape: Shape, i: int) -> int {
	switch shape {
	case .Tree:
		return i == 0 ? -1 : (i - 1) / 4
	case .Forest:
		r := i % 7
		root := i - r
		if r == 0 do return -1
		return r <= 2 ? root : root + 1 + (r - 3) / 2
	case .Chain:
		return i % 64 == 0 ? -1 : i - 1
	}
	return -1
}

count_roots :: proc(shape: Shape, n: int) -> int {
	roots := 0
	for i in 0 ..< n do if parent_of(shape, i) < 0 do roots += 1
	return roots
}

// The new parent of a reparented entity c: a random root of the original shape below c. Lower
// than c, so never one of its descendants, and shallow, so depths stay far below flecs' limit
// of 128.
reparent_target :: proc(shape: Shape, c: int) -> int {
	stride := shape == .Tree ? c : shape == .Forest ? 7 : 64
	return stride * int(hash(u64(c)) % u64((c - 1) / stride + 1))
}
