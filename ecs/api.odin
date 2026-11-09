package ecs

// >---------------------------------------------------------------------- Setup

/*
Registers `kind` as a part of type `T`. `destroy` runs on a part whenever the world drops it:
on remove, overwrite, kill, reset and destroy.

Asserts:
- `kind` is not registered as a part yet.
- `kind` is not registered as a stash or a hierarchy.
*/
register_part :: world_register_part

/* Checks whether `kind` is registered as a part. */
is_part_registered :: world_is_part_registered

/*
Registers `kind` as a stash of type `T`. The stash starts zeroed. `destroy` runs on it on reset
and destroy.

Asserts:
- `kind` is not registered as a stash yet.
- `kind` is not registered as a part or a hierarchy.

Panics:
- the stash doesn't fit in the remaining stash capacity.
*/
register_stash :: world_register_stash

/* Checks whether `kind` is registered as a stash. */
is_stash_registered :: world_is_stash_registered

/*
Registers `kind` as a hierarchy: one tree structure over things, with room for every thing the
world can hold. Several kinds make several independent hierarchies. Put the kind in a system's
`reads` or `writes` like a part kind to order systems that touch it.

Asserts:
- `kind` is not registered as a hierarchy yet.
- `kind` is not registered as a part or a stash.
*/
register_hierarchy :: world_register_hierarchy

/* Checks whether `kind` is registered as a hierarchy. */
is_hierarchy_registered :: world_is_hierarchy_registered

// >--------------------------------------------------------------------- Things

/*
Spawns a thing with no parts.

Returns THING_NIL when the thing pool is full. The world treats it as dead.
*/
spawn :: proc {
	world_spawn,
	stuff_spawn,
}

/*
Kills the thing and removes all its parts. It leaves every hierarchy, and its children there
become roots.

Returns false if the thing is already dead.

Asserts:
- every part kind of the thing, and every hierarchy it is in, is declared in the system's writes
  (stuff variant).
*/
kill_now :: proc {
	world_kill_now,
	stuff_kill_now,
}

/*
Records a kill to run on the next apply. A thing that is dead by then is skipped, and THING_NIL
is not recorded at all.
*/
kill_later :: proc {
	world_kill_later,
	stuff_kill_later,
}

/*
Kills the thing and all its descendants in the hierarchy of `kind`, removing all their parts.
Each one is killed after its descendants, as with `kill_now`, so it also leaves every other
hierarchy and its children there become roots.

Returns false if the thing is already dead.

Asserts:
- `kind` is a registered hierarchy.
- `kind`, and every part kind and hierarchy of every thing in the subtree, is declared in the
  system's writes (stuff variant).
*/
kill_tree_now :: proc {
	world_kill_tree_now,
	stuff_kill_tree_now,
}

/*
Records a `kill_tree_now` to run on the next apply. The descendants are the ones the thing has by
then. A thing that is dead by then is skipped, and THING_NIL is not recorded at all.

Asserts:
- `kind` is a registered hierarchy.
*/
kill_tree_later :: proc {
	world_kill_tree_later,
	stuff_kill_tree_later,
}

/*
Checks whether the thing is alive.

Returns false for a stale thing whose slot was reused.
*/
is_alive :: proc {
	world_is_alive,
	stuff_is_alive,
}

/* Counts the things that are alive. */
count_alive :: proc {
	world_count_alive,
	stuff_count_alive,
}

/* Counts the killed thing slots waiting to be reused by `spawn`. */
count_free :: proc {
	world_count_free,
	stuff_count_free,
}

/*
Gets the query's current thing.

Returns THING_NIL before the first `query_iter` / `hierarchy_query_iter` and once it returns false.
*/
get_thing :: proc {
	query_get_thing,
	hierarchy_query_get_thing,
}

// >---------------------------------------------------------------------- Parts

/*
Checks whether the thing has the part. The query variants check the current thing.

Returns false for a dead thing.

Asserts:
- `kind` is a registered part.
- the system declared `kind` in its reads or writes (stuff and query variants).
*/
has :: proc {
	world_has,
	stuff_has,
	query_has,
	hierarchy_query_has,
}

/*
Gets a copy of the thing's part, for reading. The query variants get it from the current thing.

Returns the part and true, or false if the thing doesn't have it. The query variants return just
the part, the current thing always has it.

Asserts:
- `kind` is a registered part.
- `T` is the type `kind` was registered with.
- the system declared `kind` in its reads or writes (stuff and query variants).
- the query has a current thing that has the part (query variants only).
*/
get_part :: proc {
	world_get_part,
	stuff_get_part,
	query_get_part,
	hierarchy_query_get_part,
}

/*
Gets the thing's part, for writing. The query variants get it from the current thing.

Returns nil if the thing doesn't have the part; the query variants never do (unchecked).
The pointer is valid until a part of this kind is added to or removed from any thing.

Asserts:
- `kind` is a registered part.
- `T` is the type `kind` was registered with.
- the system declared `kind` in its writes (stuff and query variants).
- the query has a current thing that has the part (query variants only).
*/
write_part :: proc {
	world_write_part,
	stuff_write_part,
	query_write_part,
	hierarchy_query_write_part,
}

