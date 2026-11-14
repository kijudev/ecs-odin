# Minimal ECS in Odin

Entities are things, components are parts, resources are stashes and systems stay systems. I just like this naming convention.

## Layout

| Path                      | What                                                                               |
| ------------------------- | ---------------------------------------------------------------------------------- |
| [`ecs`](ecs/README.md)    | The library: handles, things, parts, stashes, queries, command buffers, the world. |
| `tests`                   | Tests. They should fail when something breaks, so run them.                        |
| `src`                     | Sandbox. Poke things here.                                                         |
| [`bench`](bench/CASES.md) | Benchmarks against EnTT and flecs.                                                 |

## Dependencies

| Tool                                          | For               |
| --------------------------------------------- | ----------------- |
| [Odin](https://odin-lang.org) (`dev-2026-11`) | Everything.       |
| [just](https://github.com/casey/just)         | Running commands. |
| clang, python3                                | Benchmarks only.  |
| [samply](https://github.com/mstange/samply)   | Profiling only.   |

Got Nix? `nix develop` gets you all of it, plus EnTT and flecs for the benchmarks.

## Building

```sh
just            # list every command
just test       # run the tests
just run        # run the sandbox
just check      # type-check without building
just bench      # benchmark oecs, EnTT and flecs at 100k entities
just bench profile 'query.*'   # flame graph in samply
```

No `just`? It's plain `odin`, so `odin test tests` works too.

## Sources

Stuff I stole ideas from, or measure myself against.

- [EnTT](https://github.com/skypjack/entt): sparse sets, done properly.
- [ECS back and forth](https://skypjack.github.io/2019-02-14-ecs-baf-part-1/): EnTT's author on how ECS designs actually work.
- [flecs](https://github.com/flecs/flecs): archetypes, relationships and everything else.
- [ECS FAQ](https://github.com/SanderMertens/ecs-faq): the flecs author's answers to everything you were about to ask.
- [Bevy](https://github.com/bevyengine/bevy): the ECS in Rust's most popular engine.
- [Odin overview](https://odin-lang.org/docs/overview/): the language itself.
