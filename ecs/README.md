# Things

`Thing` is an opaque handle type. It is a `u32` bit field with two parts: 20-bit `idx` and a 12-bit `gen` counter.
`THING_NIL` is a nil handle (zeroed out).

## `Thing_Pool` design

Thing pool consists of two fixed-size arrays allocated up front:

- `slots` - one `Thing_Slot` per index, a `u16` bit field packing the 12-bit `gen` and an `is_alive` flag.
  Keeping both in one slot means checking a thing is a single memory read.
- `free` - a stack of killed indices that can be reused.

Slot `0` is reserved for `THING_NIL`, so a pool of capacity `N` holds at most `N - 1` things.
`slots_next` is the next never-used index. Spawning pops from the free stack first and only
takes a fresh slot when the stack is empty. Reusing a slot bumps its `gen`, which invalidates
stale handles to it. Fresh slots start at `gen = 0`.

The free stack also leaves room for recycling heuristics later, e.g. reserving a run of slots so
a bunch of things are allocated close to one another.

`gen` is 12 bits, so it wraps after `THING_MAX_GEN` (4096) reuses of the same slot. A handle that
is exactly that many generations stale becomes valid again. This is the trade-off for
packing a handle into a `u32`.

# Parts

# Systems
