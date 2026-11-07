package ecs

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

Part_Idx :: u32
Part_Set_Indices :: Inline_Paged_Array(Part_Idx, PART_SET_PAGE_COUNT, PART_SET_PAGE_SIZE)

/*
Stores the parts of one kind as a sparse set: `indices` maps `thing.idx` to a slot in the packed
`things` and `parts_data` arrays. The part type is erased, only its size and alignment are kept.
Removing moves the last part into the hole, so the order of parts changes.
*/
Part_Set :: struct {
	part_size:      int,
	part_align:     int,
	indices:        Part_Set_Indices,
	things:         []Thing,
	parts_data:     []byte,
	parts_capacity: int,
	parts_size:     int,
	destroy_proc:   proc(part: rawptr),
	allocator:      mem.Allocator,
}

/*
Holds a part set per kind, plus the type each kind was registered with. A kind has to be
registered before use.
*/
Part_Pool :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	sets:       [K]Part_Set,
	types:      [K]typeid,
	registered: bit_set[K],
	allocator:  mem.Allocator,
}

@(private = "file")
Part_Zero_Sized: byte

// >------------------------------------------------------------------- Part_Set

/*
Initializes the set for parts of the type described by `part_info`. `destroy` runs on a part
whenever the set drops it: on remove, overwrite, reset and destroy. Nothing is allocated until
the first insert.

Asserts:
- `part_info` is not nil.
*/
part_set_init :: proc(
	set: ^Part_Set,
	part_info: ^runtime.Type_Info,
	destroy: proc(part: rawptr) = nil,
	allocator: mem.Allocator = context.allocator,
) {
	assert(part_info != nil, "Part set needs the part type info.")

	set^ = Part_Set {
		part_size      = part_info.size,
		part_align     = part_info.align,
		indices        = {},
		things         = nil,
		parts_data     = nil,
		parts_capacity = 0,
		parts_size     = 0,
		destroy_proc   = destroy,
		allocator      = allocator,
	}

	inline_paged_array_init(&set.indices, allocator)
}

/*
Runs `destroy` on every part, frees the set with the allocator it was initialized with and
zeroes it.
*/
part_set_destroy :: proc(set: ^Part_Set) {
	parts_destroy_all(set)
	inline_paged_array_destroy(&set.indices)

	delete(set.things, set.allocator)
	delete(set.parts_data, set.allocator)
	set^ = Part_Set{}
}

/* Runs `destroy` on every part and removes them all, keeping the allocated memory. */
part_set_reset :: proc(set: ^Part_Set) {
	parts_destroy_all(set)
	inline_paged_array_reset(&set.indices)
	set.parts_size = 0
}

/*
Checks whether the thing has a part in the set.

Returns false for a stale thing whose slot was reused.
*/
part_set_has :: proc(set: ^Part_Set, thing: Thing) -> bool {
	_, ok := dense_idx(set, thing)
	return ok
}

/*
Gets the thing's part.

Returns nil if the thing doesn't have the part. The pointer is valid until a part is inserted
into or removed from the set.
*/
part_set_get :: proc(set: ^Part_Set, thing: Thing) -> rawptr {
	idx, ok := dense_idx(set, thing)
	if !ok do return nil

	return parts_get_unchecked(set, idx)
}

/*
Gets the thing's part without checking it. The thing has to have the part, otherwise the pointer
is garbage.

The pointer is valid until a part is inserted into or removed from the set.
*/
part_set_get_unchecked :: proc(set: ^Part_Set, thing: Thing) -> rawptr {
	return parts_get_unchecked(set, dense_idx_unchecked(set, thing))
}

