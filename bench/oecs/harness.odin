package bench

import "core:c"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

// The sampling harness, see "Method" in CASES.md. common/harness.cpp follows the same rules.

MAX_SAMPLES :: 30
MIN_SAMPLES :: 5
WALL_CAP_SAMPLES :: 3
MIN_TIMED_NS :: 0.1e9
WALL_CAP_NS :: 3e9
MIN_RUN_NS :: 50e3

/*
Runs one sample: builds a world (untimed), wraps the measured part in a `timed` or `repeated`
loop, and returns a checksum of the world afterwards.
*/
Case_Proc :: #type proc(s: ^Sampler, n: int) -> f64

Case :: struct {
	group: string,
	name:  string,
	run:   Case_Proc,
}

Sampler :: struct {
	k:                  int, // Runs per repeated sample, picked from the warm-up.
	runs:               int, // Runs in the last sample: 1 for timed, k for repeated.
	left:               int,
	looping:            bool,
	timed:              bool,
	base, live, peak:   int,
	start:              time.Tick,
	took_ns, ns_per_op: f64,
}

/* Use as `for timed(s, ops) { ... }`: times the body once. `ops` is how many operations it does. */
timed :: #force_inline proc(s: ^Sampler, ops: int) -> bool {
	return sample_loop(s, ops, 1)
}

/*
Use as `for repeated(s, ops) { ... }`: times the body k times in a row on the same world, with k
picked by the harness so tiny runs stay measurable. Only for operations that can run again on
their own result.
*/
repeated :: #force_inline proc(s: ^Sampler, ops: int) -> bool {
	return sample_loop(s, ops, s.k)
}

@(private = "file")
sample_loop :: #force_inline proc(s: ^Sampler, ops, runs: int) -> bool {
	if !s.looping {
		s.looping = true
		s.left = runs
		s.runs = runs
		s.live = memory.live - s.base
		memory.peak = memory.live
		s.start = time.tick_now()
	}

	if s.left > 0 {
		s.left -= 1
		return true
	}

	s.took_ns = f64(time.tick_since(s.start))
	s.peak = memory.peak - (s.base + s.live)
	s.ns_per_op = s.took_ns / f64(ops * runs)
	s.looping = false
	s.timed = true
	return false
}

// >------------------------------------------------------------------------ Run

/* Parses `--n 10000,100000` and `--case 'query.*'`, runs the matching cases and prints CSV. */
run :: proc(lib: string, cases: []Case) {
	sizes := []int{10_000, 100_000, 1_000_000}
	patterns: []string

	for i := 1; i + 1 < len(os.args); i += 2 {
		items := strings.split(os.args[i + 1], ",")
		switch os.args[i] {
		case "--n":
			sizes = make([]int, len(items))
			for item, j in items do sizes[j], _ = strconv.parse_int(item)
		case "--case":
			patterns = items
		case:
			fmt.eprintfln("unknown flag %s", os.args[i])
			os.exit(1)
		}
	}

	fmt.println(
		"lib,group,case,n,median_ns_op,min_ns_op,mad_ns_op,samples,runs,live_bytes,peak_bytes,checksum",
	)

	samples := make([]f64, MAX_SAMPLES)
	deviations := make([]f64, MAX_SAMPLES)

	for n in sizes {
		make_perm(n)

		for c in cases {
			id := strings.concatenate({c.group, ".", c.name})
			if !matches(patterns, id) do continue

			s := Sampler {
				k = 1,
			}
			count := 0
			checksum, timed_ns: f64
			wall_start := time.tick_now()

			for sample := 0;; sample += 1 {
				s.base = memory.live
				s.timed = false
				sum := c.run(&s, n)

				if !s.timed {
					fmt.eprintfln("%s never ran a timed or repeated loop", id)
					os.exit(1)
				}

				// The first sample is a warm-up: it gives the checksum and picks k.
				if sample == 0 {
					checksum = sum
					if s.took_ns < MIN_RUN_NS do s.k = int(math.ceil(MIN_RUN_NS / max(s.took_ns, 1)))
					continue
				}

				samples[count] = s.ns_per_op
				count += 1
				timed_ns += s.took_ns

				if count >= MAX_SAMPLES do break
				if count >= MIN_SAMPLES && timed_ns >= MIN_TIMED_NS do break
				if count >= WALL_CAP_SAMPLES && f64(time.tick_since(wall_start)) >= WALL_CAP_NS do break
			}

			mid := median(samples[:count])
			for v, i in samples[:count] do deviations[i] = abs(v - mid)

			fmt.printfln(
				"%s,%s,%s,%d,%.3f,%.3f,%.3f,%d,%d,%d,%d,%d",
				lib,
				c.group,
				c.name,
				n,
				mid,
				slice.min(samples[:count]),
				median(deviations[:count]),
				count,
				s.runs,
				s.live,
				s.peak,
				i64(checksum),
			)
			fmt.eprintfln("  %-14s %-28s n=%-8d %10.2f ns/op", lib, id, n, mid)
		}
	}
}

