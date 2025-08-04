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
import gfx "eldr/graphic"

g_ctx: runtime.Context

vec3 :: [3]f32

UniformBufferObject :: struct {
	model:      glsl.mat4,
	view:       glsl.mat4,
	projection: glsl.mat4,
}

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

	e := new(eldr.Eldr)
	defer eldr.destroy_eldr(e)

	eldr.init_graphic(e, window)

	particle_renderer := gfx.particle_new(e.g)

	texture := eldr.load_texture(e, "./assets/room.png")

	defer eldr.unload_texture(e, &texture)

	uniform_buffer := gfx.create_uniform_buffer(e.g, cast(vk.DeviceSize)size_of(UniformBufferObject))
	defer gfx.destroy_uniform_buffer(e.g, &uniform_buffer)

	model := eldr.load_model(e, "./assets/room.obj")
	defer eldr.destroy_model(e, &model)

	create_default_pipeline(e)

	descriptor_set, _ := gfx.create_descriptor_set(e.g, "default_pipeline", 0, {uniform_buffer, texture})


	// update_unfiform_buffer(&uniform_buffer, e.g.swapchain.extent)
	start_unfiform_buffer(&uniform_buffer, e.g.swapchain.extent)
	for !glfw.WindowShouldClose(window) {
		free_all(context.temp_allocator)

		glfw.PollEvents()

		if (quite) {
			break
		}

		if (reload) {
			vk.WaitForFences(e.g.device, 1, &e.g.fence, true, max(u64))
			gfx.pipeline_hot_reload(e.g)
			reload = false
			log.info("Reloading graphic pipelines")
		}

		dt = glfw.GetTime() - last_time
		last_time = glfw.GetTime()
		log.info("FPS: ", 1 / dt)

		gfx.particle_update_uniform_buffer(particle_renderer, cast(f32)dt)
		gfx.particle_compute(particle_renderer)

		gfx.begin_render(e.g)
		// Begin gfx. ------------------------------
		viewport := vk.Viewport {
			width    = f32(e.g.swapchain.extent.width),
			height   = f32(e.g.swapchain.extent.height),
			maxDepth = 1.0,
		}
		vk.CmdSetViewport(e.g.command_buffer, 0, 1, &viewport)

		scissor := vk.Rect2D {
			extent = e.g.swapchain.extent,
		}
		vk.CmdSetScissor(e.g.command_buffer, 0, 1, &scissor)

		gfx.particle_draw(particle_renderer)
		// gfx.bind_pipeline(e.g, "default_pipeline")
		//
		// offset := vk.DeviceSize{}
		// vk.CmdBindVertexBuffers(e.g.command_buffer, 0, 1, &model.vbo.buffer, &offset)
		// vk.CmdBindIndexBuffer(e.g.command_buffer, model.ebo.buffer, 0, .UINT16)
		//
		// gfx.bind_descriptor_set(e.g, "default_pipeline", &descriptor_set)
		// // vk.CmdDraw(e.g.command_buffer, 3, 1, 0, 0)
		// vk.CmdDrawIndexed(e.g.command_buffer, cast(u32)len(model.indices), 1, 0, 0, 0)


		// End gfx. ------------------------------
		gfx.end_render(e.g, []vk.Semaphore{particle_renderer.semaphore}, {{.VERTEX_INPUT}})
		// gfx.end_render(e.g, []vk.Semaphore{}, {})
	}
	vk.DeviceWaitIdle(e.g.device)
	log.info("Successfuly close")
}

glfw_error_callback :: proc "c" (code: i32, description: cstring) {
	context = g_ctx
	log.errorf("glfw: %i: %s", code, description)
}

update_unfiform_buffer :: proc(buffer: ^gfx.UniformBuffer, extend: vk.Extent2D) {
	ubo := UniformBufferObject{}
	ubo.model = glsl.mat4Rotate(glsl.vec3{1, 1, 1}, cast(f32)glfw.GetTime() * glsl.radians_f32(90))
	ubo.view = glsl.mat4LookAt(glsl.vec3{0, 0, 2}, glsl.vec3{0, 0, 0}, glsl.vec3{0, 1, 0})
	ubo.projection = glsl.mat4Perspective(
		glsl.radians_f32(45),
		(cast(f32)extend.width / cast(f32)extend.height),
		0.1,
		10,
	)
	// NOTE: GLM was originally designed for OpenGL, where the Y coordinate of the clip coordinates is inverted
	ubo.projection[1][1] *= -1

	runtime.mem_copy(buffer.mapped, &ubo, size_of(ubo))
}

start_unfiform_buffer :: proc(buffer: ^gfx.UniformBuffer, extend: vk.Extent2D) {
	ubo := UniformBufferObject{}
	ubo.model = glsl.mat4Rotate(glsl.vec3{0, 0, 0}, glsl.radians_f32(0))
	ubo.model = glsl.mat4Translate(glsl.vec3{0, 0, 0})
	ubo.view = glsl.mat4LookAt(glsl.vec3{2, 2, 2}, glsl.vec3{0, 0, 0}, glsl.vec3{0, 0, 1})
	ubo.projection = glsl.mat4Perspective(
		glsl.radians_f32(45),
		(cast(f32)extend.width / cast(f32)extend.height),
		0.1,
		10,
	)
	// NOTE: GLM was originally designed for OpenGL, where the Y coordinate of the clip coordinates is inverted
	ubo.projection[1][1] *= -1

	runtime.mem_copy(buffer.mapped, &ubo, size_of(ubo))
}


// TODO: remove
// vertices: []gfx.Vertex = {
// 	{{-0.5, -0.5, 0.0}, {1.0, 0.0, 0.0}, {1.0, 0.0}},
// 	{{0.5, -0.5, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0}},
// 	{{0.5, 0.5, 0.0}, {0.0, 0.0, 1.0}, {0.0, 1.0}},
// 	{{-0.5, 0.5, 0.0}, {1.0, 1.0, 1.0}, {1.0, 1.0}},
// 	// --------------------------------------------
// 	{{-0.5, -0.5, -0.5}, {1.0, 0.0, 0.0}, {1.0, 0.0}},
// 	{{0.5, -0.5, -0.5}, {0.0, 1.0, 0.0}, {0.0, 0.0}},
// 	{{0.5, 0.5, -0.5}, {0.0, 0.0, 1.0}, {0.0, 1.0}},
// 	{{-0.5, 0.5, -0.5}, {1.0, 1.0, 1.0}, {1.0, 1.0}},
// }
