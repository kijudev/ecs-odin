package ecs_tests

import "core:testing"

import ecs "../ecs"

Archetype :: ecs.Archetype(Kind)

// >---------------------------------------------------------------------- Kinds

@(test)
archetype_make_has_given_kinds :: proc(t: ^testing.T) {
	a := ecs.archetype_make(bit_set[Kind]{.Position, .Health})

	testing.expect(t, ecs.archetype_has(a, .Position))
	testing.expect(t, ecs.archetype_has(a, .Health))
	testing.expect(t, !ecs.archetype_has(a, .Velocity))
	testing.expect(t, !ecs.archetype_is_empty(a))
}

@(test)
archetype_zero_is_empty :: proc(t: ^testing.T) {
	a: Archetype
	testing.expect(t, ecs.archetype_is_empty(a))
	for kind in PARTS do testing.expect(t, !ecs.archetype_has(a, kind))
}

@(test)
archetype_insert_remove_clear :: proc(t: ^testing.T) {
	a: Archetype
	ecs.archetype_insert(&a, .Velocity)
	ecs.archetype_insert(&a, .Tag)
	testing.expect(t, ecs.archetype_has(a, .Velocity))
	testing.expect(t, ecs.archetype_has(a, .Tag))

	ecs.archetype_remove(&a, .Velocity)
	testing.expect(t, !ecs.archetype_has(a, .Velocity))
	testing.expect(t, ecs.archetype_has(a, .Tag))

	ecs.archetype_clear(&a)
	testing.expect(t, ecs.archetype_is_empty(a))
}

// >-------------------------------------------------------------------- Set Ops

@(test)
archetype_contains_needs_every_kind :: proc(t: ^testing.T) {
	a := ecs.archetype_make(bit_set[Kind]{.Position, .Velocity, .Tag})

	testing.expect(t, ecs.archetype_contains(a, ecs.archetype_make(bit_set[Kind]{.Position, .Tag})))
	testing.expect(t, ecs.archetype_contains(a, a))
	testing.expect(t, ecs.archetype_contains(a, Archetype{}))
	testing.expect(t, !ecs.archetype_contains(a, ecs.archetype_make(bit_set[Kind]{.Position, .Health})))
	testing.expect(t, !ecs.archetype_contains(Archetype{}, a))
}

@(test)
archetype_is_disjoint_and_intersect :: proc(t: ^testing.T) {
	a := ecs.archetype_make(bit_set[Kind]{.Position, .Velocity})
	b := ecs.archetype_make(bit_set[Kind]{.Velocity, .Health})
	c := ecs.archetype_make(bit_set[Kind]{.Tag})

	testing.expect(t, !ecs.archetype_is_disjoint(a, b))
	testing.expect(t, ecs.archetype_is_disjoint(a, c))
	testing.expect(t, ecs.archetype_is_disjoint(a, Archetype{}))

	both := ecs.archetype_intersect(a, b)
	testing.expect(t, ecs.archetype_has(both, .Velocity))
	testing.expect(t, !ecs.archetype_has(both, .Position))
	testing.expect(t, !ecs.archetype_has(both, .Health))
	testing.expect(t, ecs.archetype_is_empty(ecs.archetype_intersect(a, c)))
}

// >------------------------------------------------------------------ Iteration

@(test)
archetype_iter_yields_each_kind_once_in_order :: proc(t: ^testing.T) {
	a := ecs.archetype_make(bit_set[Kind]{.Target, .Velocity, .Tag})

	seen: [dynamic; 8]Kind
	it := ecs.archetype_iter_make(a)
	for kind in ecs.archetype_iter(&it) do append(&seen, kind)

	testing.expect_value(t, len(seen), 3)
	if len(seen) != 3 do return
	testing.expect_value(t, seen[0], Kind.Velocity)
	testing.expect_value(t, seen[1], Kind.Tag)
	testing.expect_value(t, seen[2], Kind.Target)

	// Done stays done.
	_, ok := ecs.archetype_iter(&it)
	testing.expect(t, !ok)
}

@(test)
archetype_iter_of_empty_yields_nothing :: proc(t: ^testing.T) {
	it := ecs.archetype_iter_make(Archetype{})
	for _ in ecs.archetype_iter(&it) do testing.fail_now(t, "Empty archetype yielded a kind.")
}

@(test)
archetype_iter_does_not_change_the_archetype :: proc(t: ^testing.T) {
	a := ecs.archetype_make(bit_set[Kind]{.Position, .Health})
	it := ecs.archetype_iter_make(a)
	for _ in ecs.archetype_iter(&it) {}

	testing.expect(t, ecs.archetype_has(a, .Position))
	testing.expect(t, ecs.archetype_has(a, .Health))
}

// >------------------------------------------------------------- Archetype_Pool

@(test)
archetype_pool_get_returns_the_things_kinds :: proc(t: ^testing.T) {
	pool: ecs.Archetype_Pool(Kind)
	ecs.archetype_pool_init(&pool, ecs.ARCHETYPE_POOL_MIN_CAPACITY)
	defer ecs.archetype_pool_destroy(&pool)

	thing := ecs.thing_make(3)
	ecs.archetype_pool_insert(&pool, thing, .Velocity)
	ecs.archetype_pool_insert(&pool, thing, .Tag)

	a := ecs.archetype_pool_get(pool, thing)
	testing.expect(t, ecs.archetype_contains(a, ecs.archetype_make(bit_set[Kind]{.Velocity, .Tag})))
	testing.expect(t, !ecs.archetype_has(a, .Position))

	ecs.archetype_pool_remove_all(&pool, thing)
	testing.expect(t, ecs.archetype_is_empty(ecs.archetype_pool_get(pool, thing)))
}
