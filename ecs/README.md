# Things

`Thing` is an opaque handle type. It is a `u32` bit field with two parts: 20-bit `idx` and a 12-bit `gen` counter.
`THING_NIL` is a nil handle (zeroed out).

## `Thing_Pool` design

Thing pool consists of three arrays: alive bitset containing boolean flags, generations array of `u16`,
and a stack of free slots that could be reused.
This approach allows for optimal memory access when checking if a thing is alive or valid.
It also allows for some heuristics to be chosen when slots are being recycled. The stack can be
used to reserve some space for a bunch of things to be allocated close to one another.

# Parts

# Systems
