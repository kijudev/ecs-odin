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
`get` returns a shared non-nil pointer for them.

The `_unchecked` variants skip validation: `get`/`remove` assume the part exists, `insert` assumes it
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
