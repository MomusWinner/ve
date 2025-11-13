package main

import "base:runtime"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:time"
import "eldr"
import gfx "eldr/graphics"
import "vendor:glfw"
import vk "vendor:vulkan"

Test_Scene_Data :: struct {
	room_texture_h:            eldr.Texture_Handle,
	camera:                    eldr.Camera,
	surface_h:                 eldr.Surface_Handle,
	postprocessing_pipeline_h: eldr.Pipeline_Handle,
}

create_test_scene :: proc() -> Scene {
	return Scene {
		init = test_scene_init,
		update = test_scene_update,
		draw = test_scene_draw,
		destroy = test_scene_destroy,
	}
}

test_scene_init :: proc(s: ^Scene) {
	data := new(Test_Scene_Data)

	eldr.camera_init(&data.camera)
	data.camera.position = {0, 0, 2}
	data.camera.target = {0, 0, 0}
	data.camera.up = {0, 1, 0}
	data.camera.dirty = true

	data.surface_h = eldr.create_surface()
	surface, ok := eldr.get_surface(data.surface_h)
	assert(ok)
	eldr.surface_add_color_attachment(surface)
	eldr.surface_add_depth_attachment(surface)
	data.postprocessing_pipeline_h = create_postprocessing_pipeline()

	s.data = data
}

test_scene_update :: proc(s: ^Scene) {
	// data := cast(^Room_Scene_Data)s.data
	// value += cast(f32)dt
	// result := math.sin_f32(value)
	// data.transform.position.x = result * 2
	// data.transform.dirty = true
}

test_scene_draw :: proc(s: ^Scene) {
	data := cast(^Test_Scene_Data)s.data

	frame := eldr.begin_render()

	// Begin gfx.
	// --------------------------------------------------------------------------------------------------------------------

	eldr.set_full_viewport_scissor(frame)

	// Postprocessing

	// Surface
	surface, ok := eldr.get_surface(data.surface_h)
	assert(ok)

	surface_frame := eldr.begin_surface(surface, frame)
	{
		gfx.draw_square(eldr.ctx.gfx, surface_frame, &data.camera, {0, 0, 0}, {1, 1, 1}, {1, 0, 0, 1})
	}
	eldr.end_surface(surface, surface_frame)

	// Swapchain
	base_frame := eldr.begin_draw(frame)
	{
		eldr.draw_surface(surface, base_frame, data.postprocessing_pipeline_h)
	}
	eldr.end_draw(frame)


	// No Postprocessing
	// eldr.begin_draw(frame)
	// {
	// 	gfx.draw_square(eldr.ctx.gfx, surface_frame, data.camera, {0, 0, 0}, {1, 1, 1}, {1, 0, 0, 1})
	// }
	// eldr.end_draw(frame)

	// --------------------------------------------------------------------------------------------------------------------
	// End gfx.
	eldr.end_render(frame)
}

test_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Test_Scene_Data)s.data

	eldr.destroy_surface(data.surface_h)

	free(data)
}
