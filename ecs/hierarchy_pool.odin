package ecs

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
Links things into trees and flattens them into a pre-order at explicit sync points.

The links in `nodes` are indexed by `thing.idx` and always up to date. Node 0 is a virtual root:
its children are the roots of every tree, so roots have a nil `parent`. `order`, `depths`, `ends`
and `pos` are a cache that only `hierarchy_pool_rebuild` writes. Changing the links marks it
dirty, but nothing rebuilds it on its own.
*/
Hierarchy_Pool :: struct {
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

/* Iterates the children of one thing, or the roots, in sibling order. */
Hierarchy_Children_Iter :: struct {
	pool: ^Hierarchy_Pool,
	next: Thing,
}

// >------------------------------------------------------------- Hierarchy_Pool

/*
Initializes the pool with room for things with an idx below `capacity`, allocated up front with
`allocator`.

Asserts:
- `capacity` is between HIERARCHY_POOL_MIN_CAPACITY and HIERARCHY_POOL_MAX_CAPACITY.
*/
hierarchy_pool_init :: proc(
	pool: ^Hierarchy_Pool,
	capacity: int = HIERARCHY_POOL_DEFAULT_CAPACITY,
	allocator: mem.Allocator = context.allocator,
) {
	fmt.assertf(
		capacity >= HIERARCHY_POOL_MIN_CAPACITY && capacity <= HIERARCHY_POOL_MAX_CAPACITY,
		"Hierarchy pool capacity has to be between %v and %v, got %v.",
		HIERARCHY_POOL_MIN_CAPACITY,
		HIERARCHY_POOL_MAX_CAPACITY,
		capacity,
	)

	nodes, nodes_err := make([]Hierarchy_Node, capacity, allocator)
	if nodes_err != nil do panic("Failed to allocate memory for hierarchy pool.")

	order, order_err := make([]Thing, capacity, allocator)
	if order_err != nil do panic("Failed to allocate memory for hierarchy pool.")

	depths, depths_err := make([]Hierarchy_Depth, capacity, allocator)
	if depths_err != nil do panic("Failed to allocate memory for hierarchy pool.")

	ends, ends_err := make([]Hierarchy_Pos, capacity, allocator)
	if ends_err != nil do panic("Failed to allocate memory for hierarchy pool.")

	pos, pos_err := make([]Hierarchy_Pos, capacity, allocator)
	if pos_err != nil do panic("Failed to allocate memory for hierarchy pool.")

	pool^ = Hierarchy_Pool {
		nodes     = nodes,
		order     = order,
		depths    = depths,
		ends      = ends,
		pos       = pos,
		allocator = allocator,
	}
}

/* Frees the pool with the allocator it was initialized with and zeroes it. */
hierarchy_pool_destroy :: proc(pool: ^Hierarchy_Pool) {
	delete(pool.nodes, pool.allocator)
	delete(pool.order, pool.allocator)
	delete(pool.depths, pool.allocator)
	delete(pool.ends, pool.allocator)
	delete(pool.pos, pool.allocator)
	pool^ = Hierarchy_Pool{}
}

/* Removes every thing from the hierarchy and clears the order. */
hierarchy_pool_reset :: proc(pool: ^Hierarchy_Pool) {
	mem.zero_slice(pool.nodes)
	pool.count = 0
	pool.order_count = 0
	pool.is_dirty = false
}

/* Counts the things in the hierarchy. */
hierarchy_pool_count :: proc(pool: ^Hierarchy_Pool) -> int {
	return pool.count
}

/* Gets the number of thing indices the pool has room for. */
hierarchy_pool_capacity :: proc(pool: ^Hierarchy_Pool) -> int {
	return len(pool.nodes)
}

/* Checks whether the links changed since the last rebuild. */
hierarchy_pool_is_dirty :: proc(pool: ^Hierarchy_Pool) -> bool {
	return pool.is_dirty
}

/*
Checks whether the thing is in the hierarchy.

Returns false for the nil thing, a stale thing and an `idx` out of range.
*/
hierarchy_pool_contains :: proc(pool: ^Hierarchy_Pool, thing: Thing) -> bool {
	if thing == THING_NIL || int(thing.idx) >= len(pool.nodes) do return false
	return hierarchy_node_self(pool, thing.idx) == thing
}

/*
Attaches `child` as the last child of `parent`, moving it with its whole subtree if it already
has a parent. A `parent` that isn't in the hierarchy yet joins it as a root. Does nothing if
`child` is already a child of `parent`, so it keeps its place among its siblings.

Asserts:
- `child` and `parent` are valid hierarchy things, see hierarchy_pool_parent.
- `child` and `parent` are different things.
- `parent` isn't a descendant of `child`.
*/
hierarchy_pool_attach :: proc(pool: ^Hierarchy_Pool, child, parent: Thing) {
	hierarchy_pool_assert_thing(pool, child)
	hierarchy_pool_assert_thing(pool, parent)
	fmt.assertf(
		child.idx != parent.idx,
		"Hierarchy thing %v can't be attached to itself.",
		child.idx,
	)

	when !ODIN_DISABLE_ASSERT {
		for up := parent; up != THING_NIL; up = pool.nodes[up.idx].parent {
			fmt.assertf(
				up.idx != child.idx,
				"Hierarchy thing %v can't be attached to its descendant %v.",
				child.idx,
				parent.idx,
			)
		}
	}

	if pool.nodes[child.idx].parent == parent do return

	if !hierarchy_node_is_linked(pool, parent.idx) {
		hierarchy_node_link(pool, parent, THING_NIL)
		pool.count += 1
	}

	if hierarchy_node_is_linked(pool, child.idx) {
		hierarchy_node_unlink(pool, child.idx)
	} else {
		pool.count += 1
	}

	hierarchy_node_link(pool, child, parent)
	pool.is_dirty = true
}

/*
Detaches the thing from its parent and makes it the last root. Its subtree stays attached to it.

Returns false if the thing isn't in the hierarchy or is already a root.

Asserts:
- `thing` is a valid hierarchy thing, see hierarchy_pool_parent.
*/
hierarchy_pool_detach :: proc(pool: ^Hierarchy_Pool, thing: Thing) -> bool {
	hierarchy_pool_assert_thing(pool, thing)

	if pool.nodes[thing.idx].parent == THING_NIL do return false

	hierarchy_node_unlink(pool, thing.idx)
	hierarchy_node_link(pool, thing, THING_NIL)
	pool.is_dirty = true
	return true
}

/*
Removes the thing from the hierarchy. Its children become the last roots, in order, and keep
their own subtrees.

Returns false if the thing isn't in the hierarchy.

Asserts:
- `thing` is a valid hierarchy thing, see hierarchy_pool_parent.
*/
hierarchy_pool_remove :: proc(pool: ^Hierarchy_Pool, thing: Thing) -> bool {
	hierarchy_pool_assert_thing(pool, thing)

	if !hierarchy_node_is_linked(pool, thing.idx) do return false

	for {
		child := pool.nodes[thing.idx].first_child
		if child == THING_NIL do break

		hierarchy_node_unlink(pool, child.idx)
		hierarchy_node_link(pool, child, THING_NIL)
	}

	hierarchy_node_unlink(pool, thing.idx)
	pool.count -= 1
	pool.is_dirty = true
	return true
}

/*
Gets the thing's parent.

Returns nil if the thing is a root or isn't in the hierarchy.

Asserts:
- `thing` isn't nil and its idx is below the pool's capacity.
- `thing` isn't stale: if its idx is in the hierarchy, it is there with the same gen.
*/
hierarchy_pool_parent :: proc(pool: ^Hierarchy_Pool, thing: Thing) -> Thing {
	hierarchy_pool_assert_thing(pool, thing)
	return pool.nodes[thing.idx].parent
}

/*
Gets the thing's first child.

Returns nil if the thing has no children.

Asserts:
- `thing` is a valid hierarchy thing, see hierarchy_pool_parent.
*/
hierarchy_pool_first_child :: proc(pool: ^Hierarchy_Pool, thing: Thing) -> Thing {
	hierarchy_pool_assert_thing(pool, thing)
	return pool.nodes[thing.idx].first_child
}

/*
Gets the thing's next sibling. Roots are siblings of each other.

Returns nil if the thing is the last sibling or isn't in the hierarchy.

Asserts:
- `thing` is a valid hierarchy thing, see hierarchy_pool_parent.
*/
hierarchy_pool_next_sibling :: proc(pool: ^Hierarchy_Pool, thing: Thing) -> Thing {
	hierarchy_pool_assert_thing(pool, thing)
	return hierarchy_node_next_sibling(pool, thing.idx)
}

/*
Makes an iterator over the thing's children.

Asserts:
- `thing` is a valid hierarchy thing, see hierarchy_pool_parent.
*/
hierarchy_pool_iter_children :: proc(
	pool: ^Hierarchy_Pool,
	thing: Thing,
) -> Hierarchy_Children_Iter {
	hierarchy_pool_assert_thing(pool, thing)
	return Hierarchy_Children_Iter{pool = pool, next = pool.nodes[thing.idx].first_child}
}

/* Makes an iterator over the roots. */
hierarchy_pool_iter_roots :: proc(pool: ^Hierarchy_Pool) -> Hierarchy_Children_Iter {
	return Hierarchy_Children_Iter{pool = pool, next = pool.nodes[0].first_child}
}

/*
Advances the iterator. Changing the links while iterating is not supported.

Returns the next child and true, or false once every child was returned.
*/
hierarchy_children_iter_next :: proc(it: ^Hierarchy_Children_Iter) -> (Thing, bool) {
	if it.next == THING_NIL do return THING_NIL, false

	thing := it.next
	it.next = hierarchy_node_next_sibling(it.pool, thing.idx)
	return thing, true
}

/*
Flattens the links into the order: every tree in pre-order, roots in sibling order. Parents come
before their children and every subtree is a contiguous range. Runs in O(count) without extra
memory and clears the dirty flag.

Asserts:
- No thing is deeper than HIERARCHY_MAX_DEPTH.
*/
hierarchy_pool_rebuild :: proc(pool: ^Hierarchy_Pool) {
	n := 0
	depth := 0
	cur := pool.nodes[0].first_child

	for cur != THING_NIL {
		pool.order[n] = cur
		pool.depths[n] = Hierarchy_Depth(depth)
		pool.pos[cur.idx] = Hierarchy_Pos(n)
		n += 1

		if child := pool.nodes[cur.idx].first_child; child != THING_NIL {
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
			pool.ends[pool.pos[cur.idx]] = Hierarchy_Pos(n)

			if next := hierarchy_node_next_sibling(pool, cur.idx); next != THING_NIL {
				cur = next
				break
			}

			cur = pool.nodes[cur.idx].parent
			depth -= 1
		}
	}

	pool.order_count = n
	pool.is_dirty = false
}

/*
Gets the things in the order of the last rebuild.

The slice is valid until the next rebuild.
*/
hierarchy_pool_order :: proc(pool: ^Hierarchy_Pool) -> []Thing {
	return pool.order[:pool.order_count]
}

/*
Gets the depth of every thing in the order, roots are at depth 0.

The slice is valid until the next rebuild.
*/
hierarchy_pool_depths :: proc(pool: ^Hierarchy_Pool) -> []Hierarchy_Depth {
	return pool.depths[:pool.order_count]
}

/*
Gets, for every thing in the order, the position one past its subtree. The subtree of the thing
at `i` is `order[i:ends[i]]`.

The slice is valid until the next rebuild.
*/
hierarchy_pool_ends :: proc(pool: ^Hierarchy_Pool) -> []Hierarchy_Pos {
	return pool.ends[:pool.order_count]
}

/*
Gets the thing's subtree from the order, starting with the thing itself.

Returns nil if the thing wasn't in the hierarchy at the last rebuild. The slice is valid until
the next rebuild.
*/
hierarchy_pool_subtree :: proc(pool: ^Hierarchy_Pool, thing: Thing) -> []Thing {
	pos, ok := hierarchy_pool_order_pos(pool, thing)
	if !ok do return nil

	return pool.order[pos:pool.ends[pos]]
}

/*
Checks whether `ancestor` is a strict ancestor of `thing`, as of the last rebuild.

Returns false if either wasn't in the hierarchy at the last rebuild.
*/
hierarchy_pool_is_ancestor :: proc(pool: ^Hierarchy_Pool, ancestor, thing: Thing) -> bool {
	a, a_ok := hierarchy_pool_order_pos(pool, ancestor)
	t, t_ok := hierarchy_pool_order_pos(pool, thing)
	if !a_ok || !t_ok do return false

	return a < t && t < pool.ends[a]
}

// >------------------------------------------------------------------ Internals

@(private = "file")
hierarchy_pool_assert_thing :: proc(pool: ^Hierarchy_Pool, thing: Thing) {
	when !ODIN_DISABLE_ASSERT {
		fmt.assertf(thing != THING_NIL, "Hierarchy thing can't be THING_NIL.")
		fmt.assertf(
			int(thing.idx) < len(pool.nodes),
			"Hierarchy thing idx %v is out of range, the capacity is %v.",
			thing.idx,
			len(pool.nodes),
		)

		self := hierarchy_node_self(pool, thing.idx)
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
hierarchy_pool_order_pos :: proc(pool: ^Hierarchy_Pool, thing: Thing) -> (Hierarchy_Pos, bool) {
	if int(thing.idx) >= len(pool.pos) do return 0, false

	pos := pool.pos[thing.idx]
	if int(pos) >= pool.order_count || pool.order[pos] != thing do return 0, false

	return pos, true
}

@(private = "file")
hierarchy_node_is_linked :: proc(pool: ^Hierarchy_Pool, idx: Thing_Idx) -> bool {
	return pool.nodes[idx].next_sibling != THING_NIL
}

@(private = "file")
hierarchy_node_self :: proc(pool: ^Hierarchy_Pool, idx: Thing_Idx) -> Thing {
	next := pool.nodes[idx].next_sibling
	if next == THING_NIL do return THING_NIL

	return pool.nodes[next.idx].prev_sibling
}

@(private = "file")
hierarchy_node_next_sibling :: proc(pool: ^Hierarchy_Pool, idx: Thing_Idx) -> Thing {
	node := pool.nodes[idx]
	if node.next_sibling == THING_NIL do return THING_NIL
	if node.next_sibling == pool.nodes[node.parent.idx].first_child do return THING_NIL

	return node.next_sibling
}

@(private = "file")
hierarchy_node_link :: proc(pool: ^Hierarchy_Pool, thing, parent: Thing) {
	node := &pool.nodes[thing.idx]
	parent_node := &pool.nodes[parent.idx]
	node.parent = parent

	first := parent_node.first_child
	if first == THING_NIL {
		parent_node.first_child = thing
		node.next_sibling = thing
		node.prev_sibling = thing
		return
	}

	last := pool.nodes[first.idx].prev_sibling
	node.next_sibling = first
	node.prev_sibling = last
	pool.nodes[last.idx].next_sibling = thing
	pool.nodes[first.idx].prev_sibling = thing
}

@(private = "file")
hierarchy_node_unlink :: proc(pool: ^Hierarchy_Pool, idx: Thing_Idx) {
	node := &pool.nodes[idx]
	parent_node := &pool.nodes[node.parent.idx]

	if node.next_sibling.idx == idx {
		parent_node.first_child = THING_NIL
	} else {
		pool.nodes[node.prev_sibling.idx].next_sibling = node.next_sibling
		pool.nodes[node.next_sibling.idx].prev_sibling = node.prev_sibling
		if parent_node.first_child.idx == idx do parent_node.first_child = node.next_sibling
	}

	node.parent = THING_NIL
	node.next_sibling = THING_NIL
	node.prev_sibling = THING_NIL
}
