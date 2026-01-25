package main

import ve ".."
import gfx "../graphics"
import "base:runtime"
import "core:log"
import "core:math"
import "core:math/linalg/glsl"
import "core:math/rand"
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

empty_scene_update :: proc(s: ^Scene) {
}

empty_scene_draw :: proc(s: ^Scene) {
	e := &ve.ctx

	frame_data := gfx.begin_render()
	// Begin gfx. ------------------------------

	gfx.set_full_viewport_scissor(frame_data)

	base_frame := gfx.begin_draw(frame_data)

	gfx.end_draw(frame_data)

	sync_data := gfx.Sync_Data {
		wait_semaphore_infos = make([]vk.SemaphoreSubmitInfo, 0),
	}
	// End gfx. ------------------------------
	gfx.end_render(frame_data, sync_data)

}

empty_scene_destroy :: proc(s: ^Scene) {
}
