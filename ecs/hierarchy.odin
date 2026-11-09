package ecs

import "base:intrinsics"
import "core:fmt"
import "core:mem"

// >-------------------------------------------------------- Constants and Types

Hierarchy_Depth :: u16
Hierarchy_Pos :: u32

/*
A thing's links in the hierarchy. Siblings form a circular list, so the first child's
`prev_sibling` is the last child. A thing is in the hierarchy exactly when its `next_sibling`
isn't nil, an only child links to itself.
*/
Hierarchy_Node :: struct {
	parent:       Thing,
	first_child:  Thing,
	next_sibling: Thing,
	prev_sibling: Thing,
}

/*
Links things into trees and flattens them into a pre-order at explicit sync points. It knows
nothing about kinds, see Hierarchy_Pool.

The links in `nodes` are indexed by `thing.idx` and always up to date. Node 0 is a virtual root:
its children are the roots of every tree, so roots have a nil `parent`. A thing is in the
hierarchy only while it has a parent or a child, the set drops it as soon as it has neither.
`order`, `depths`, `ends` and `pos` are a cache that only `hierarchy_set_rebuild` writes.
Changing the links marks it dirty, but nothing rebuilds it on its own.
*/
Hierarchy_Set :: struct {
	nodes:       []Hierarchy_Node,
	order:       []Thing,
	depths:      []Hierarchy_Depth,
	ends:        []Hierarchy_Pos,
	pos:         []Hierarchy_Pos,
	count:       int,
	order_count: int,
	is_dirty:    bool,
	allocator:   mem.Allocator,
}

/*
Holds one Hierarchy_Set per registered kind of `K`. A set is allocated when its kind is
registered, with room for things with an idx below `capacity`.
*/
Hierarchy_Pool :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	sets:       [K]Hierarchy_Set,
	registered: bit_set[K],
	capacity:   int,
	allocator:  mem.Allocator,
}

/* Iterates the children of one thing, or the roots, in sibling order. */
Hierarchy_Children_Iter :: struct {
	set:  ^Hierarchy_Set,
	next: Thing,
}

// >-------------------------------------------------------------- Hierarchy_Set

/*
Initializes the set with room for things with an idx below `capacity`, allocated up front with
`allocator`.

Asserts:
- `capacity` is between HIERARCHY_SET_MIN_CAPACITY and HIERARCHY_SET_MAX_CAPACITY.
*/
hierarchy_set_init :: proc(
	set: ^Hierarchy_Set,
	capacity: int,
	allocator: mem.Allocator = context.allocator,
) {
	fmt.assertf(
		capacity >= HIERARCHY_SET_MIN_CAPACITY && capacity <= HIERARCHY_SET_MAX_CAPACITY,
		"Hierarchy set capacity has to be between %v and %v, got %v.",
		HIERARCHY_SET_MIN_CAPACITY,
		HIERARCHY_SET_MAX_CAPACITY,
		capacity,
	)

	nodes, nodes_err := make([]Hierarchy_Node, capacity, allocator)
	if nodes_err != nil do panic("Failed to allocate memory for hierarchy set.")

	order, order_err := make([]Thing, capacity, allocator)
	if order_err != nil do panic("Failed to allocate memory for hierarchy set.")

	depths, depths_err := make([]Hierarchy_Depth, capacity, allocator)
	if depths_err != nil do panic("Failed to allocate memory for hierarchy set.")

	ends, ends_err := make([]Hierarchy_Pos, capacity, allocator)
	if ends_err != nil do panic("Failed to allocate memory for hierarchy set.")

	pos, pos_err := make([]Hierarchy_Pos, capacity, allocator)
	if pos_err != nil do panic("Failed to allocate memory for hierarchy set.")

	set^ = Hierarchy_Set {
		nodes     = nodes,
		order     = order,
		depths    = depths,
		ends      = ends,
		pos       = pos,
		allocator = allocator,
	}
}

