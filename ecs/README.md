# Handles

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

# Things

`Thing` is an opaque handle type: `Handle(Thing_Tag)`, a `u32` with a 20-bit `idx` and a 12-bit `gen` counter.
`THING_NIL` is a nil handle (zeroed out).

`Thing_Pool` is `Handle_Pool(Thing_Tag)` and the `thing_pool_*` procs are aliases of the
`handle_pool_*` ones, except `thing_pool_init`, which fixes the tag and adds a default
capacity. See [Handles](#handles) for the pool design.

# Parts

`Part_Pool` stores one part type as a paged sparse set. It is type-erased: it only knows the part's
size and alignment (from `^runtime.Type_Info`) and an optional `destroy_part` callback.

- `indices` - `PART_POOL_PAGE_COUNT` pages, allocated on demand, mapping a
  thing idx to dense idx + 1. `0` means no part, so a freshly zeroed page is empty.
- `things` / `parts_data` - dense arrays of owners and part bytes, grown by doubling. Removal swaps the
  last part into the hole and updates its sparse entry, so parts stay packed for iteration.

Lookups take a full `Thing` and compare it with the dense owner, so a stale thing never sees the part
of a reused idx. Inserting for a thing that already has the part overwrites it (`destroy_part` runs
on the old value). Inserting with a nil part zero-initialises it. Zero-sized parts (tags) store no data;
`get_part` returns a shared non-nil pointer for them.

The `_unchecked` variants skip validation: `get_part`/`remove` assume the part exists, `insert` assumes it
does not.

# Commands

`Cmd_Pool($P)` records deferred mutations as a `Cmd($P)` union (`Cmd_Kill`, `Cmd_Set_Value`,
`Cmd_Set_Zero`, `Cmd_Remove`) in record order. It only stores commands; applying them is up to the caller.

Part values are copied into a single `parts` byte buffer, packed without padding. `Cmd_Set_Value`
keeps the `offset` and `size` of its bytes. `cmd_pool_get_bytes` returns them as a slice, valid until
the next record, and `cmd_pool_get_part` copies them out as a `T`. No `^T` is handed out because a
packed offset may be misaligned for `T`. Offsets and sizes are `u32`, so the buffer is capped at
`CMD_POOL_MAX_PARTS_SIZE` bytes.

# World

`World($P)` owns a `Thing_Pool`, one `Part_Pool` per registered kind of `P`, an
`Archetype_Pool(P)` and a `Cmd_Pool(P)`.

Mutations come in two flavours:

- `_now` (`set_now`, `add_now`, `remove_now`, `kill_now`) apply immediately and report failure for
  dead things by returning `nil`/`false`.
- `_later` (`set_later`, `add_later`, `remove_later`, `kill_later`) record into the world's own
  `Cmd_Pool`. Kind and type are asserted when recording; liveness is checked when applying, so
  commands for things that are dead by then are skipped. `THING_NIL` is never recorded.

`apply_self` applies the world's buffer in record order and resets it. `apply_other` applies a
buffer recorded elsewhere and leaves it untouched; the caller resets it, and may replay it into
several worlds. `reset` drops unapplied commands.

Part values are moved into the world on apply. The buffer itself never runs `destroy` callbacks:
resetting a buffer that was never applied leaks resources owned by its parts, and applying one
buffer twice hands the same resources to two parts.

`spawn` has no `_later` variant: the thing is needed right away to record commands for it.

# Systems
