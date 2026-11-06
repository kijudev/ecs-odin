# Errors

There are only three cases:

- **You used it wrong** (an unregistered kind, a mismatched type, an index out of range):
  `assert`. These go away with `-disable-assert`.
- **Something just isn't there** (a dead thing, a missing part): you get `false` or `nil` back.
  When the thing pool is full, `spawn` returns `THING_NIL`. The world treats it as dead, so a
  failed spawn is harmless there. The lower-level pools assert on it instead.
- **Out of memory**: `panic`. No proc returns an allocator error. If that matters, size the pools
  up front or pass an allocator that can't fail.

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

## Part Set

`Part_Set` stores one part type as a paged sparse set. It is type-erased: it only knows the part's
size and alignment (from `^runtime.Type_Info`) and an optional `destroy_part` callback.

- `indices` - an `Inline_Paged_Array` with `PART_SET_PAGE_COUNT` pages mapping a thing idx to
  dense idx + 1. `0` means no part, so a missing or freshly zeroed page is empty.
- `things` / `parts_data` - dense arrays of owners and part bytes, grown by doubling. Removal swaps the
  last part into the hole and updates its sparse entry, so parts stay packed for iteration.

Lookups take a full `Thing` and compare it with the dense owner, so a stale thing never sees the part
of a reused idx. Inserting for a thing that already has the part overwrites it (`destroy_part` runs
on the old value). Inserting with a nil part zero-initialises it. Zero-sized parts (tags) store no data;
`get_part` returns a shared non-nil pointer for them.

The `_unchecked` variants skip validation: `get_part`/`remove` assume the part exists, `insert` assumes it
does not.

## Part Pool

`Part_Pool($P)` is one `Part_Set` per kind of `P`, plus the type each kind was registered with. It
only cares about parts: it doesn't know if a thing is alive or which kinds it has, that is up to
whoever uses it.

Every call asserts that the kind is registered, and the typed ones that the type matches. The
`_unchecked` variants keep these asserts and only skip the runtime checks, the same way as in
`Part_Set`. The asserts are also available on their own as `part_pool_assert_registered` and
`part_pool_assert_type`, and vanish entirely with `-disable-assert`.

Parts are set with `set_value`, `set_pointer` (`nil` zeroes the part) or the untyped `set_raw`.
There are no proc groups. `remove_all` tries every registered kind; if you already know which
kinds a thing has, `remove_unchecked` on those is faster.

# Resources

`Resource_Pool($R)` holds one value per kind of `R`, for things that aren't tied to any thing:
time, input, config. The values are packed into one buffer of a fixed capacity, allocated once in
`init`, so a resource never moves and its pointer stays valid. Registering puts the next resource
behind the previous one, aligned for its type, and panics when it doesn't fit anymore.

A resource starts zeroed and is changed through the pointer from `get`. `reset` runs the
destroyers and zeroes every resource but keeps the registrations; `destroy` runs the destroyers
and frees the buffer.

# Archetypes

`Archetype($P)` is the set of part kinds a thing has. It is a `bit_set[P]` underneath, but only
the `archetype_*` procs touch it: `has`, `insert`, `remove`, `clear`, `is_empty`, `contains`
(every kind of the other one is in it), `is_disjoint` and `intersect`. Iterate it with
`it := archetype_iter_make(a)` and `for kind in archetype_iter_next(&it)`.

`Archetype_Pool($P)` keeps one `Archetype` per thing idx. Like the part pool it doesn't know if a
thing is alive.

# Commands

`Cmd_Pool($P)` records deferred mutations as a `Cmd($P)` union (`Cmd_Kill`, `Cmd_Set_Value`,
`Cmd_Set_Zero`, `Cmd_Remove`) in record order. It only stores commands; applying them is up to the caller.

Part values are copied into a single `parts` byte buffer, packed without padding. `Cmd_Set_Value`
keeps the `offset` and `size` of its bytes. `cmd_pool_get_bytes` returns them as a slice, valid until
the next record, and `cmd_pool_get_part` copies them out as a `T`. No `^T` is handed out because a
packed offset may be misaligned for `T`. Offsets and sizes are `u32`, so the buffer is capped at
`CMD_POOL_MAX_PARTS_SIZE` bytes.

# World

`World($P, $R, $S)` owns a `Thing_Pool`, a `Part_Pool(P)`, an `Archetype_Pool(P)`, a `Cmd_Pool(P)`,
a `Resource_Pool(R)` and a `System_Pool(P, R, S)`, all allocated with the one `pool_allocator`
passed to `world_init`. `S` is the enum of system stages. A world without resources passes an empty enum for `R`.

Resources are reached with `register_resource`, `is_resource_registered` and `get_resource`. They
have no `_now`/`_later` variants, nothing about them is deferred.

Mutations come in two flavours:

- `_now` (`set_now`, `add_now`, `remove_now`, `kill_now`) apply immediately and report failure for
  dead things by returning `nil`/`false`.
- `_later` (`set_later`, `add_later`, `remove_later`, `kill_later`) record into the world's own
  `Cmd_Pool`. Kind and type are asserted when recording; liveness is checked when applying, so
  commands for things that are dead by then are skipped. `THING_NIL` is never recorded.

`apply_self` applies the world's buffer in record order and resets it. `apply_other` applies a
buffer recorded elsewhere and leaves it untouched; the caller resets it, and may replay it into
several worlds. `world_reset` drops unapplied commands, kills every thing and zeroes every
resource, keeping all registrations.

Part values are moved into the world on apply. The buffer itself never runs `destroy` callbacks:
resetting a buffer that was never applied leaks resources owned by its parts, and applying one
buffer twice hands the same resources to two parts.

`spawn` has no `_later` variant: the thing is needed right away to record commands for it.

Systems are `proc(stuff: Stuff(P, R, S))`, scheduled with `world_schedule` into a stage with the
part kinds they read and write. `world_run_stage` runs one stage and then applies the commands its
systems recorded with `apply_self`, so `_later` changes become visible to the next stage.
`world_run` runs every stage in the order of `S`. The stage graph is rebuilt on the next run
whenever systems were scheduled since the last build. Everything runs on one thread for now.
`world_reset` keeps the scheduled systems.

# Stuff and Queries

`Stuff($P, $R, $S)` is what a system gets. It forwards to its world, but only for things, parts
and resources: it cannot register kinds, apply commands or init/destroy/reset the world.

`Query($P, $R, $S)` iterates the things that have every kind of `with` and none of `without`.
`with` cannot be empty and cannot share a kind with `without`. It walks the smallest part set of
`with`, picked in `query_make` and again in `query_refresh`, which also starts the iteration over.
`query.thing` is the current thing (nil once `query_next` returns false), and `query_has` and
`query_get_part` read it.

# API

`api.odin` has the short names (`spawn`, `get_part`, `set_later`, ...). Each one is a proc group
of the `world_`, `stuff_` and `query_` procs, so the handle you pass decides what you may do: a
call a handle has no proc for does not compile. Names with only a world proc are plain aliases.

# Systems

This is going to hurt.