/* Frees the set with the allocator it was initialized with and zeroes it. */
hierarchy_set_destroy :: proc(set: ^Hierarchy_Set) {
	delete(set.nodes, set.allocator)
	delete(set.order, set.allocator)
	delete(set.depths, set.allocator)
	delete(set.ends, set.allocator)
	delete(set.pos, set.allocator)
	set^ = Hierarchy_Set{}
}

/* Removes every thing from the hierarchy and clears the order. */
hierarchy_set_reset :: proc(set: ^Hierarchy_Set) {
	mem.zero_slice(set.nodes)
	set.count = 0
	set.order_count = 0
	set.is_dirty = false
}

/* Counts the things in the hierarchy. */
hierarchy_set_count :: proc(set: ^Hierarchy_Set) -> int {
	return set.count
}

/* Gets the number of thing indices the set has room for. */
hierarchy_set_capacity :: proc(set: ^Hierarchy_Set) -> int {
	return len(set.nodes)
}

/* Checks whether the links changed since the last rebuild. */
hierarchy_set_is_dirty :: proc(set: ^Hierarchy_Set) -> bool {
	return set.is_dirty
}

/*
Checks whether the thing is in the hierarchy.

Returns false for the nil thing, a stale thing and an `idx` out of range.
*/
hierarchy_set_contains :: proc(set: ^Hierarchy_Set, thing: Thing) -> bool {
	if thing == THING_NIL || int(thing.idx) >= len(set.nodes) do return false
	return hierarchy_node_self(set, thing.idx) == thing
}

/*
Attaches `child` as the last child of `parent`, moving it with its whole subtree if it already
has a parent. A `parent` that isn't in the hierarchy yet joins it as a root, and an old parent
that is left with neither a parent nor a child drops out. Does nothing if `child` is already a
child of `parent`, so it keeps its place among its siblings.

Asserts:
- `child` and `parent` are valid hierarchy things, see hierarchy_set_parent.
- `child` and `parent` are different things.
- `parent` isn't a descendant of `child`.
*/
hierarchy_set_attach :: proc(set: ^Hierarchy_Set, child, parent: Thing) {
	hierarchy_set_assert_thing(set, child)
	hierarchy_set_assert_thing(set, parent)
	fmt.assertf(
		child.idx != parent.idx,
		"Hierarchy thing %v can't be attached to itself.",
		child.idx,
	)

	when !ODIN_DISABLE_ASSERT {
		for up := parent; up != THING_NIL; up = set.nodes[up.idx].parent {
			fmt.assertf(
				up.idx != child.idx,
				"Hierarchy thing %v can't be attached to its descendant %v.",
				child.idx,
				parent.idx,
			)
		}
	}

	if set.nodes[child.idx].parent == parent do return

	if hierarchy_node_is_linked(set, child.idx) {
		hierarchy_node_unlink_and_prune(set, child.idx)
	} else {
		set.count += 1
	}

	if !hierarchy_node_is_linked(set, parent.idx) {
		hierarchy_node_link(set, parent, THING_NIL)
		set.count += 1
	}

	hierarchy_node_link(set, child, parent)
	set.is_dirty = true
}

/*
Detaches the thing from its parent and makes it the last root, with its subtree still attached.
A thing without children drops out of the hierarchy instead, and so does a root parent left
without children.

Returns false if the thing isn't in the hierarchy or is already a root.

Asserts:
- `thing` is a valid hierarchy thing, see hierarchy_set_parent.
*/
hierarchy_set_detach :: proc(set: ^Hierarchy_Set, thing: Thing) -> bool {
	hierarchy_set_assert_thing(set, thing)

	if set.nodes[thing.idx].parent == THING_NIL do return false

	hierarchy_node_unlink_and_prune(set, thing.idx)
	hierarchy_node_settle(set, thing)
	set.is_dirty = true
	return true
}

