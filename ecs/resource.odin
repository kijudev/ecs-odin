package ecs

import "base:intrinsics"
import "core:fmt"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

RESOURCE_POOL_DEFAULT_CAPACITY :: 1 << 16

Resource_Pool :: struct($R: typeid) where intrinsics.type_is_enum(R) {
	resources_data:     []byte,
	resources_size:     int,
	resources_capacity: int,
	offsets:            [R]int,
	destroy_fns:         [R]proc(resource: rawptr),
	registered:         bit_set[R],
	types:              [R]typeid,
	allocator:          mem.Allocator,
}

// >-------------------------------------------------------------- Resource_Pool

resource_pool_init :: proc(
	pool: ^Resource_Pool($R),
	capacity: int = RESOURCE_POOL_DEFAULT_CAPACITY,
	allocator := context.allocator,
) {
	fmt.assertf(capacity >= 0, "Resource pool capacity cannot be negative, got %v.", capacity)

	data, err := make([]byte, capacity, allocator)
	if err != nil do panic("Failed to allocate memory for resource pool.")

	pool^ = Resource_Pool(R) {
		resources_data     = data,
		resources_size     = 0,
		resources_capacity = capacity,
		offsets            = [R]int{},
		allocator          = allocator,
	}
}

resource_pool_destroy :: proc(pool: ^Resource_Pool($R)) {
	destroy_all(pool)

	delete(pool.resources_data, pool.allocator)
	pool^ = {}
}

resource_pool_reset :: proc(pool: ^Resource_Pool($R)) {
	destroy_all(pool)
	mem.zero_slice(pool.resources_data[:pool.resources_size])
}

resource_pool_register :: proc(
	pool: ^Resource_Pool($R),
	resource: R,
	$T: typeid,
	destroy: proc(resource: rawptr) = nil,
) {
	fmt.assertf(
		resource not_in pool.registered,
		"Resource %v is already registered in the pool.",
		resource,
	)

	// The buffer never moves, so aligning the address keeps the resource aligned for good.
	base := uintptr(raw_data(pool.resources_data))
	start := mem.align_forward_uintptr(base + uintptr(pool.resources_size), align_of(T))
	offset := int(start - base)

	required_size := offset + size_of(T)
	if required_size > pool.resources_capacity {
		fmt.panicf(
			"Resource pool is out of memory: %v needs %v bytes, the capacity is %v. Consider increasing the capacity.",
			resource,
			required_size,
			pool.resources_capacity,
		)
	}

	pool.resources_size = required_size
	pool.offsets[resource] = offset
	pool.types[resource] = T
	pool.destroy_fns[resource] = destroy
	pool.registered += {resource}
}

resource_pool_is_registered :: proc(pool: ^Resource_Pool($R), resource: R) -> bool {
	return resource in pool.registered
}

@(disabled = ODIN_DISABLE_ASSERT)
resource_pool_assert_registered :: proc(
	pool: ^Resource_Pool($R),
	resource: R,
	loc := #caller_location,
) {
	fmt.assertf(
		resource in pool.registered,
		"Resource %v is not registered in the pool.",
		resource,
		loc = loc,
	)
}

@(disabled = ODIN_DISABLE_ASSERT)
resource_pool_assert_type :: proc(
	pool: ^Resource_Pool($R),
	resource: R,
	$T: typeid,
	loc := #caller_location,
) {
	resource_pool_assert_registered(pool, resource, loc)
	fmt.assertf(
		pool.types[resource] == T,
		"Resource %v is a %v, not a %v.",
		resource,
		pool.types[resource],
		typeid_of(T),
		loc = loc,
	)
}

resource_pool_get :: proc(pool: ^Resource_Pool($R), resource: R, $T: typeid) -> ^T {
	resource_pool_assert_type(pool, resource, T)
	return cast(^T)get_raw(pool, resource)
}

// >------------------------------------------------------------------ Internals

@(private = "file")
destroy_all :: proc(pool: ^Resource_Pool($R)) {
	for resource in pool.registered {
		destroy := pool.destroy_fns[resource]
		if destroy != nil do destroy(get_raw(pool, resource))
	}
}

@(private = "file")
get_raw :: proc(pool: ^Resource_Pool($R), resource: R) -> rawptr {
	offset := pool.offsets[resource]
	return rawptr(uintptr(raw_data(pool.resources_data)) + uintptr(offset))
}
