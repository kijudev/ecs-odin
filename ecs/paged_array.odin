package ecs

import "base:intrinsics"
import "core:fmt"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

// Page count and size are compile-time constants, so the page table lives inline in the struct.
Inline_Paged_Array :: struct($T: typeid, $PAGE_COUNT: int, $PAGE_SIZE: int) where size_of(T) > 0,
	PAGE_COUNT > 0,
	PAGE_SIZE > 0,
	PAGE_SIZE & (PAGE_SIZE - 1) == 0 {
	pages:     [PAGE_COUNT][^]T,
	allocator: mem.Allocator,
}

// Page count and size are chosen in `paged_array_init`, the page table is allocated there.
Paged_Array :: struct($T: typeid) where size_of(T) > 0 {
	pages:      [][^]T,
	page_size:  int,
	page_shift: uint,
	allocator:  mem.Allocator,
}

// >--------------------------------------------------------- Inline_Paged_Array

inline_paged_array_init :: proc(
	arr: ^Inline_Paged_Array($T, $C, $S),
	allocator: mem.Allocator = context.allocator,
) {
	arr^ = Inline_Paged_Array(T, C, S) {
		allocator = allocator,
	}
}

inline_paged_array_destroy :: proc(arr: ^Inline_Paged_Array($T, $C, $S)) {
	pages_free_all(arr.pages[:], arr.allocator)
	arr^ = Inline_Paged_Array(T, C, S){}
}

// Zeroes every allocated page and keeps it, so refilling does not allocate again.
inline_paged_array_reset :: proc(arr: ^Inline_Paged_Array($T, $C, $S)) {
	pages_zero_all(arr.pages[:], S)
}

inline_paged_array_capacity :: proc(arr: ^Inline_Paged_Array($T, $C, $S)) -> int {
	return C * S
}

inline_paged_array_count_pages :: proc(arr: ^Inline_Paged_Array($T, $C, $S)) -> int {
	return pages_count(arr.pages[:])
}

inline_paged_array_has_page :: proc(arr: ^Inline_Paged_Array($T, $C, $S), idx: int) -> bool {
	page, _ := locate(idx, intrinsics.constant_log2(S), C * S)
	return arr.pages[page] != nil
}

// Returns nil when the page is not allocated.
inline_paged_array_get_page :: proc(arr: ^Inline_Paged_Array($T, $C, $S), page: int) -> []T {
	check_page(page, C)
	return page_slice(arr.pages[page], S)
}

// Not allocated pages are nil.
inline_paged_array_get_pages :: proc(arr: ^Inline_Paged_Array($T, $C, $S)) -> [][^]T {
	return arr.pages[:]
}

// Returns the zero value when the page of `idx` is not allocated.
inline_paged_array_get :: proc(arr: ^Inline_Paged_Array($T, $C, $S), idx: int) -> T {
	page, offset := locate(idx, intrinsics.constant_log2(S), C * S)
	return page_get(arr.pages[page], offset)
}

// Returns nil when the page of `idx` is not allocated.
inline_paged_array_get_ptr :: proc(arr: ^Inline_Paged_Array($T, $C, $S), idx: int) -> ^T {
	page, offset := locate(idx, intrinsics.constant_log2(S), C * S)
	return page_get_ptr(arr.pages[page], offset)
}

// Assumes the page of `idx` is allocated.
inline_paged_array_get_unchecked :: proc(arr: ^Inline_Paged_Array($T, $C, $S), idx: int) -> T {
	page, offset := locate(idx, intrinsics.constant_log2(S), C * S)
	return arr.pages[page][offset]
}

// Allocates the page of `idx` if needed.
inline_paged_array_ensure :: proc(arr: ^Inline_Paged_Array($T, $C, $S), idx: int) -> ^T {
	page, offset := locate(idx, intrinsics.constant_log2(S), C * S)
	return &page_ensure(&arr.pages[page], S, arr.allocator)[offset]
}

inline_paged_array_set :: proc(arr: ^Inline_Paged_Array($T, $C, $S), idx: int, value: T) {
	inline_paged_array_ensure(arr, idx)^ = value
}

// Assumes the page of `idx` is allocated.
inline_paged_array_set_unchecked :: proc(
	arr: ^Inline_Paged_Array($T, $C, $S),
	idx: int,
	value: T,
) {
	page, offset := locate(idx, intrinsics.constant_log2(S), C * S)
	arr.pages[page][offset] = value
}

// >---------------------------------------------------------------- Paged_Array

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

paged_array_destroy :: proc(arr: ^Paged_Array($T)) {
	pages_free_all(arr.pages, arr.allocator)
	delete(arr.pages, arr.allocator)
	arr^ = Paged_Array(T){}
}

// Zeroes every allocated page and keeps it, so refilling does not allocate again.
paged_array_reset :: proc(arr: ^Paged_Array($T)) {
	pages_zero_all(arr.pages, arr.page_size)
}

paged_array_capacity :: proc(arr: ^Paged_Array($T)) -> int {
	return len(arr.pages) * arr.page_size
}

paged_array_count_pages :: proc(arr: ^Paged_Array($T)) -> int {
	return pages_count(arr.pages)
}

paged_array_has_page :: proc(arr: ^Paged_Array($T), idx: int) -> bool {
	page, _ := locate(idx, arr.page_shift, paged_array_capacity(arr))
	return arr.pages[page] != nil
}

// Returns nil when the page is not allocated.
paged_array_get_page :: proc(arr: ^Paged_Array($T), page: int) -> []T {
	check_page(page, len(arr.pages))
	return page_slice(arr.pages[page], arr.page_size)
}

// Not allocated pages are nil.
paged_array_get_pages :: proc(arr: ^Paged_Array($T)) -> [][^]T {
	return arr.pages
}

// Returns the zero value when the page of `idx` is not allocated.
paged_array_get :: proc(arr: ^Paged_Array($T), idx: int) -> T {
	page, offset := locate(idx, arr.page_shift, paged_array_capacity(arr))
	return page_get(arr.pages[page], offset)
}

// Returns nil when the page of `idx` is not allocated.
paged_array_get_ptr :: proc(arr: ^Paged_Array($T), idx: int) -> ^T {
	page, offset := locate(idx, arr.page_shift, paged_array_capacity(arr))
	return page_get_ptr(arr.pages[page], offset)
}

// Assumes the page of `idx` is allocated.
paged_array_get_unchecked :: proc(arr: ^Paged_Array($T), idx: int) -> T {
	page, offset := locate(idx, arr.page_shift, paged_array_capacity(arr))
	return arr.pages[page][offset]
}

// Allocates the page of `idx` if needed.
paged_array_ensure :: proc(arr: ^Paged_Array($T), idx: int) -> ^T {
	page, offset := locate(idx, arr.page_shift, paged_array_capacity(arr))
	return &page_ensure(&arr.pages[page], arr.page_size, arr.allocator)[offset]
}

paged_array_set :: proc(arr: ^Paged_Array($T), idx: int, value: T) {
	paged_array_ensure(arr, idx)^ = value
}

// Assumes the page of `idx` is allocated.
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
