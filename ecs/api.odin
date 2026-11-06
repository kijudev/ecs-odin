package ecs

// >---------------------------------------------------------------------- Setup

register :: world_register
is_registered :: world_is_registered
register_resource :: world_register_resource
is_resource_registered :: world_is_resource_registered

// >--------------------------------------------------------------------- Things

spawn :: proc {
	world_spawn,
	stuff_spawn,
}

kill_now :: proc {
	world_kill_now,
	stuff_kill_now,
}

kill_later :: proc {
	world_kill_later,
	stuff_kill_later,
}

is_alive :: proc {
	world_is_alive,
	stuff_is_alive,
}

count_alive :: proc {
	world_count_alive,
	stuff_count_alive,
}

count_free :: proc {
	world_count_free,
	stuff_count_free,
}

get_thing :: proc {
	query_get_thing,
}

// >---------------------------------------------------------------------- Parts

has :: proc {
	world_has,
	stuff_has,
	query_has,
}

get_part :: proc {
	world_get_part,
	stuff_get_part,
	query_get_part,
}

get_parts :: proc {
	world_get_parts,
	stuff_get_parts,
}

get_things :: proc {
	world_get_things,
	stuff_get_things,
}

count_parts :: proc {
	world_count_parts,
	stuff_count_parts,
}

set_now :: proc {
	world_set_value_now,
	world_set_pointer_now,
	world_set_zero_now,
	stuff_set_value_now,
	stuff_set_pointer_now,
	stuff_set_zero_now,
}

add_now :: proc {
	world_add_now,
	stuff_add_now,
}

remove_now :: proc {
	world_remove_now,
	stuff_remove_now,
}

set_later :: proc {
	world_set_value_later,
	world_set_pointer_later,
	world_set_zero_later,
	stuff_set_value_later,
	stuff_set_pointer_later,
	stuff_set_zero_later,
}

add_later :: proc {
	world_add_later,
	stuff_add_later,
}

remove_later :: proc {
	world_remove_later,
	stuff_remove_later,
}

// >------------------------------------------------------------------ Resources

get_resource :: proc {
	world_get_resource,
	stuff_get_resource,
}
