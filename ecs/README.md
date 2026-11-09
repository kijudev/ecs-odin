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

`gen` is 12 bits, so it wraps after `HANDLE_GEN_COUNT` (4096) reuses of the same slot. A handle that
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
size and alignment (from `^runtime.Type_Info`) and an optional `destroy` callback.

- `indices` - an `Inline_Paged_Array` with `PART_SET_PAGE_COUNT` pages mapping a thing idx to
  dense idx + 1. `0` means no part, so a missing or freshly zeroed page is empty.
- `things` / `parts_data` - dense arrays of owners and part bytes, grown by doubling. Removal swaps the
  last part into the hole and updates its sparse entry, so parts stay packed for iteration.

Lookups take a full `Thing` and compare it with the dense owner, so a stale thing never sees the part
of a reused idx. Inserting for a thing that already has the part overwrites it (`destroy` runs
on the old value). Inserting with a nil part zero-initialises it. Zero-sized parts (tags) store no data;
`get_part` returns a shared non-nil pointer for them.

The `_unchecked` variants skip validation: `get_part`/`remove` assume the part exists, `insert` assumes it
does not.

## Part Pool

`Part_Pool($K)` is one `Part_Set` per kind of `K`, plus the type each kind was registered with. It
only cares about parts: it doesn't know if a thing is alive or which kinds it has, that is up to
whoever uses it.

Every call asserts that the kind is registered, and the typed ones that the type matches. The
`_unchecked` variants keep these asserts and only skip the runtime checks, the same way as in
`Part_Set`. The asserts are also available on their own as `part_pool_assert_registered` and
`part_pool_assert_type`, and vanish entirely with `-disable-assert`.

Parts are set with `set_value`, `set_pointer` (`nil` zeroes the part) or the untyped `set_raw`.
There are no proc groups. `remove_all` tries every registered kind; if you already know which
kinds a thing has, `remove_unchecked` on those is faster.

# Stashes

A stash is a single value that belongs to the world rather than to any thing: time, input, config.
`Stash_Pool($K)` holds one value per registered kind of `K`. The values are packed into one buffer
of a fixed capacity, allocated once in `init`, so a stash never moves and its pointer stays valid.
Registering puts the next stash behind the previous one, aligned for its type, and panics when it
doesn't fit anymore.

A stash starts zeroed and is changed through the pointer from `get`. `reset` runs the
`destroy` callbacks and zeroes every stash but keeps the registrations; `destroy` runs them
and frees the buffer.

# Archetypes

`Archetype($K)` is the set of part kinds a thing has. It is a `bit_set[K]` underneath, but only
the `archetype_*` procs touch it: `has`, `insert`, `remove`, `clear`, `is_empty`, `contains`
(every kind of the other one is in it), `is_disjoint` and `intersect`. Iterate it with
`it := archetype_iter_make(a)` and `for kind in archetype_iter(&it)`.

`Archetype_Pool($K)` keeps one `Archetype` per thing idx. Like the part pool it doesn't know if a
thing is alive.

# Hierarchies

## Hierarchy Set

`Hierarchy_Set` links things into trees. It knows nothing about kinds. It has two layers:

- **Links**, the source of truth. One `Hierarchy_Node` per thing idx holds `parent`,
  `first_child`, `next_sibling` and `prev_sibling`, each a full `Thing`. Siblings form a circular
  list, so the first child's `prev_sibling` is the last child and attaching or detaching is O(1).
  Node 0 is a virtual root whose children are the roots of every tree. A node knows its own handle
  as `next_sibling.prev_sibling`, which lets the set assert on stale handles without storing it.
- **The order**, a cache. `hierarchy_set_rebuild` walks the links and writes `order` (every tree in
  pre-order), `depths`, `ends` (one past each subtree, so a subtree is `order[i:ends[i]]`) and
  `pos` (thing idx to position). The walk needs no stack and no extra memory. Changing the links
  only sets `is_dirty`; nothing rebuilds on its own.

A thing is in the hierarchy only while it has a parent or a child. Detaching a leaf, or leaving a
root without children, drops it out, so the order holds exactly the things in a relationship.
Children keep the order they were attached in and roots the order they became roots, so the
order is deterministic.

The set doesn't know whether a thing is alive. The world checks liveness first and removes a
thing from every set when it is killed, which makes its children roots. `kill_tree_now` collects
the subtree from the links of one set and kills it bottom-up.

## Hierarchy Pool

`Hierarchy_Pool($K)` keeps one `Hierarchy_Set` per registered kind in a `[K]Hierarchy_Set`, like
the part pool does with part sets. Registering a kind allocates its set with room for every
thing idx, so a world pays for exactly the hierarchies it registers. `hierarchy_pool_get_set`
asserts the kind is registered and hands out the set, and `hierarchy_pool_remove_all` removes a
killed thing from every set.

# Commands

`Cmd_Buffer($K)` records deferred mutations as a `Cmd($K)` union (`Cmd_Kill`, `Cmd_Set_Value`,
`Cmd_Set_Zero`, `Cmd_Remove`, `Cmd_Attach`, `Cmd_Detach`, `Cmd_Kill_Tree`) in record order. It only
stores commands; applying them is up to the caller.

Part values are copied into a single `parts` byte buffer, packed without padding. `Cmd_Set_Value`
keeps the `offset` and `size` of its bytes. `cmd_buffer_get_bytes` returns them as a slice, valid until
the next record, and `cmd_buffer_get_part` copies them out as a `T`. No `^T` is handed out because a
packed offset may be misaligned for `T`. Offsets and sizes are `u32`, so the buffer is capped at
`CMD_BUFFER_MAX_PARTS_CAPACITY` bytes.

# World