/*
Inserts a copy of the part, or overwrites the one the thing already has. A nil `part` inserts a
zeroed one. `destroy` runs on the overwritten part, unless `part` points to it.

Returns a pointer to the part in the set, valid until a part is inserted into or removed from
the set.

Asserts:
- `thing` is not THING_NIL.
- no other thing with the same `idx` has a part in the set.
- the set is not full, when the part is new.
*/
part_set_insert :: proc(set: ^Part_Set, thing: Thing, part: rawptr = nil) -> rawptr {
	assert(thing != THING_NIL, "Cannot insert a part for THING_NIL.")

	entry := inline_paged_array_get(&set.indices, int(thing.idx))
	if entry == 0 do return part_set_insert_unchecked(set, thing, part)

	idx := int(entry - 1)
	fmt.assertf(
		set.things[idx] == thing,
		"Cannot insert a part: slot %v belongs to gen %v, not gen %v.",
		thing.idx,
		set.things[idx].gen,
		thing.gen,
	)

	result := parts_get_unchecked(set, idx)
	if result == part do return result

	if set.destroy_proc != nil do set.destroy_proc(result)
	parts_write(set, result, part)

	return result
}

/*
Inserts a copy of the part without checking whether the thing already has one. A nil `part`
inserts a zeroed one. No thing with the same `idx` may have a part in the set, otherwise its part
is left orphaned.

Returns a pointer to the part in the set, valid until a part is inserted into or removed from
the set.

Asserts:
- `thing` is not THING_NIL.
- the set is not full.
*/
part_set_insert_unchecked :: proc(set: ^Part_Set, thing: Thing, part: rawptr = nil) -> rawptr {
	assert(thing != THING_NIL, "Cannot insert a part for THING_NIL.")
	assert(set.parts_size < PART_SET_MAX_CAPACITY, "Part set is full.")

	idx := set.parts_size
	result := parts_append(set, part)

	set.things[idx] = thing
	inline_paged_array_set(&set.indices, int(thing.idx), Part_Idx(idx + 1))

	return result
}

/*
Removes the thing's part and runs `destroy` on it.

Returns false if the thing doesn't have the part.
*/
part_set_remove :: proc(set: ^Part_Set, thing: Thing) -> bool {
	if !part_set_has(set, thing) do return false

	part_set_remove_unchecked(set, thing)
	return true
}

/*
Removes the thing's part without checking it and runs `destroy` on it. The thing has to have the
part.
*/
part_set_remove_unchecked :: proc(set: ^Part_Set, thing: Thing) {
	idx := dense_idx_unchecked(set, thing)
	last_idx := set.parts_size - 1

	if idx != last_idx {
		moved := set.things[last_idx]
		set.things[idx] = moved
		inline_paged_array_set_unchecked(&set.indices, int(moved.idx), Part_Idx(idx + 1))
	}

	inline_paged_array_set_unchecked(&set.indices, int(thing.idx), 0)
	parts_remove_swap(set, idx)
}

/*
Gets the raw bytes of every part, packed, in the same order as `part_set_get_things`.

The slice is valid until a part is inserted into or removed from the set.
*/
part_set_get_parts :: proc(set: ^Part_Set) -> []byte {
	return set.parts_data[:set.parts_size * set.part_size]
}

/*
Gets every thing that has a part in the set, in the same order as `part_set_get_parts`.

The slice is valid until a part is inserted into or removed from the set.
*/
part_set_get_things :: proc(set: ^Part_Set) -> []Thing {
	return set.things[:set.parts_size]
}

// >------------------------------------------------------------------ Part_Pool

/* Initializes the pool with no kinds registered. Nothing is allocated here. */
part_pool_init :: proc(pool: ^Part_Pool($K), allocator: mem.Allocator = context.allocator) {
	pool^ = Part_Pool(K) {
		allocator = allocator,
	}
}

/* Destroys the set of every registered kind and zeroes the pool. */
part_pool_destroy :: proc(pool: ^Part_Pool($K)) {
	for kind in pool.registered {
		part_set_destroy(&pool.sets[kind])
	}

	pool^ = Part_Pool(K){}
}

/* Resets the set of every registered kind. The kinds stay registered. */
part_pool_reset :: proc(pool: ^Part_Pool($K)) {
	for kind in pool.registered {
		part_set_reset(&pool.sets[kind])
	}
}

