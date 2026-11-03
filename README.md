# Minimal ECS in Odin

Entities are things, components are parts and systems stay systems. I just like this naming conventions.

## Layout

- [`ecs`](ecs/README.md) - the primitives: handles, things, parts, archetypes, command buffers.
- [`worlds`](worlds/README.md) - sample worlds assembled from the primitives, meant to be copied and tweaked.
- `tests/ecs`, `tests/world_sync` - one test package each, run with `odin test tests/<name>`.

## Features I aspire to build

1. Sparse set / dense array part storage.
2. Bitset based queries.
3. Groups.
4. Hierarchies.
5. Deffered mutations and command buffers.
6. Opt-in deterministic mutations.
