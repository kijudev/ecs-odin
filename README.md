# Minimal ECS in Odin

Entities are things, components are parts, resources are stashes and systems stay systems. I just like this naming conventions.

## Layout

- [`ecs`](ecs/README.md) - handles, things, parts, stashes, archetypes, command buffers and the world.
- `tests` - the test package, run with `odin test tests`.

## Features I aspire to build

1. Sparse set / dense array part storage.
2. Bitset based queries.
3. Groups.
4. Hierarchies.
5. Deffered mutations and command buffers.
6. Opt-in deterministic mutations.
