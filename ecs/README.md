# Worlds

Worlds are the top-level container for all ECS state. They are essentially a composition of `Thing_Pool`s, `Part_Pool`s, and `Cmd_Pool`s etc.. Each world manages its own set of things and parts, allowing for isolated simulations or game states. This library wants to provide three such implementations:

- `World_Sync` - a single-threaded world where all operations are performed in a single thread.
- `World_Async` - a multi-threaded world where operations can be performed in parallel, but is not deterministic.
- `World_Deterministic` - a multi-threaded world that ensures deterministic behavior across runs.

## `World_Sync`

Mutations come in two flavours:

- `_now` (`set_now`, `add_now`, `remove_now`, `kill_now`) apply immediately and report failure for
  dead things by returning `nil`/`false`.
- `_later` (`set_later`, `add_later`, `remove_later`, `kill_later`) record into the world's own
  `Cmd_Pool`. Kind and type are asserted when recording; liveness is checked when applying, so
  commands for things that are dead by then are skipped. `THING_NIL` is never recorded.

`world_sync_apply_self` applies the world's buffer in record order and resets it.
`world_sync_apply_other` applies a buffer recorded elsewhere and leaves it untouched; the caller
resets it, and may replay it into several worlds. `world_sync_reset` drops unapplied commands.

Part values are moved into the world on apply. The buffer itself never runs `destroy` callbacks:
resetting a buffer that was never applied leaks resources owned by its parts, and applying one
buffer twice hands the same resources to two parts.

`spawn` has no `_later` variant: the thing is needed right away to record commands for it.

# Things

`Thing` is an opaque handle type: `utils.Handle(Thing_Tag)`, a `u32` with a 20-bit `idx` and a 12-bit `gen` counter.
`THING_NIL` is a nil handle (zeroed out).

`Thing_Pool` is `utils.Handle_Pool(Thing_Tag)` and the `thing_pool_*` procs are aliases of the
`utils.handle_pool_*` ones, except `thing_pool_init`, which fixes the tag and adds a default
capacity. See [`utils/README.md`](../utils/README.md) for the pool design.

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

# Systems
