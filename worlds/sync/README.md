# `world_sync`

A single-threaded world: `World($P)` owns a `Thing_Pool`, one `Part_Pool` per registered kind of
`P`, an `Archetype_Pool(P)` and a `Cmd_Pool(P)`.

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
