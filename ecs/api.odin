package ecs

// >---------------------------------------------------------------------- Setup

/*
Registers `kind` as a part of type `T`. `destroy` runs on a part whenever the world drops it:
on remove, overwrite, kill, reset and destroy.

Asserts:
- `kind` is not registered as a part yet.
- `kind` is not registered as a stash.
*/
register_part :: world_register_part

/* Checks whether `kind` is registered as a part. */
is_part_registered :: world_is_part_registered

/*
Registers `kind` as a stash of type `T`. The stash starts zeroed. `destroy` runs on it on reset
and destroy.

Asserts:
- `kind` is not registered as a stash yet.
- `kind` is not registered as a part.

Panics:
- the stash doesn't fit in the remaining stash capacity.
*/
register_stash :: world_register_stash

/* Checks whether `kind` is registered as a stash. */
is_stash_registered :: world_is_stash_registered

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
Kills the thing and removes all its parts.

Returns false if the thing is already dead.
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

Returns THING_NIL before the first `query_next` and once it returns false.
*/
get_thing :: proc {
	query_get_thing,
}

// >---------------------------------------------------------------------- Parts

/*
Checks whether the thing has the part. The query variant checks the current thing.

Returns false for a dead thing.

Asserts:
- `kind` is a registered part.
*/
has :: proc {
	world_has,
	stuff_has,
	query_has,
}

/*
Gets the thing's part. The query variant gets it from the current thing.

Returns nil if the thing doesn't have the part; the query variant never does (unchecked).
The pointer is valid until a part of this kind is added to or removed from any thing.

Asserts:
- `kind` is a registered part.
- `T` is the type `kind` was registered with.
- the query has a current thing that has the part (query variant only).
*/
get_part :: proc {
	world_get_part,
	stuff_get_part,
	query_get_part,
}

/*
Gets every part of this kind, packed, in the same order as `get_things`.

The slice is valid until a part of this kind is added to or removed from any thing.

Asserts:
- `kind` is a registered part.
- `T` is the type `kind` was registered with.
*/
get_parts :: proc {
	world_get_parts,
	stuff_get_parts,
}

/*
Gets every thing that has this part, in the same order as `get_parts`.

The slice is valid until a part of this kind is added to or removed from any thing.

Asserts:
- `kind` is a registered part.
*/
get_things :: proc {
	world_get_things,
	stuff_get_things,
}

/*
Counts the things that have this part.

Asserts:
- `kind` is a registered part.
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

// >-------------------------------------------------------------------- Stashes

/*
Gets the stash.

The pointer is never nil and stays valid until the world is destroyed.

Asserts:
- `kind` is a registered stash.
- `T` is the type `kind` was registered with.
*/
get_stash :: proc {
	world_get_stash,
	stuff_get_stash,
}
