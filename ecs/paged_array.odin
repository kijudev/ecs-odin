package ecs

import "base:intrinsics"
import "core:fmt"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

/*
A `Paged_Array` whose page table is a fixed array inside the struct, so it needs no allocation
until the first page. `PAGE_SIZE` has to be a power of two.
*/
Inline_Paged_Array :: struct($T: typeid, $PAGE_COUNT: int, $PAGE_SIZE: int) where size_of(T) > 0,
	PAGE_COUNT > 0,
	PAGE_SIZE > 0,
	PAGE_SIZE & (PAGE_SIZE - 1) == 0 {
	pages:     [PAGE_COUNT][^]T,
	allocator: mem.Allocator,
}

/*
A sparse array split into pages of `page_size` elements. The page table is allocated in `init`,
the pages only when something is set in them. Pages never move, so pointers into them stay
valid until `destroy`.
*/
Paged_Array :: struct($T: typeid) where size_of(T) > 0 {
	pages:      [][^]T,
	page_size:  int,
	page_shift: uint,
	allocator:  mem.Allocator,
}

// >--------------------------------------------------------- Inline_Paged_Array

/* Initializes the array. Nothing is allocated until the first page is needed. */
inline_paged_array_init :: proc(
	arr: ^Inline_Paged_Array($T, $C, $S),
	allocator: mem.Allocator = context.allocator,
) {
	arr^ = Inline_Paged_Array(T, C, S) {
		allocator = allocator,
	}
}

/* See paged_array_destroy. */
inline_paged_array_destroy :: proc(arr: ^Inline_Paged_Array($T, $C, $S)) {
	pages_free_all(arr.pages[:], arr.allocator)
	arr^ = Inline_Paged_Array(T, C, S){}
}

/* See paged_array_reset. */
inline_paged_array_reset :: proc(arr: ^Inline_Paged_Array($T, $C, $S)) {
	pages_zero_all(arr.pages[:], S)
}

/* See paged_array_capacity. */
inline_paged_array_capacity :: proc(arr: ^Inline_Paged_Array($T, $C, $S)) -> int {
	return C * S
}

/* See paged_array_count_pages. */
inline_paged_array_count_pages :: proc(arr: ^Inline_Paged_Array($T, $C, $S)) -> int {
	return pages_count(arr.pages[:])
}

/* See paged_array_has_page. */
inline_paged_array_has_page :: proc(arr: ^Inline_Paged_Array($T, $C, $S), idx: int) -> bool {
	page, _ := locate(idx, intrinsics.constant_log2(S), C * S)
	return arr.pages[page] != nil
}

/* See paged_array_get_page. */
inline_paged_array_get_page :: proc(arr: ^Inline_Paged_Array($T, $C, $S), page: int) -> []T {
	check_page(page, C)
	return page_slice(arr.pages[page], S)
}

/* See paged_array_get. */
inline_paged_array_get :: proc(arr: ^Inline_Paged_Array($T, $C, $S), idx: int) -> T {
	page, offset := locate(idx, intrinsics.constant_log2(S), C * S)
	return page_get(arr.pages[page], offset)
}

/* See paged_array_get_ptr. */
inline_paged_array_get_ptr :: proc(arr: ^Inline_Paged_Array($T, $C, $S), idx: int) -> ^T {
	page, offset := locate(idx, intrinsics.constant_log2(S), C * S)
	return page_get_ptr(arr.pages[page], offset)
}

/* See paged_array_get_unchecked. */
inline_paged_array_get_unchecked :: #force_inline proc(
	arr: ^Inline_Paged_Array($T, $C, $S),
	idx: int,
) -> T #no_bounds_check {
	page, offset := locate(idx, intrinsics.constant_log2(S), C * S)
	return arr.pages[page][offset]
}

/* See paged_array_ensure. */
inline_paged_array_ensure :: proc(arr: ^Inline_Paged_Array($T, $C, $S), idx: int) -> ^T {
	page, offset := locate(idx, intrinsics.constant_log2(S), C * S)
	return &page_ensure(&arr.pages[page], S, arr.allocator)[offset]
}

/* See paged_array_set. */
inline_paged_array_set :: proc(arr: ^Inline_Paged_Array($T, $C, $S), idx: int, value: T) {
	inline_paged_array_ensure(arr, idx)^ = value
}

/* See paged_array_set_unchecked. */
inline_paged_array_set_unchecked :: proc(
	arr: ^Inline_Paged_Array($T, $C, $S),
	idx: int,
	value: T,
) {
	page, offset := locate(idx, intrinsics.constant_log2(S), C * S)
	arr.pages[page][offset] = value
}

// >---------------------------------------------------------------- Paged_Array

/*
Initializes the array with a table of `page_count` pages, allocated with `allocator`. No page is
allocated yet.

Asserts:
- `page_count` is greater than 0.
- `page_size` is a power of two.
*/
paged_array_init :: proc(
	arr: ^Paged_Array($T),
	page_count: int,
	page_size: int,
	allocator: mem.Allocator = context.allocator,
) {
	fmt.assertf(page_count > 0, "Paged array needs at least one page, got %v.", page_count)
	fmt.assertf(
		page_size > 0 && page_size & (page_size - 1) == 0,
		"Paged array page size has to be a power of two, got %v.",
		page_size,
	)

	pages, err := make([][^]T, page_count, allocator)
	if err != nil do panic("Failed to allocate memory for paged array.")

	arr^ = Paged_Array(T) {
		pages      = pages,
		page_size  = page_size,
		page_shift = uint(intrinsics.count_trailing_zeros(page_size)),
		allocator  = allocator,
	}
}

