# Utils

## `Handle` and `Handle_Pool`

`Handle($T)` is an opaque, typed handle. It wraps a `u32` bit field with two parts: 20-bit `idx`
and a 12-bit `gen` counter. `T` is only a tag, so `Handle(Texture)` and `Handle(Mesh)` can't be
mixed up, at no runtime cost. A zeroed handle is nil.

`Handle_Pool($T)` only hands out and validates handles; it stores no data. Anything that needs
data per handle keeps its own array indexed by `handle.idx` and checks the handle against the
pool before touching it.

The pool consists of two fixed-size arrays allocated up front:

- `slots` - one `Handle_Slot` per index, a `u16` bit field packing the 12-bit `gen` and an `is_alive` flag.
  Keeping both in one slot means checking a handle is a single memory read.
- `free` - a stack of killed indices that can be reused.

Slot `0` is reserved for the nil handle, so a pool of capacity `N` holds at most `N - 1` handles.
`slots_next` is the next never-used index. Spawning pops from the free stack first and only
takes a fresh slot when the stack is empty. Reusing a slot bumps its `gen`, which invalidates
stale handles to it. Fresh slots start at `gen = 0`.

The free stack also leaves room for recycling heuristics later, e.g. reserving a run of slots so
a bunch of handles are allocated close to one another.

`gen` is 12 bits, so it wraps after `HANDLE_MAX_GEN` (4096) reuses of the same slot. A handle that
is exactly that many generations stale becomes valid again. This is the trade-off for
packing a handle into a `u32`.
