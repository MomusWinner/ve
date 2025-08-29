package main

import "base:runtime"
import "core:log"
import "core:math"
import "core:math/linalg/glsl"
import "core:math/rand"
import "eldr"
import gfx "eldr/graphics"
import "vendor:glfw"
import vk "vendor:vulkan"

create_empty_scene :: proc() -> Scene {
	return Scene {
		init = empty_scene_init,
		update = empty_scene_update,
		draw = empty_scene_draw,
		destroy = empty_scene_destroy,
	}
}

empty_scene_init :: proc(s: ^Scene) {
}

empty_scene_update :: proc(s: ^Scene, dt: f64) {
}

empty_scene_draw :: proc(s: ^Scene) {
	e := &eldr.ctx

	gfx.begin_render(e.g)
	// Begin gfx. ------------------------------

	viewport := vk.Viewport {
		width    = f32(e.g.swapchain.extent.width),
		height   = f32(e.g.swapchain.extent.height),
		maxDepth = 1.0,
	}
	vk.CmdSetViewport(e.g.cmd, 0, 1, &viewport)

	scissor := vk.Rect2D {
		extent = e.g.swapchain.extent,
	}
	vk.CmdSetScissor(e.g.cmd, 0, 1, &scissor)

	// End gfx. ------------------------------
	gfx.end_render(e.g, []vk.Semaphore{}, {})

}

empty_scene_destroy :: proc(s: ^Scene) {
}