@(private = "file")
median :: proc(values: []f64) -> f64 {
	slice.sort(values)
	mid := len(values) / 2
	return len(values) % 2 == 1 ? values[mid] : (values[mid - 1] + values[mid]) / 2
}

// Glob match with `*` only, which is all `--case` needs.
@(private = "file")
matches :: proc(patterns: []string, id: string) -> bool {
	if len(patterns) == 0 do return true
	for pattern in patterns do if glob(pattern, id) do return true
	return false
}

@(private = "file")
glob :: proc(pattern, s: string) -> bool {
	if len(pattern) == 0 do return len(s) == 0
	if pattern[0] == '*' {
		for i in 0 ..= len(s) do if glob(pattern[1:], s[i:]) do return true
		return false
	}
	return len(s) > 0 && pattern[0] == s[0] && glob(pattern[1:], s[1:])
}

// >--------------------------------------------------------------------- Memory

/*
Counts every allocation like common/memory.cpp: glibc malloc underneath, sizes from
malloc_usable_size. main installs it as context.allocator.
*/
memory: struct {
	live, peak: int,
}

foreign import libc "system:c"

@(default_calling_convention = "c", private = "file")
foreign libc {
	malloc :: proc(size: c.size_t) -> rawptr ---
	calloc :: proc(count, size: c.size_t) -> rawptr ---
	realloc :: proc(ptr: rawptr, size: c.size_t) -> rawptr ---
	aligned_alloc :: proc(align, size: c.size_t) -> rawptr ---
	free :: proc(ptr: rawptr) ---
	malloc_usable_size :: proc(ptr: rawptr) -> c.size_t ---
}

counting_allocator :: proc() -> mem.Allocator {
	return {procedure = counting_allocator_proc}
}

@(private = "file")
MALLOC_ALIGN :: 16

@(private = "file")
track :: proc(ptr: rawptr) -> rawptr {
	if ptr != nil {
		memory.live += int(malloc_usable_size(ptr))
		memory.peak = max(memory.peak, memory.live)
	}
	return ptr
}

@(private = "file")
untrack :: proc(ptr: rawptr) {
	if ptr != nil do memory.live -= int(malloc_usable_size(ptr))
}

@(private = "file")
counting_alloc :: proc(size, alignment: int, zero: bool) -> rawptr {
	if alignment <= MALLOC_ALIGN do return track(zero ? calloc(1, c.size_t(size)) : malloc(c.size_t(size)))

	rounded := (size + alignment - 1) / alignment * alignment
	ptr := track(aligned_alloc(c.size_t(alignment), c.size_t(rounded)))
	if ptr != nil && zero do mem.zero(ptr, size)
	return ptr
}

@(private = "file")
counting_allocator_proc :: proc(
	data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		if size == 0 do return nil, nil
		ptr := counting_alloc(size, alignment, mode == .Alloc)
		if ptr == nil do return nil, .Out_Of_Memory
		return ([^]byte)(ptr)[:size], nil

	case .Free:
		untrack(old_memory)
		free(old_memory)
		return nil, nil

	case .Resize, .Resize_Non_Zeroed:
		if old_memory == nil {
			return counting_allocator_proc(data, .Alloc, size, alignment, nil, 0, loc)
		}

		ptr: rawptr
		if alignment <= MALLOC_ALIGN {
			untrack(old_memory)
			ptr = track(realloc(old_memory, c.size_t(size)))
		} else {
			ptr = counting_alloc(size, alignment, false)
			if ptr != nil {
				mem.copy(ptr, old_memory, min(old_size, size))
				untrack(old_memory)
				free(old_memory)
			}
		}

		if ptr == nil do return nil, .Out_Of_Memory
		if mode == .Resize && size > old_size {
			mem.zero(rawptr(uintptr(ptr) + uintptr(old_size)), size - old_size)
		}
		return ([^]byte)(ptr)[:size], nil

	case .Query_Features:
		set := (^mem.Allocator_Mode_Set)(old_memory)
		if set != nil {
			set^ = {.Alloc, .Alloc_Non_Zeroed, .Free, .Resize, .Resize_Non_Zeroed, .Query_Features}
		}
		return nil, nil

	case .Free_All, .Query_Info:
		return nil, .Mode_Not_Implemented
	}

	return nil, nil
}