/*
Gets every part of this kind, packed, in the same order as `get_things`, for reading. Odin can't
make the slice read-only, so writing through it is up to you, use `write_parts` for that.

The slice is valid until a part of this kind is added to or removed from any thing.

Asserts:
- `kind` is a registered part.
- `T` is the type `kind` was registered with.
- the system declared `kind` in its reads or writes (stuff variant).
*/
get_parts :: proc {
	world_get_parts,
	stuff_get_parts,
}

/*
Gets every part of this kind, packed, in the same order as `get_things`, for writing.

The slice is valid until a part of this kind is added to or removed from any thing.

Asserts:
- `kind` is a registered part.
- `T` is the type `kind` was registered with.
- the system declared `kind` in its writes (stuff variant).
*/
write_parts :: proc {
	world_write_parts,
	stuff_write_parts,
}

/*
Gets every thing that has this part, in the same order as `get_parts`.

The slice is valid until a part of this kind is added to or removed from any thing.

Asserts:
- `kind` is a registered part.
- the system declared `kind` in its reads or writes (stuff variant).
*/
get_things :: proc {
	world_get_things,
	stuff_get_things,
}

/*
Counts the things that have this part.

Asserts:
- `kind` is a registered part.
- the system declared `kind` in its reads or writes (stuff variant).
*/
count_parts :: proc {
	world_count_parts,
	stuff_count_parts,
}

/*
Sets the thing's part, adding it or overwriting the one it has. Takes a value, a pointer to
copy from (nil zeroes the part) or just the type to zero it. Overwriting runs `destroy` on the
old part.

Returns the part in the world, or nil if the thing is dead. The pointer is valid until a part of
this kind is added to or removed from any thing.

Asserts:
- `kind` is a registered part.
- `T` is the type `kind` was registered with.
- the system declared `kind` in its writes (stuff variant).
*/
set_now :: proc {
	world_set_value_now,
	world_set_pointer_now,
	world_set_zero_now,
	stuff_set_value_now,
	stuff_set_pointer_now,
	stuff_set_zero_now,
}

/*
Adds a zeroed part to the thing, or zeroes the one it has. Meant for tags, where there is no
value to set.

Returns false if the thing is dead.

Asserts:
- `kind` is a registered part.
- the system declared `kind` in its writes (stuff variant).
*/
add_now :: proc {
	world_add_now,
	stuff_add_now,
}

/*
Removes the thing's part and runs `destroy` on it.

Returns false if the thing is dead or doesn't have the part.

Asserts:
- `kind` is a registered part.
- the system declared `kind` in its writes (stuff variant).
*/
remove_now :: proc {
	world_remove_now,
	stuff_remove_now,
}

/*
Records a set to run on the next apply, with the same variants as `set_now`. The value is copied
when recorded. A thing that is dead by then is skipped, and THING_NIL is not recorded at all.

Asserts:
- `kind` is a registered part.
- `T` is the type `kind` was registered with.
*/
set_later :: proc {
	world_set_value_later,
	world_set_pointer_later,
	world_set_zero_later,
	stuff_set_value_later,
	stuff_set_pointer_later,
	stuff_set_zero_later,
}

/*
Records an `add_now` to run on the next apply. A thing that is dead by then is skipped, and
THING_NIL is not recorded at all.

Asserts:
- `kind` is a registered part.
*/
add_later :: proc {
	world_add_later,
	stuff_add_later,
}

/*
Records a `remove_now` to run on the next apply. A thing that is dead by then, or no longer has
the part, is skipped, and THING_NIL is not recorded at all.

Asserts:
- `kind` is a registered part.
*/
remove_later :: proc {
	world_remove_later,
	stuff_remove_later,
}

// >------------------------------------------------------------------ Hierarchy

/*
Attaches `child` as the last child of `parent` in the hierarchy of `kind`, moving it with its
whole subtree if it already has a parent. Does nothing if `child` is already a child of `parent`.
A thing is in a hierarchy only while it has a parent or a child there, so an old root parent left
without children drops out. Killing a thing removes it from every hierarchy and makes its
children roots, see `kill_tree_now` to kill them too.

Returns false if either thing is dead.

Asserts:
- `kind` is a registered hierarchy.
- `child` and `parent` are different things.
- `parent` isn't a descendant of `child`.
- the system declared `kind` in its writes (stuff variant).
*/
attach_now :: proc {
	world_attach_now,
	stuff_attach_now,
}

/*
Records an `attach_now` to run on the next apply. It is skipped if either thing is dead by then,
or if `parent` has become a descendant of `child`. THING_NIL is not recorded at all.

Asserts:
- `kind` is a registered hierarchy.
- `child` and `parent` are different things.
*/
attach_later :: proc {
	world_attach_later,
	stuff_attach_later,
}

/*
Detaches `child` from its parent and makes it a root, with its subtree still attached. A child
without children drops out of the hierarchy instead, and so does a root parent left without
children.

Returns false if `child` is dead or has no parent.

Asserts:
- `kind` is a registered hierarchy.
- the system declared `kind` in its writes (stuff variant).
*/
detach_now :: proc {
	world_detach_now,
	stuff_detach_now,
}

