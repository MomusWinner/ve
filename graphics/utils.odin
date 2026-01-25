package graphics

import "../common"
import "base:runtime"
import "core:fmt"
import "core:log"
import vk "vendor:vulkan"

merge :: common.merge
assert_not_nil :: common.assert_not_nil

assert_gfx_ctx :: #force_inline proc(loc := #caller_location) {
	assert(
		ctx.initialized == true,
		"Graphics not initialized. Call 'graphics.init()' before using any graphics functions.",
		loc = loc,
	)
}

@(private)
must :: proc(result: vk.Result, msg: string = "", loc := #caller_location) {
	if result != .SUCCESS {
		log.panicf("vulkan failure: %s (%v)", msg, result, location = loc)
	}
}

assert_frame_data :: #force_inline proc(frame_data: Frame_Data, loc := #caller_location) {
	assert(frame_data.surface_info.type != .None, "Frame data has uninitialized surface information.", loc = loc)
}
