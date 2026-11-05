package ecs

import "core:thread"
// >-------------------------------------------------------- Constants and Types

Job :: struct($T: typeid) {
	data: ^T,
	exec: proc(data: ^T),
}

Job_Pool :: struct($T: typeid) {
	jobs:          []Job($T),
	jobs_size:     int,
	jobs_capacity: int,
	threads:       []^thread.Thread,
	allocator:     mem.Allocator,
}

// >------------------------------------------------------------------- Job_Pool