/*
Records a `detach_now` to run on the next apply. It is skipped if `child` is dead or has no parent
by then, and THING_NIL is not recorded at all.

Asserts:
- `kind` is a registered hierarchy.
*/
detach_later :: proc {
	world_detach_later,
	stuff_detach_later,
}

/*
Gets the thing's parent. The hierarchy query variant gets the parent of the current thing in the
query's hierarchy, read from the links rather than the order.

Returns THING_NIL if the thing is dead, a root or not in the hierarchy.

Asserts:
- `kind` is a registered hierarchy.
- the query has a current thing (hierarchy query variant only).
- the system declared `kind` in its reads or writes (stuff variant).
*/
get_parent :: proc {
	world_get_parent,
	stuff_get_parent,
	hierarchy_query_get_parent,
}

/*
Gets the thing's first child.

Returns THING_NIL if the thing is dead or has no children.

Asserts:
- `kind` is a registered hierarchy.
- the system declared `kind` in its reads or writes (stuff variant).
*/
get_first_child :: proc {
	world_get_first_child,
	stuff_get_first_child,
}

/*
Gets the thing's next sibling. Roots are siblings of each other.

Returns THING_NIL if the thing is dead, the last sibling or not in the hierarchy.

Asserts:
- `kind` is a registered hierarchy.
- the system declared `kind` in its reads or writes (stuff variant).
*/
get_next_sibling :: proc {
	world_get_next_sibling,
	stuff_get_next_sibling,
}

/*
Makes an iterator over the thing's children, in the order they were attached. Advance it with
`for child in hierarchy_children_iter(&it)`. Attaching, detaching or killing while iterating
is not supported.

A dead thing has no children.

Asserts:
- `kind` is a registered hierarchy.
- the system declared `kind` in its reads or writes (stuff variant).
*/
iter_children :: proc {
	world_iter_children,
	stuff_iter_children,
}

/*
Makes an iterator over the roots, see `iter_children`.

Asserts:
- `kind` is a registered hierarchy.
- the system declared `kind` in its reads or writes (stuff variant).
*/
iter_roots :: proc {
	world_iter_roots,
	stuff_iter_roots,
}

/*
Checks whether `ancestor` is a strict ancestor of `thing`, as of the last rebuild of the
hierarchy.

Returns false if either thing is dead or wasn't in the hierarchy at the last rebuild.

Asserts:
- `kind` is a registered hierarchy.
- the system declared `kind` in its reads or writes (stuff variant).
*/
is_ancestor :: proc {
	world_is_ancestor,
	stuff_is_ancestor,
}

/*
Gets every thing in the hierarchy as of its last `world_rebuild_hierarchy`: each tree in
pre-order, roots in the order they became roots. Parents come before their children and every
subtree is a contiguous range, see `get_hierarchy_ends`.

Things killed since the last rebuild are still in it. The slice is valid until the next rebuild.

Asserts:
- `kind` is a registered hierarchy.
- the system declared `kind` in its reads or writes (stuff variant).
*/
get_hierarchy_order :: proc {
	world_get_hierarchy_order,
	stuff_get_hierarchy_order,
}

/*
Gets the depth of every thing in `get_hierarchy_order`, roots are at depth 0.

The slice is valid until the next rebuild.

Asserts:
- `kind` is a registered hierarchy.
- the system declared `kind` in its reads or writes (stuff variant).
*/
get_hierarchy_depths :: proc {
	world_get_hierarchy_depths,
	stuff_get_hierarchy_depths,
}

/*
Gets, for every thing in `get_hierarchy_order`, the position one past its subtree. The subtree of
the thing at `i` is `order[i:ends[i]]`.

The slice is valid until the next rebuild.

Asserts:
- `kind` is a registered hierarchy.
- the system declared `kind` in its reads or writes (stuff variant).
*/
get_hierarchy_ends :: proc {
	world_get_hierarchy_ends,
	stuff_get_hierarchy_ends,
}

/*
Gets the thing's subtree from `get_hierarchy_order`, starting with the thing itself.

Returns nil if the thing is dead or wasn't in the hierarchy at the last rebuild. The slice is
valid until the next rebuild.

Asserts:
- `kind` is a registered hierarchy.
- the system declared `kind` in its reads or writes (stuff variant).
*/
get_subtree :: proc {
	world_get_subtree,
	stuff_get_subtree,
}

// >-------------------------------------------------------------------- Stashes

/*
Gets a copy of the stash, for reading.

Asserts:
- `kind` is a registered stash.
- `T` is the type `kind` was registered with.
- the system declared `kind` in its reads or writes (stuff variant).
*/
get_stash :: proc {
	world_get_stash,
	stuff_get_stash,
}

/*
Gets the stash, for writing.

The pointer is never nil and stays valid until the world is destroyed.

Asserts:
- `kind` is a registered stash.
- `T` is the type `kind` was registered with.
- the system declared `kind` in its writes (stuff variant).
*/
write_stash :: proc {
	world_write_stash,
	stuff_write_stash,
}
