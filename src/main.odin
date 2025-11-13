package main

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"
import "core:math/linalg/glsl"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:time"
import "eldr"
import gfx "eldr/graphics"
import "vendor:glfw"
import vk "vendor:vulkan"

g_ctx: runtime.Context

vec3 :: [3]f32

last_time: f64

reload: bool = false

current_scene: Scene

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)
	g_ctx = context

	key_handler :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int) {
		if key == glfw.KEY_R {
			reload = true
		}
	}

	eldr.init(
		nil,
		fixed_update,
		update,
		draw,
		destroy,
		{gfx = {swapchain_sample_count = ._4}, window = {width = 800, height = 400, title = "VulkanTest"}},
	)

	glfw.SetKeyCallback(eldr.ctx.window, key_handler)
	glfw.SetErrorCallback(glfw_error_callback)

	g := eldr.ctx.gfx // TODO:

	current_scene = create_room_scene()
	// current_scene = create_text_scene()
	// current_scene = create_empty_scene()
	// current_scene = create_test_scene()

	current_scene.init(&current_scene)

	eldr.run()

	log.info("Successfuly close")
}


fixed_update :: proc(user_data: rawptr) {
}

update :: proc(user_data: rawptr) {
	g := eldr.ctx.gfx // TODO:
	if (reload) {
		vk.WaitForFences(g.vulkan_state.device, 1, &g.fence, true, max(u64))
		gfx.pipeline_hot_reload(g)
		reload = false
	}

	current_scene.update(&current_scene) // TODO:
}

draw :: proc(user_data: rawptr) {
	current_scene.draw(&current_scene)
}

destroy :: proc(user_data: rawptr) {
	current_scene.destroy(&current_scene)
}

glfw_error_callback :: proc "c" (code: i32, description: cstring) {
	context = g_ctx
	log.errorf("glfw: %i: %s", code, description)
}