/* Frees every page and the page table, then zeroes the array. */
paged_array_destroy :: proc(arr: ^Paged_Array($T)) {
	pages_free_all(arr.pages, arr.allocator)
	delete(arr.pages, arr.allocator)
	arr^ = Paged_Array(T){}
}

/* Zeroes every allocated page. The pages stay allocated. */
paged_array_reset :: proc(arr: ^Paged_Array($T)) {
	pages_zero_all(arr.pages, arr.page_size)
}

/* Gets the number of elements the array can hold, allocated or not. */
paged_array_capacity :: proc(arr: ^Paged_Array($T)) -> int {
	return len(arr.pages) * arr.page_size
}

/* Counts the allocated pages. */
paged_array_count_pages :: proc(arr: ^Paged_Array($T)) -> int {
	return pages_count(arr.pages)
}

/*
Checks whether the page holding element `idx` is allocated.

Asserts:
- `idx` is in range of the capacity.
*/
paged_array_has_page :: proc(arr: ^Paged_Array($T), idx: int) -> bool {
	page, _ := locate(idx, arr.page_shift, paged_array_capacity(arr))
	return arr.pages[page] != nil
}

/*
Gets a whole page by its page index.

Returns nil if the page isn't allocated.

Asserts:
- `page` is in range of the page count.
*/
paged_array_get_page :: proc(arr: ^Paged_Array($T), page: int) -> []T {
	check_page(page, len(arr.pages))
	return page_slice(arr.pages[page], arr.page_size)
}

/*
Gets the element at `idx`.

Returns the zero value if its page isn't allocated.

Asserts:
- `idx` is in range of the capacity.
*/
paged_array_get :: proc(arr: ^Paged_Array($T), idx: int) -> T {
	page, offset := locate(idx, arr.page_shift, paged_array_capacity(arr))
	return page_get(arr.pages[page], offset)
}

/*
Gets a pointer to the element at `idx`.

Returns nil if its page isn't allocated.

Asserts:
- `idx` is in range of the capacity.
*/
paged_array_get_ptr :: proc(arr: ^Paged_Array($T), idx: int) -> ^T {
	page, offset := locate(idx, arr.page_shift, paged_array_capacity(arr))
	return page_get_ptr(arr.pages[page], offset)
}

/*
Gets the element at `idx`. Its page has to be allocated.

Asserts:
- `idx` is in range of the capacity.
*/
paged_array_get_unchecked :: proc(arr: ^Paged_Array($T), idx: int) -> T #no_bounds_check {
	page, offset := locate(idx, arr.page_shift, paged_array_capacity(arr))
	return arr.pages[page][offset]
}

/*
Gets a pointer to the element at `idx`, allocating its page if needed. New pages start zeroed.

Asserts:
- `idx` is in range of the capacity.
*/
paged_array_ensure :: proc(arr: ^Paged_Array($T), idx: int) -> ^T {
	page, offset := locate(idx, arr.page_shift, paged_array_capacity(arr))
	return &page_ensure(&arr.pages[page], arr.page_size, arr.allocator)[offset]
}

/*
Sets the element at `idx`, allocating its page if needed.

Asserts:
- `idx` is in range of the capacity.
*/
paged_array_set :: proc(arr: ^Paged_Array($T), idx: int, value: T) {
	paged_array_ensure(arr, idx)^ = value
}

/*
Sets the element at `idx`. Its page has to be allocated.

Asserts:
- `idx` is in range of the capacity.
*/
paged_array_set_unchecked :: proc(arr: ^Paged_Array($T), idx: int, value: T) {
	page, offset := locate(idx, arr.page_shift, paged_array_capacity(arr))
	arr.pages[page][offset] = value
}

// >------------------------------------------------------------------ Internals

@(private = "file")
locate :: #force_inline proc(
	idx: int,
	page_shift: uint,
	capacity: int,
) -> (
	page: int,
	offset: int,
) {
	fmt.assertf(
		idx >= 0 && idx < capacity,
		"Paged array index %v is out of range, the capacity is %v.",
		idx,
		capacity,
	)

	page = idx >> page_shift
	offset = idx & ((1 << page_shift) - 1)
	return
}

@(private = "file")
check_page :: #force_inline proc(page: int, page_count: int) {
	fmt.assertf(
		page >= 0 && page < page_count,
		"Paged array page %v is out of range, the page count is %v.",
		page,
		page_count,
	)
}

@(private = "file")
page_slice :: #force_inline proc(page: [^]$T, page_size: int) -> []T {
	if page == nil do return nil
	return page[:page_size]
}

@(private = "file")
page_get :: #force_inline proc(page: [^]$T, offset: int) -> T {
	if page == nil do return T{}
	return page[offset]
}

@(private = "file")
page_get_ptr :: #force_inline proc(page: [^]$T, offset: int) -> ^T {
	if page == nil do return nil
	return &page[offset]
}

@(private = "file")
page_ensure :: #force_inline proc(page: ^[^]$T, page_size: int, allocator: mem.Allocator) -> [^]T {
	if page^ == nil {
		data, err := mem.alloc(page_size * size_of(T), align_of(T), allocator)
		if err != nil do panic("Failed to allocate memory for paged array page.")

		page^ = cast([^]T)data
	}

	return page^
}

@(private = "file")
pages_free_all :: proc(pages: [][^]$T, allocator: mem.Allocator) {
	for &page in pages {
		if page != nil do mem.free(page, allocator)
		page = nil
	}
}

@(private = "file")
pages_zero_all :: proc(pages: [][^]$T, page_size: int) {
	for page in pages {
		if page != nil do mem.zero(page, page_size * size_of(T))
	}
}

@(private = "file")
pages_count :: proc(pages: [][^]$T) -> int {
	count := 0
	for page in pages {
		if page != nil do count += 1
	}

	return count
}