/*
Removes the thing from the hierarchy. Its children become the last roots, in order, and keep
their own subtrees. Children without children of their own drop out instead, and so does a root
parent left without children.

Returns false if the thing isn't in the hierarchy.

Asserts:
- `thing` is a valid hierarchy thing, see hierarchy_set_parent.
*/
hierarchy_set_remove :: proc(set: ^Hierarchy_Set, thing: Thing) -> bool {
	hierarchy_set_assert_thing(set, thing)

	if !hierarchy_node_is_linked(set, thing.idx) do return false

	for {
		child := set.nodes[thing.idx].first_child
		if child == THING_NIL do break

		hierarchy_node_unlink(set, child.idx)
		hierarchy_node_settle(set, child)
	}

	hierarchy_node_unlink_and_prune(set, thing.idx)
	set.count -= 1
	set.is_dirty = true
	return true
}

/*
Checks whether `child` can be attached to `parent` without a cycle: they are different things and
`parent` isn't a descendant of `child`. Walks up from `parent`, so it costs its depth.

Asserts:
- `child` and `parent` are valid hierarchy things, see hierarchy_set_parent.
*/
hierarchy_set_can_attach :: proc(set: ^Hierarchy_Set, child, parent: Thing) -> bool {
	hierarchy_set_assert_thing(set, child)
	hierarchy_set_assert_thing(set, parent)

	for up := parent; up != THING_NIL; up = set.nodes[up.idx].parent {
		if up.idx == child.idx do return false
	}

	return true
}

/*
Collects the thing and its descendants into `buffer`, in pre-order. Walks the links, so it is up
to date without a rebuild. A thing that isn't in the hierarchy collects only itself.

Returns the filled front of `buffer`. `hierarchy_set_count(set) + 1` things always fit.

Asserts:
- `thing` is a valid hierarchy thing, see hierarchy_set_parent.
- the subtree fits in `buffer`.
*/
hierarchy_set_collect_subtree :: proc(
	set: ^Hierarchy_Set,
	thing: Thing,
	buffer: []Thing,
) -> []Thing {
	hierarchy_set_assert_thing(set, thing)
	fmt.assertf(len(buffer) > 0, "Subtree of thing %v doesn't fit in the buffer.", thing.idx)

	buffer[0] = thing
	n := 1
	cur := set.nodes[thing.idx].first_child

	for cur != THING_NIL {
		fmt.assertf(n < len(buffer), "Subtree of thing %v doesn't fit in the buffer.", thing.idx)
		buffer[n] = cur
		n += 1

		if child := set.nodes[cur.idx].first_child; child != THING_NIL {
			cur = child
			continue
		}

		for {
			if next := hierarchy_node_next_sibling(set, cur.idx); next != THING_NIL {
				cur = next
				break
			}

			cur = set.nodes[cur.idx].parent
			if cur == thing {
				cur = THING_NIL
				break
			}
		}
	}

	return buffer[:n]
}

/*
Gets the thing's parent.

Returns nil if the thing is a root or isn't in the hierarchy.

Asserts:
- `thing` isn't nil and its idx is below the set's capacity.
- `thing` isn't stale: if its idx is in the hierarchy, it is there with the same gen.
*/
hierarchy_set_parent :: proc(set: ^Hierarchy_Set, thing: Thing) -> Thing {
	hierarchy_set_assert_thing(set, thing)
	return set.nodes[thing.idx].parent
}

/*
Gets the thing's first child.

Returns nil if the thing has no children.

Asserts:
- `thing` is a valid hierarchy thing, see hierarchy_set_parent.
*/
hierarchy_set_first_child :: proc(set: ^Hierarchy_Set, thing: Thing) -> Thing {
	hierarchy_set_assert_thing(set, thing)
	return set.nodes[thing.idx].first_child
}

/*
Gets the thing's next sibling. Roots are siblings of each other.

Returns nil if the thing is the last sibling or isn't in the hierarchy.

Asserts:
- `thing` is a valid hierarchy thing, see hierarchy_set_parent.
*/
hierarchy_set_next_sibling :: proc(set: ^Hierarchy_Set, thing: Thing) -> Thing {
	hierarchy_set_assert_thing(set, thing)
	return hierarchy_node_next_sibling(set, thing.idx)
}