/*
Registers `kind` as a part of type `T`. `destroy` runs on a part whenever the pool drops it: on
remove, overwrite, reset and destroy.

Asserts:
- `kind` is not registered yet.
*/
part_pool_register :: proc(
	pool: ^Part_Pool($K),
	kind: K,
	$T: typeid,
	destroy: proc(part: rawptr) = nil,
) {
	fmt.assertf(kind not_in pool.registered, "Part kind %v is already registered.", kind)

	pool.types[kind] = T
	pool.registered += {kind}

	part_set_init(&pool.sets[kind], type_info_of(T), destroy, pool.allocator)
}

/* Checks whether `kind` is registered. */
part_pool_is_registered :: proc(pool: ^Part_Pool($K), kind: K) -> bool {
	return kind in pool.registered
}

/* Asserts that `kind` is registered, reporting `loc`. Disabled with ODIN_DISABLE_ASSERT. */
@(disabled = ODIN_DISABLE_ASSERT)
part_pool_assert_registered :: proc(pool: ^Part_Pool($K), kind: K, loc := #caller_location) {
	fmt.assertf(kind in pool.registered, "Part kind %v is not registered.", kind, loc = loc)
}

/*
Asserts that `kind` is registered with type `T`, reporting `loc`. Disabled with
ODIN_DISABLE_ASSERT.
*/
@(disabled = ODIN_DISABLE_ASSERT)
part_pool_assert_type :: proc(pool: ^Part_Pool($K), kind: K, $T: typeid, loc := #caller_location) {
	part_pool_assert_registered(pool, kind, loc)
	fmt.assertf(
		pool.types[kind] == T,
		"Part kind %v is a %v, not a %v.",
		kind,
		pool.types[kind],
		typeid_of(T),
		loc = loc,
	)
}

/*
Counts the things that have a part of this kind.

Asserts:
- `kind` is registered.
*/
part_pool_count_parts :: proc(pool: ^Part_Pool($K), kind: K) -> int {
	part_pool_assert_registered(pool, kind)
	return pool.sets[kind].parts_size
}

/*
Checks whether the thing has the part.

Returns false for a stale thing whose slot was reused.

Asserts:
- `kind` is registered.
*/
part_pool_has :: proc(pool: ^Part_Pool($K), thing: Thing, kind: K) -> bool {
	part_pool_assert_registered(pool, kind)
	return part_set_has(&pool.sets[kind], thing)
}

/*
Gets the thing's part.

Returns nil if the thing doesn't have the part. The pointer is valid until a part of this kind
is inserted or removed.

Asserts:
- `kind` is registered.
- `T` is the type `kind` was registered with.
*/
part_pool_get :: proc(pool: ^Part_Pool($K), thing: Thing, kind: K, $T: typeid) -> ^T {
	part_pool_assert_type(pool, kind, T)
	return cast(^T)part_set_get(&pool.sets[kind], thing)
}

/*
Gets the thing's part without checking it. The thing has to have the part, otherwise the pointer
is garbage.

The pointer is valid until a part of this kind is inserted or removed.

Asserts:
- `kind` is registered.
- `T` is the type `kind` was registered with.
*/
part_pool_get_unchecked :: proc(pool: ^Part_Pool($K), thing: Thing, kind: K, $T: typeid) -> ^T {
	part_pool_assert_type(pool, kind, T)
	return cast(^T)part_set_get_unchecked(&pool.sets[kind], thing)
}

/*
Gets every part of this kind, packed, in the same order as `part_pool_get_things`.

The slice is valid until a part of this kind is inserted or removed.

Asserts:
- `kind` is registered.
- `T` is the type `kind` was registered with.
*/
part_pool_get_parts :: proc(pool: ^Part_Pool($K), kind: K, $T: typeid) -> []T {
	part_pool_assert_type(pool, kind, T)

	set := &pool.sets[kind]
	return ([^]T)(raw_data(set.parts_data))[:set.parts_size]
}

/*
Gets every thing that has a part of this kind, in the same order as `part_pool_get_parts`.

The slice is valid until a part of this kind is inserted or removed.

Asserts:
- `kind` is registered.
*/
part_pool_get_things :: proc(pool: ^Part_Pool($K), kind: K) -> []Thing {
	part_pool_assert_registered(pool, kind)
	return part_set_get_things(&pool.sets[kind])
}

