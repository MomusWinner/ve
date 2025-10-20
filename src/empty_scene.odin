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

	frame_data := eldr.begin_render()
	// Begin gfx. ------------------------------

	eldr.cmd_set_full_viewport(frame_data.cmd)

	eldr.begin_draw(frame_data)

	eldr.end_draw(frame_data)

	// End gfx. ------------------------------
	eldr.end_render(frame_data)

}

empty_scene_destroy :: proc(s: ^Scene) {
}