/*
Makes an iterator over the thing's children.

Asserts:
- `thing` is a valid hierarchy thing, see hierarchy_set_parent.
*/
hierarchy_set_iter_children :: proc(set: ^Hierarchy_Set, thing: Thing) -> Hierarchy_Children_Iter {
	hierarchy_set_assert_thing(set, thing)
	return Hierarchy_Children_Iter{set = set, next = set.nodes[thing.idx].first_child}
}

/* Makes an iterator over the roots. */
hierarchy_set_iter_roots :: proc(set: ^Hierarchy_Set) -> Hierarchy_Children_Iter {
	return Hierarchy_Children_Iter{set = set, next = set.nodes[0].first_child}
}

/*
Advances the iterator. Changing the links while iterating is not supported.

Returns the next child and true, or false once every child was returned.
*/
hierarchy_children_iter_next :: proc(it: ^Hierarchy_Children_Iter) -> (Thing, bool) {
	if it.next == THING_NIL do return THING_NIL, false

	thing := it.next
	it.next = hierarchy_node_next_sibling(it.set, thing.idx)
	return thing, true
}

/*
Flattens the links into the order: every tree in pre-order, roots in sibling order. Parents come
before their children and every subtree is a contiguous range. Runs in O(count) without extra
memory and clears the dirty flag.

Asserts:
- No thing is deeper than HIERARCHY_MAX_DEPTH.
*/
hierarchy_set_rebuild :: proc(set: ^Hierarchy_Set) {
	n := 0
	depth := 0
	cur := set.nodes[0].first_child

	for cur != THING_NIL {
		set.order[n] = cur
		set.depths[n] = Hierarchy_Depth(depth)
		set.pos[cur.idx] = Hierarchy_Pos(n)
		n += 1

		if child := set.nodes[cur.idx].first_child; child != THING_NIL {
			fmt.assertf(
				depth < HIERARCHY_MAX_DEPTH,
				"Hierarchy is deeper than HIERARCHY_MAX_DEPTH (%v).",
				HIERARCHY_MAX_DEPTH,
			)

			cur = child
			depth += 1
			continue
		}

		for cur != THING_NIL {
			set.ends[set.pos[cur.idx]] = Hierarchy_Pos(n)

			if next := hierarchy_node_next_sibling(set, cur.idx); next != THING_NIL {
				cur = next
				break
			}

			cur = set.nodes[cur.idx].parent
			depth -= 1
		}
	}

	set.order_count = n
	set.is_dirty = false
}

/*
Gets the things in the order of the last rebuild.

The slice is valid until the next rebuild.
*/
hierarchy_set_order :: proc(set: ^Hierarchy_Set) -> []Thing {
	return set.order[:set.order_count]
}

/*
Gets the depth of every thing in the order, roots are at depth 0.

The slice is valid until the next rebuild.
*/
hierarchy_set_depths :: proc(set: ^Hierarchy_Set) -> []Hierarchy_Depth {
	return set.depths[:set.order_count]
}

/*
Gets, for every thing in the order, the position one past its subtree. The subtree of the thing
at `i` is `order[i:ends[i]]`.

The slice is valid until the next rebuild.
*/
hierarchy_set_ends :: proc(set: ^Hierarchy_Set) -> []Hierarchy_Pos {
	return set.ends[:set.order_count]
}

/*
Gets the thing's subtree from the order, starting with the thing itself.

Returns nil if the thing wasn't in the hierarchy at the last rebuild. The slice is valid until
the next rebuild.
*/
hierarchy_set_subtree :: proc(set: ^Hierarchy_Set, thing: Thing) -> []Thing {
	pos, ok := hierarchy_set_order_pos(set, thing)
	if !ok do return nil

	return set.order[pos:set.ends[pos]]
}