/*
Inserts the part, or overwrites the one the thing already has. See part_set_insert.

Returns a pointer to the part in the pool, valid until a part of this kind is inserted or removed.

Asserts:
- `kind` is registered.
- `T` is the type `kind` was registered with.
- `thing` is not THING_NIL.
- no other thing with the same `idx` has a part of this kind.
*/
part_pool_set_value :: proc(pool: ^Part_Pool($K), thing: Thing, kind: K, part: $T) -> ^T {
	part := part
	return part_pool_set_pointer(pool, thing, kind, &part)
}

/*
Inserts the part without checking whether the thing already has one. See
part_set_insert_unchecked.

Returns a pointer to the part in the pool, valid until a part of this kind is inserted or removed.

Asserts:
- `kind` is registered.
- `T` is the type `kind` was registered with.
- `thing` is not THING_NIL.
- the kind's set is not full.
*/
part_pool_set_value_unchecked :: proc(
	pool: ^Part_Pool($K),
	thing: Thing,
	kind: K,
	part: $T,
) -> ^T {
	part := part
	return part_pool_set_pointer_unchecked(pool, thing, kind, &part)
}

/*
Inserts a copy of the part `part` points to, or overwrites the one the thing already has. A nil
`part` zeroes it. See part_set_insert.

Returns a pointer to the part in the pool, valid until a part of this kind is inserted or removed.

Asserts:
- `kind` is registered.
- `T` is the type `kind` was registered with.
- `thing` is not THING_NIL.
- no other thing with the same `idx` has a part of this kind.
*/
part_pool_set_pointer :: proc(pool: ^Part_Pool($K), thing: Thing, kind: K, part: ^$T) -> ^T {
	part_pool_assert_type(pool, kind, T)
	return cast(^T)part_set_insert(&pool.sets[kind], thing, part)
}

/*
Inserts a copy of the part `part` points to without checking whether the thing already has one. A
nil `part` inserts a zeroed one. See part_set_insert_unchecked.

Returns a pointer to the part in the pool, valid until a part of this kind is inserted or removed.

Asserts:
- `kind` is registered.
- `T` is the type `kind` was registered with.
- `thing` is not THING_NIL.
- the kind's set is not full.
*/
part_pool_set_pointer_unchecked :: proc(
	pool: ^Part_Pool($K),
	thing: Thing,
	kind: K,
	part: ^$T,
) -> ^T {
	part_pool_assert_type(pool, kind, T)
	return cast(^T)part_set_insert_unchecked(&pool.sets[kind], thing, part)
}

/*
Untyped `part_pool_set_pointer`: `part` has to point to a value of the registered type, or be
nil.

Returns a pointer to the part in the pool, valid until a part of this kind is inserted or removed.

Asserts:
- `kind` is registered.
- `thing` is not THING_NIL.
- no other thing with the same `idx` has a part of this kind.
*/
part_pool_set_raw :: proc(pool: ^Part_Pool($K), thing: Thing, kind: K, part: rawptr) -> rawptr {
	part_pool_assert_registered(pool, kind)
	return part_set_insert(&pool.sets[kind], thing, part)
}

/*
Untyped `part_pool_set_pointer_unchecked`: `part` has to point to a value of the registered type,
or be nil.

Returns a pointer to the part in the pool, valid until a part of this kind is inserted or removed.

Asserts:
- `kind` is registered.
- `thing` is not THING_NIL.
- the kind's set is not full.
*/
part_pool_set_raw_unchecked :: proc(
	pool: ^Part_Pool($K),
	thing: Thing,
	kind: K,
	part: rawptr,
) -> rawptr {
	part_pool_assert_registered(pool, kind)
	return part_set_insert_unchecked(&pool.sets[kind], thing, part)
}

/*
Removes the thing's part and runs `destroy` on it.

Returns false if the thing doesn't have the part.

Asserts:
- `kind` is registered.
*/
part_pool_remove :: proc(pool: ^Part_Pool($K), thing: Thing, kind: K) -> bool {
	part_pool_assert_registered(pool, kind)
	return part_set_remove(&pool.sets[kind], thing)
}

