# Things

`Thing` is an opaque handle type: `utils.Handle(Thing_Tag)`, a `u32` with a 20-bit `idx` and a 12-bit `gen` counter.
`THING_NIL` is a nil handle (zeroed out).

`Thing_Pool` is `utils.Handle_Pool(Thing_Tag)` and the `thing_pool_*` procs are aliases of the
`utils.handle_pool_*` ones, except `thing_pool_init`, which fixes the tag and adds a default
capacity. See [`utils/README.md`](../utils/README.md) for the pool design.

# Parts

# Systems