/*
Checks whether `ancestor` is a strict ancestor of `thing`, as of the last rebuild.

Returns false if either wasn't in the hierarchy at the last rebuild.
*/
hierarchy_set_is_ancestor :: proc(set: ^Hierarchy_Set, ancestor, thing: Thing) -> bool {
	a, a_ok := hierarchy_set_order_pos(set, ancestor)
	t, t_ok := hierarchy_set_order_pos(set, thing)
	if !a_ok || !t_ok do return false

	return a < t && t < set.ends[a]
}

// >------------------------------------------------------------- Hierarchy_Pool

/*
Initializes the pool. Nothing is allocated until a kind is registered, then each set takes room
for things with an idx below `capacity` from `allocator`.

Asserts:
- `capacity` is between HIERARCHY_SET_MIN_CAPACITY and HIERARCHY_SET_MAX_CAPACITY.
*/
hierarchy_pool_init :: proc(
	pool: ^Hierarchy_Pool($K),
	capacity: int,
	allocator: mem.Allocator = context.allocator,
) {
	fmt.assertf(
		capacity >= HIERARCHY_SET_MIN_CAPACITY && capacity <= HIERARCHY_SET_MAX_CAPACITY,
		"Hierarchy pool capacity has to be between %v and %v, got %v.",
		HIERARCHY_SET_MIN_CAPACITY,
		HIERARCHY_SET_MAX_CAPACITY,
		capacity,
	)

	pool^ = Hierarchy_Pool(K) {
		capacity  = capacity,
		allocator = allocator,
	}
}

/* Destroys every registered set and zeroes the pool. */
hierarchy_pool_destroy :: proc(pool: ^Hierarchy_Pool($K)) {
	for kind in pool.registered do hierarchy_set_destroy(&pool.sets[kind])
	pool^ = Hierarchy_Pool(K){}
}

/* Resets every registered set, keeping the registrations. */
hierarchy_pool_reset :: proc(pool: ^Hierarchy_Pool($K)) {
	for kind in pool.registered do hierarchy_set_reset(&pool.sets[kind])
}

/*
Registers `kind` as a hierarchy and allocates its set.

Asserts:
- `kind` is not registered yet.
*/
hierarchy_pool_register :: proc(pool: ^Hierarchy_Pool($K), kind: K) {
	fmt.assertf(kind not_in pool.registered, "Hierarchy kind %v is already registered.", kind)

	hierarchy_set_init(&pool.sets[kind], pool.capacity, pool.allocator)
	pool.registered += {kind}
}

/* Checks whether `kind` is registered as a hierarchy. */
hierarchy_pool_is_registered :: proc(pool: ^Hierarchy_Pool($K), kind: K) -> bool {
	return kind in pool.registered
}

/* Asserts that `kind` is registered as a hierarchy. */
hierarchy_pool_assert_registered :: proc(
	pool: ^Hierarchy_Pool($K),
	kind: K,
	loc := #caller_location,
) {
	fmt.assertf(kind in pool.registered, "Hierarchy kind %v is not registered.", kind, loc = loc)
}

/*
Gets the set of `kind`.

The pointer stays valid until the pool is destroyed.

Asserts:
- `kind` is registered.
*/
hierarchy_pool_get_set :: proc(
	pool: ^Hierarchy_Pool($K),
	kind: K,
	loc := #caller_location,
) -> ^Hierarchy_Set {
	hierarchy_pool_assert_registered(pool, kind, loc)
	return &pool.sets[kind]
}

/*
Removes the thing from every registered set, see hierarchy_set_remove.

Asserts:
- `thing` is a valid hierarchy thing in every set, see hierarchy_set_parent.
*/
hierarchy_pool_remove_all :: proc(pool: ^Hierarchy_Pool($K), thing: Thing) {
	for kind in pool.registered do hierarchy_set_remove(&pool.sets[kind], thing)
}

// >------------------------------------------------------------------ Internals

