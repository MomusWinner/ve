package graphics

import sm "core:container/small_array"
import "core:fmt"
import "core:log"

Global_Resource_Manager :: struct {
	slots:      [MAX_SLOT_COUNT]Resource_Handle,
	free_slots: [MAX_SLOT_COUNT]bool,
}

@(private)
_init_g_res_manager :: proc() {
	ctx.g_res_manager = new(Global_Resource_Manager)
	for i in 0 ..< MAX_SLOT_COUNT {
		ctx.g_res_manager.free_slots[i] = true
	}
}

@(private)
_destroy_g_res_manager :: proc() {
	free(ctx.g_res_manager)
}

g_resource_set_slot :: proc(slot: int, handle: Resource_Handle, loc := #caller_location) -> bool {
	_assert_slot_value(slot, loc)
	if !g_resource_slot_is_free(slot, loc) {
		return false
	}

	ctx.g_res_manager.slots[slot] = handle
	ctx.g_res_manager.free_slots[slot] = false

	return true
}

g_resource_get_slot :: proc(slot: int, loc := #caller_location) -> (Resource_Handle, bool) {
	_assert_slot_value(slot, loc)
	if g_resource_slot_is_free(slot, loc) {
		return {}, false
	}

	return ctx.g_res_manager.slots[slot], true
}

g_resource_slot_is_free :: proc(slot: int, loc := #caller_location) -> bool {
	_assert_slot_value(slot, loc)
	return ctx.g_res_manager.free_slots[slot]
}

g_resource_clear_slot :: proc(slot: int, loc := #caller_location) -> Resource_Handle {
	_assert_slot_value(slot, loc)

	ctx.g_res_manager.free_slots[slot] = true
	return ctx.g_res_manager.slots[slot]
}

@(private)
_g_res_manager_get_resource_indices :: proc() -> (indices: [MAX_SLOT_COUNT]u32) {
	for slot, i in ctx.g_res_manager.slots {
		if ctx.g_res_manager.free_slots[i] {
			indices[i] = max(u32)
			continue
		}

		switch &resource in slot {
		case Buffer_Handle:
			indices[i] = resource.index
		case Texture_Handle:
			indices[i] = resource.index
		case Uniform_Buffer_Handle:
			ubo, ok := get_uniform_buffer(resource)
			if !ok do g_resource_clear_slot(i)
			indices[i] = ubo.buffer_h.index
		}
	}

	return
}

@(private = "file")
_assert_slot_value :: #force_inline proc(slot: int, loc := #caller_location) {
	assert(
		slot >= 0 && slot < MAX_SLOT_COUNT,
		fmt.tprintf("Invalid slot: %d. Valid range is [0, %d) exclusive.", slot, MAX_SLOT_COUNT),
		loc,
	)
}
