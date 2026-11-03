# Worlds

Worlds are sample assemblies of the `ecs` primitives (`Thing_Pool`, `Part_Pool`, `Archetype_Pool`,
`Cmd_Pool`, ...). They are a starting point, not a complete solution: copy one and tweak it, or
read it as documentation for building your own.

Each world is its own package. The procs are not prefixed, the package is the namespace
(`world_sync.spawn(&world)`), and worlds use the same proc names where the concept matches, so
switching worlds is mostly changing the import.

- [`sync`](sync/README.md) - `world_sync`, a single-threaded world.
- `async` (planned) - a multi-threaded world, not deterministic.
- `deterministic` (planned) - a multi-threaded world with deterministic results across runs.
