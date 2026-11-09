package ecs

// >--------------------------------------------------------------------- Handle

HANDLE_IDX_BITS :: 20
HANDLE_GEN_BITS :: 12
HANDLE_IDX_COUNT :: 1 << HANDLE_IDX_BITS
HANDLE_GEN_COUNT :: 1 << HANDLE_GEN_BITS

HANDLE_POOL_MIN_CAPACITY :: 64
HANDLE_POOL_MAX_CAPACITY :: HANDLE_IDX_COUNT

// >---------------------------------------------------------------------- Thing

THING_IDX_BITS :: HANDLE_IDX_BITS
THING_GEN_BITS :: HANDLE_GEN_BITS
THING_IDX_COUNT :: HANDLE_IDX_COUNT
THING_GEN_COUNT :: HANDLE_GEN_COUNT
THING_NIL :: Thing{}

THING_POOL_MIN_CAPACITY :: HANDLE_POOL_MIN_CAPACITY
THING_POOL_MAX_CAPACITY :: HANDLE_POOL_MAX_CAPACITY
THING_POOL_DEFAULT_CAPACITY :: 1 << 16

// >----------------------------------------------------------------------- Part

PART_SET_PAGE_BITS :: 14
PART_SET_PAGE_SIZE :: 1 << PART_SET_PAGE_BITS
PART_SET_PAGE_COUNT :: THING_IDX_COUNT / PART_SET_PAGE_SIZE
PART_SET_MAX_CAPACITY :: THING_IDX_COUNT

#assert(PART_SET_PAGE_BITS <= THING_IDX_BITS)

// >------------------------------------------------------------------ Archetype

ARCHETYPE_POOL_MIN_CAPACITY :: THING_POOL_MIN_CAPACITY
ARCHETYPE_POOL_MAX_CAPACITY :: THING_POOL_MAX_CAPACITY
ARCHETYPE_POOL_DEFAULT_CAPACITY :: THING_POOL_DEFAULT_CAPACITY

// >---------------------------------------------------------------------- Stash

STASH_POOL_DEFAULT_CAPACITY :: 1 << 16

// >------------------------------------------------------------------------ Cmd

/* The most bytes of parts a buffer holds between resets. */
CMD_BUFFER_MAX_PARTS_CAPACITY :: int(max(Cmd_Offset))

/* The largest part `cmd_buffer_record_set_value` accepts, in bytes. */
CMD_BUFFER_MAX_PART_SIZE :: int(max(Cmd_Size))

CMD_BUFFER_DEFAULT_CAPACITY :: 1 << 8
CMD_BUFFER_DEFAULT_PARTS_CAPACITY :: 1 << 12

// >--------------------------------------------------------------------- System

SYSTEM_POOL_DEFAULT_CAPACITY :: 64

// >------------------------------------------------------------------ Hierarchy

HIERARCHY_SET_MIN_CAPACITY :: THING_POOL_MIN_CAPACITY
HIERARCHY_SET_MAX_CAPACITY :: THING_POOL_MAX_CAPACITY

/* The deepest a thing can sit in a hierarchy, roots are at depth 0. */
HIERARCHY_MAX_DEPTH :: int(max(Hierarchy_Depth))