/*
Removes the thing's part without checking it and runs `destroy` on it. The thing has to have the
part.

Asserts:
- `kind` is registered.
*/
part_pool_remove_unchecked :: proc(pool: ^Part_Pool($K), thing: Thing, kind: K) {
	part_pool_assert_registered(pool, kind)
	part_set_remove_unchecked(&pool.sets[kind], thing)
}

/*
Removes the thing's part of every registered kind, trying each one. When the thing's kinds are
known, prefer `part_pool_remove_unchecked`.
*/
part_pool_remove_all :: proc(pool: ^Part_Pool($K), thing: Thing) {
	for kind in pool.registered {
		part_set_remove(&pool.sets[kind], thing)
	}
}

// >------------------------------------------------------------------ Internals

@(private = "file")
dense_idx :: proc(set: ^Part_Set, thing: Thing) -> (int, bool) {
	entry := inline_paged_array_get(&set.indices, int(thing.idx))
	if entry == 0 do return 0, false

	idx := int(entry - 1)
	return idx, set.things[idx] == thing
}

@(private = "file")
dense_idx_unchecked :: proc(set: ^Part_Set, thing: Thing) -> int {
	return int(inline_paged_array_get_unchecked(&set.indices, int(thing.idx)) - 1)
}

@(private = "file")
parts_destroy_all :: proc(set: ^Part_Set) {
	if set.destroy_proc == nil do return

	for i in 0 ..< set.parts_size {
		part := parts_get_unchecked(set, i)
		set.destroy_proc(part)
	}
}

@(private = "file")
parts_remove_swap :: proc(set: ^Part_Set, target_idx: int) {
	last_idx := set.parts_size - 1

	target := parts_get_unchecked(set, target_idx)
	last := parts_get_unchecked(set, last_idx)

	if set.destroy_proc != nil do set.destroy_proc(target)
	if target_idx != last_idx do mem.copy(target, last, set.part_size)

	set.parts_size -= 1
}

@(private = "file")
parts_append :: proc(set: ^Part_Set, part: rawptr) -> rawptr {
	// `part` may point into this set, which growing would move.
	data := uintptr(raw_data(set.parts_data))
	in_pool :=
		part != nil && uintptr(part) >= data && uintptr(part) < data + uintptr(len(set.parts_data))
	offset := uintptr(part) - data

	result := parts_allocate(set)

	src := part
	if in_pool do src = rawptr(uintptr(raw_data(set.parts_data)) + offset)
	parts_write(set, result, src)

	return result
}

@(private = "file")
parts_allocate :: proc(set: ^Part_Set) -> rawptr {
	parts_ensure_capacity(set, set.parts_size + 1)

	part := parts_get_unchecked(set, set.parts_size)
	set.parts_size += 1

	return part
}

@(private = "file")
parts_write :: proc(set: ^Part_Set, dst: rawptr, src: rawptr) {
	if set.part_size == 0 do return

	if src != nil {
		mem.copy(dst, src, set.part_size)
	} else {
		mem.zero(dst, set.part_size)
	}
}

@(private = "file")
parts_get_unchecked :: proc(set: ^Part_Set, idx: int) -> rawptr {
	if intrinsics.unlikely(set.part_size == 0) do return &Part_Zero_Sized

	offset := uintptr(idx * set.part_size)
	return rawptr(uintptr(raw_data(set.parts_data)) + offset)
}

@(private = "file")
parts_ensure_capacity :: proc(set: ^Part_Set, capacity: int) {
	if capacity <= set.parts_capacity do return

	new_capacity := set.parts_capacity
	if new_capacity == 0 do new_capacity = 1
	for new_capacity < capacity do new_capacity *= 2

	things, things_err := make([]Thing, new_capacity, set.allocator)
	if things_err != nil do panic("Failed to allocate memory for part set.")

	copy(things, set.things[:set.parts_size])
	delete(set.things, set.allocator)
	set.things = things

	if set.part_size > 0 {
		data, data_err := mem.resize_bytes(
			set.parts_data,
			new_capacity * set.part_size,
			set.part_align,
			set.allocator,
		)
		if data_err != nil do panic("Failed to allocate memory for part set.")

		set.parts_data = data
	}

	set.parts_capacity = new_capacity
}