@(private = "file")
hierarchy_set_assert_thing :: proc(set: ^Hierarchy_Set, thing: Thing) {
	when !ODIN_DISABLE_ASSERT {
		fmt.assertf(thing != THING_NIL, "Hierarchy thing can't be THING_NIL.")
		fmt.assertf(
			int(thing.idx) < len(set.nodes),
			"Hierarchy thing idx %v is out of range, the capacity is %v.",
			thing.idx,
			len(set.nodes),
		)

		self := hierarchy_node_self(set, thing.idx)
		fmt.assertf(
			self == THING_NIL || self == thing,
			"Hierarchy thing %v has gen %v, the hierarchy holds gen %v.",
			thing.idx,
			thing.gen,
			self.gen,
		)
	}
}

@(private = "file")
hierarchy_set_order_pos :: proc(set: ^Hierarchy_Set, thing: Thing) -> (Hierarchy_Pos, bool) {
	if int(thing.idx) >= len(set.pos) do return 0, false

	pos := set.pos[thing.idx]
	if int(pos) >= set.order_count || set.order[pos] != thing do return 0, false

	return pos, true
}

@(private = "file")
hierarchy_node_is_linked :: proc(set: ^Hierarchy_Set, idx: Thing_Idx) -> bool {
	return set.nodes[idx].next_sibling != THING_NIL
}

@(private = "file")
hierarchy_node_self :: proc(set: ^Hierarchy_Set, idx: Thing_Idx) -> Thing {
	next := set.nodes[idx].next_sibling
	if next == THING_NIL do return THING_NIL

	return set.nodes[next.idx].prev_sibling
}

@(private = "file")
hierarchy_node_next_sibling :: proc(set: ^Hierarchy_Set, idx: Thing_Idx) -> Thing {
	node := set.nodes[idx]
	if node.next_sibling == THING_NIL do return THING_NIL
	if node.next_sibling == set.nodes[node.parent.idx].first_child do return THING_NIL

	return node.next_sibling
}

@(private = "file")
hierarchy_node_link :: proc(set: ^Hierarchy_Set, thing, parent: Thing) {
	node := &set.nodes[thing.idx]
	parent_node := &set.nodes[parent.idx]
	node.parent = parent

	first := parent_node.first_child
	if first == THING_NIL {
		parent_node.first_child = thing
		node.next_sibling = thing
		node.prev_sibling = thing
		return
	}

	last := set.nodes[first.idx].prev_sibling
	node.next_sibling = first
	node.prev_sibling = last
	set.nodes[last.idx].next_sibling = thing
	set.nodes[first.idx].prev_sibling = thing
}

@(private = "file")
hierarchy_node_unlink_and_prune :: proc(set: ^Hierarchy_Set, idx: Thing_Idx) {
	parent := set.nodes[idx].parent
	hierarchy_node_unlink(set, idx)

	parent_node := set.nodes[parent.idx]
	if parent == THING_NIL || parent_node.first_child != THING_NIL || parent_node.parent != THING_NIL do return

	hierarchy_node_unlink(set, parent.idx)
	set.count -= 1
}

@(private = "file")
hierarchy_node_settle :: proc(set: ^Hierarchy_Set, thing: Thing) {
	if set.nodes[thing.idx].first_child != THING_NIL {
		hierarchy_node_link(set, thing, THING_NIL)
	} else {
		set.count -= 1
	}
}

@(private = "file")
hierarchy_node_unlink :: proc(set: ^Hierarchy_Set, idx: Thing_Idx) {
	node := &set.nodes[idx]
	parent_node := &set.nodes[node.parent.idx]

	if node.next_sibling.idx == idx {
		parent_node.first_child = THING_NIL
	} else {
		set.nodes[node.prev_sibling.idx].next_sibling = node.next_sibling
		set.nodes[node.next_sibling.idx].prev_sibling = node.prev_sibling
		if parent_node.first_child.idx == idx do parent_node.first_child = node.next_sibling
	}

	node.parent = THING_NIL
	node.next_sibling = THING_NIL
	node.prev_sibling = THING_NIL
}