`World($K, $S)` owns a `Thing_Pool`, a `Part_Pool(K)`, an `Archetype_Pool(K)`, a
`Hierarchy_Pool(K)`, a `Cmd_Buffer(K)`, a `Stash_Pool(K)` and a `System_Pool(K, S)`. `S` is the
enum of system stages. `world_init` takes a `World_Params`, where a zero field means its default,
so `world_init(&world, {capacity = 1024})` is enough.

Sizes come in three kinds:

- **Compile-time constants** are format limits: handle bit widths, the `u32` offsets of the command
  buffer, the page table of a part set. They aren't meant to be tuned.
- **Capacities set at init** are what a game tunes: things, stash bytes, systems per stage. They are
  allocated during setup with `static_allocator` (in `world_init`, and in `register_hierarchy` for
  each hierarchy's set), never move and are freed in `world_destroy`, so an arena fits.
- **Growing storage** is what scales with play: part sets and the command buffer. It uses
  `dynamic_allocator`, which allocates, resizes and frees during play. Pointers into it are only
  valid until the next change, as each proc documents.

`K` is one enum for parts, stashes and hierarchies alike. A kind becomes a part when it is
registered with `register_part`, a stash with `register_stash` and a hierarchy with
`register_hierarchy`, and it only ever has one role: registering a kind in another role asserts.
Part, stash and hierarchy procs assert on a kind registered in another role the same way they do
on an unregistered one. Since `bit_set[K]` holds at most 128 kinds, all three share that limit.

Hierarchy procs take the kind first, since it names which tree they work on:
`attach_now(world, .Transform, child, parent)`, `kill_tree_now(world, .Transform, thing)`.

Stashes are reached with `register_stash`, `is_stash_registered` and `get_stash`. They
have no `_now`/`_later` variants, nothing about them is deferred.

Mutations come in two flavours:

- `_now` (`set_now`, `add_now`, `remove_now`, `kill_now`, `kill_tree_now`, `attach_now`,
  `detach_now`) apply immediately and report failure for dead things by returning `nil`/`false`.
- `_later` (`set_later`, `add_later`, `remove_later`, `kill_later`, `kill_tree_later`,
  `attach_later`, `detach_later`) record into the world's own `Cmd_Buffer`. Kind and type are
  asserted when recording; liveness is checked when applying, so commands for things that are
  dead by then are skipped. So is an `attach_later` that would close a cycle by then, since two
  systems can each record a valid attach that only conflicts once both apply. `THING_NIL` is
  never recorded.

`world_apply` applies the world's buffer in record order and resets it. `world_apply_buffer` applies a
buffer recorded elsewhere and leaves it untouched; the caller resets it, and may replay it into
several worlds. `world_reset` drops unapplied commands, kills every thing and zeroes every
stash, keeping all registrations.

Part values are moved into the world on apply. The buffer itself never runs `destroy` callbacks:
resetting a buffer that was never applied leaks whatever its parts own, and applying one
buffer twice hands the same memory to two parts.

`spawn` has no `_later` variant: the thing is needed right away to record commands for it.

Systems are `proc(stuff: Stuff(K, S))`, scheduled with `world_schedule` into a stage with the
kinds they read and write. Stash kinds go into `reads` and `writes` like part kinds, so two systems
touching the same stash are ordered the same way as two touching the same part. Nothing checks that
a system only touches what it declared. `world_run_stage_sync` runs one stage and
`world_run_sync` runs every stage in the order of `S`. Neither applies commands: the main loop is
the caller's, and it decides where the sync points go, with `world_apply` for commands and
`world_rebuild_hierarchy` or `world_rebuild_hierarchies` for the hierarchy orders. The stage graph
is rebuilt on the next run whenever systems were scheduled since the last build. Everything runs
on one thread for now. `world_reset` keeps the scheduled systems.

A hierarchy kind goes into `reads` and `writes` like a part or stash kind. Only `attach_now`,
`detach_now` and the kills write a hierarchy, and only the link reads (`get_parent`,
`iter_children`, ...) read it in a way that can conflict. `_later` calls only touch the command
buffer, and the order only changes at a rebuild, which runs outside systems. Note that `kill_now`
writes every hierarchy and every part kind of the thing without declaring it.

# Stuff and Queries

`Stuff($K, $S)` is what a system gets. It forwards to its world, but only for things, parts,
hierarchies and stashes: it cannot register kinds, apply commands, rebuild hierarchies or
init/destroy/reset the world.

`Query($K, $S)` iterates the things that have every kind of `include` and none of `exclude`.
`include` cannot be empty and cannot share a kind with `exclude`. It walks the smallest part set of
`include`, picked in `query_make` and again in `query_refresh`, which also starts the iteration over.
Iterate it with `for thing in query_iter(&query)`. `query.thing` is the current thing (nil once
`query_iter` returns false), and `query_has` and `query_get_part` read it.

`query_make_hierarchy(stuff, kind, include, exclude)` makes a query that walks the order of a
hierarchy instead, so a parent always comes before its children, which is what propagating values
down a tree needs. It filters by archetype the same way. A thing in the hierarchy without the parts
is skipped while its children are still visited, and a thing outside the hierarchy is never
visited. The order is the one of the last rebuild: things killed since then are skipped (the
order keeps full handles, so a reused slot is skipped too), and things attached since then show
up after the next rebuild. For the current thing, `query_get_parent` and `query_get_parent_part`
read the links, `query_get_depth` reads the order, and `query_skip_subtree` jumps past its
descendants in O(1) using `ends`.

# API

`api.odin` has the short names (`spawn`, `get_part`, `set_later`, ...). Each one is a proc group
of the `world_`, `stuff_` and `query_` procs, so the handle you pass decides what you may do: a
call a handle has no proc for does not compile. Names with only a world proc are plain aliases.
