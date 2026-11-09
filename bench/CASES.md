# Benchmark cases

One spec, implemented by oecs, EnTT and flecs. `just compare` merges the results.

## Method

- Sizes: N = 10k, 100k, 1M (`just quick` runs 100k only).
- Every sample builds a fresh world and runs setup untimed, then times the case.
- The first sample is a warm-up and is dropped. Sampling stops at 30 samples, or at 5 samples
  with 0.1 s timed, or at 3 samples after 3 s of wall time.
- _R_ cases can run again on their own result. When one run takes under 50 µs, it is repeated
  `k` times per sample.
- Reported: median, min and MAD of ns/op, plus a checksum of the world from the warm-up sample.
  The checksums must match across libraries.
- Memory: every allocation goes through glibc `malloc` and is counted with
  `malloc_usable_size`. `live` is what the world holds after setup (world overhead included);
  `peak` is the extra memory the timed part needed on top of that.
- Builds: `clang++ -O3 -DNDEBUG`, `odin -o:speed -disable-assert -no-bounds-check`. Nothing is
  reserved up front, except that oecs must size its world: capacity is N + 1.

## Data

- Parts A, B, C, D: `{x, y, z, w: f32}`, starting at `x = 1`. Tag is empty.
- `things[i]` is the i-th spawned entity. `perm` is 0..N-1 shuffled the same way in every
  binary. `.seq` cases walk `things`, `.rand` cases walk `things[perm[j]]`.

| setup        | contents                                                                        |
| ------------ | ------------------------------------------------------------------------------- |
| `full`       | N entities with A, B, C, D                                                      |
| `sparse(p)`  | N entities with A; B on `i` when `hash(i) % 1000 < p` (‰)                       |
| `fragmented` | entity `i` gets the subset of A–D given by the bits of `i % 16`, Tag when empty |

## Flat

Query update: `A.x += 1 + (x of every other part in the query)`. Checksum: sum of `A.x`.
One op is one entity of the world, so ns/op is comparable across selectivities.

| group        | case                                         | setup                                 | timed                                                                 | checksum          |
| ------------ | -------------------------------------------- | ------------------------------------- | --------------------------------------------------------------------- | ----------------- |
| lifecycle    | `spawn.0` … `spawn.4`                        | empty                                 | spawn N, then add parts A… one call each                              | alive / sum A.x   |
|              | `kill`, `kill.later`                         | `full`                                | kill all (`later`: queue, then apply)                                 | alive             |
| structure    | `add.tag`, `add.tag.later`, `remove.tag`     | `full` (+Tag)                         | on all                                                                | Tag count         |
|              | `add.D`, `remove.D`                          | `full` (−D)                           | on all                                                                | sum D.x / D count |
| query (_R_)  | `uniform.1` … `.4`                           | `full`                                | A / A,B / A,B,C / A,B,C,D                                             |                   |
|              | `exclude`                                    | `full`, Tag on even `i`               | A,B without Tag                                                       |                   |
|              | `sparse.10` / `.100` / `.500`                | `sparse(p)`                           | A,B                                                                   |                   |
|              | `fragmented.1` / `.2`                        | `fragmented`                          | A / A,B                                                               |                   |
|              | `system`                                     | `full`                                | A,B through the library's systems                                     |                   |
|              | `baseline`                                   | `full`                                | direct walk over A's storage                                          |                   |
| access (_R_) | `get.1`, `get.4`, `write.1` (`.seq`/`.rand`) | `full`                                | checked read of A / A–D, write A.x += 1                               | sum read / A.x    |
|              | `has`, `alive` (`.seq`/`.rand`)              | `sparse(500)` / `full` minus even `i` | has B / is alive                                                      | count             |
| churn        | `churn.frames` (op = frame)                  | `full`                                | 100 frames: kill 1% by `perm`, respawn them with A–D, run `uniform.2` | sum A.x           |
|              | `churn.after` (_R_)                          | `full` + 100 frames                   | `uniform.2`                                                           | sum A.x           |

## Hierarchy

Every entity has Local `{1, 1}` and Global `{0, 0}`. The parent of `i` always has a lower
index:

| shape    | parent of `i`                |
| -------- | ---------------------------- |
| `tree`   | `(i - 1) / 4`, root 0        |
| `forest` | groups of 7, root → 2 → 4    |
| `chain`  | `i - 1`, a new root every 64 |

Every case runs on every shape (`propagate.tree`, …). flecs runs twice: `flecs` (ChildOf) and
`flecs-parent` (non-fragmenting `Parent`).

| case                           | timed                                                                   | op      | checksum               |
| ------------------------------ | ----------------------------------------------------------------------- | ------- | ---------------------- |
| `attach`, `attach.later`       | attach all non-roots                                                    | attach  | children count         |
| `rebuild`                      | whatever must happen before ordered iteration                           | entity  | —                      |
| `propagate` (_R_)              | `Global = parent.Global + Local`, parents first                         | entity  | sum Global x + y       |
| `parent` (_R_, `.seq`/`.rand`) | get the parent                                                          | entity  | count                  |
| `children` (_R_)               | iterate the children of every entity                                    | entity  | count                  |
| `reparent`                     | move `perm[0 .. N/10)` (except 0) under a random original root below it | move    | Global after propagate |
| `kill.whole`                   | kill every root's subtree                                               | entity  | alive                  |
| `kill.small`                   | kill the subtrees of `perm[0 .. N/100)`, skipping dead                  | subtree | alive                  |
