package main

import "base:runtime"

import "core:fmt"
import "core:log"
import "core:math/linalg/glsl"

import "core:c"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:time"

import "vendor:glfw"
import vk "vendor:vulkan"

import "eldr"
import gfx "eldr/graphics"

g_ctx: runtime.Context

vec3 :: [3]f32

last_time: f64
dt: f64

quite: bool = false
reload: bool = false

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

	// TODO: update vendor bindings to glfw 3.4 and use this to set a custom allocator.
	// glfw.InitAllocator()

	// TODO: set up Vulkan allocator.

	if !glfw.Init() {log.panic("glfw: could not be initialized")}
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)

	window := glfw.CreateWindow(800, 600, "Vulkan", nil, nil)
	defer glfw.DestroyWindow(window) // TODO: move to render

	key_handler :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int) {
		if key == glfw.KEY_ESCAPE || key == glfw.KEY_Q {
			quite = true
		}
		if key == glfw.KEY_R {
			reload = true
		}
	}

	glfw.SetKeyCallback(window, key_handler)
	glfw.SetErrorCallback(glfw_error_callback)


	eldr.init_graphic(window)
	g := eldr.ctx.g // TODO:
	defer eldr.destroy_eldr()

	scene := create_room_scene()
	// scene := create_empty_scene()

	scene.init(&scene)

	for !glfw.WindowShouldClose(window) {
		free_all(context.temp_allocator)

		glfw.PollEvents()

		if (quite) {
			break
		}

		if (reload) {
			vk.WaitForFences(g.device, 1, &g.fence, true, max(u64))
			gfx.pipeline_hot_reload(g)
			reload = false
		}

		// dt = glfw.GetTime() - last_time
		// last_time = glfw.GetTime()
		// log.info("FPS: ", 1 / dt)

		scene.update(&scene, dt)
		scene.draw(&scene)
	}
	vk.DeviceWaitIdle(g.device)

	scene.destroy(&scene)

	log.info("Successfuly close")
}

glfw_error_callback :: proc "c" (code: i32, description: cstring) {
	context = g_ctx
	log.errorf("glfw: %i: %s", code, description)
}
