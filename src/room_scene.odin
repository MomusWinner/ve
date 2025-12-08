package main

import "base:runtime"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:time"
import "eldr"
import gfx "eldr/graphics"

Room_Scene_Data :: struct {
	room_texture_h:            gfx.Texture_Handle,
	model:                     gfx.Model,
	material:                  gfx.Material,
	transform:                 gfx.Gfx_Transform,
	camera:                    gfx.Camera,
	pipeline_h:                gfx.Pipeline_Handle,
	surface_h:                 gfx.Surface_Handle,
	postprocessing_pipeline_h: gfx.Pipeline_Handle,
}

create_room_scene :: proc() -> Scene {
	return Scene {
		init = room_scene_init,
		update = room_scene_update,
		draw = room_scene_draw,
		destroy = room_scene_destroy,
	}
}

depth_h: gfx.Texture_Handle

room_scene_init :: proc(s: ^Scene) {
	data := new(Room_Scene_Data)

	gfx.camera_init(&data.camera)
	data.camera.position = {0, 0, 2}
	data.camera.target = {0, 0, 0}
	data.camera.up = {0, 1, 0}
	data.camera.dirty = true

	data.room_texture_h = eldr.load_texture("./assets/room.png")
	data.model = eldr.load_model("./assets/room.obj")

	data.pipeline_h = create_default_pipeline()

	gfx.init_mtrl_base(&data.material, data.pipeline_h)
	gfx.mtrl_base_set_texture_h(&data.material, data.room_texture_h)

	append(&data.model.materials, data.material)
	append(&data.model.mesh_material, 0)

	gfx.init_gfx_trf(&data.transform)

	data.transform.position = {0, -0.5, -1}
	data.transform.scale = {0.5, 0.5, 0.5}
	data.transform.dirty = true

	data.surface_h = gfx.create_surface(._4)
	surface, ok := gfx.get_surface(data.surface_h)
	assert(ok)
	gfx.surface_add_color_attachment(surface)
	gfx.surface_add_depth_attachment(surface)
	data.postprocessing_pipeline_h = create_postprocessing_pipeline()

	s.data = data
}

value: f32
room_scene_update :: proc(s: ^Scene) {
	data := cast(^Room_Scene_Data)s.data
	value += eldr.get_delta_time()
	// result := math.sin_f32(value)
	eldr.trf_rotate(&data.transform, {0, 1, 0}, value)
	// dir := eldr.trf_get_right(&data.transform)
	// eldr.trf_set_position(&data.transform, dir * result)
}

room_scene_draw :: proc(s: ^Scene) {
	data := cast(^Room_Scene_Data)s.data

	pipeline, p_ok := gfx.get_graphics_pipeline(data.pipeline_h)
	assert(p_ok)

	frame := gfx.begin_render()

	// Begin gfx.
	// --------------------------------------------------------------------------------------------------------------------

	gfx.set_full_viewport_scissor(frame)

	// Postprocessing

	// Surface
	surface, ok := gfx.get_surface(data.surface_h)
	assert(ok)

	surface_frame := gfx.begin_surface(surface, frame)
	{
		gfx.draw_model(surface_frame, data.model, &data.camera, &data.transform)

		gfx.draw_square(
			surface_frame,
			&data.camera,
			data.transform.position + eldr.trf_get_up(&data.transform) * 0.5,
			0.1,
			{1, 0, 0, 1},
		)
	}
	gfx.end_surface(surface, surface_frame)

	// Swapchain
	base_frame := gfx.begin_draw(frame)
	{
		gfx.draw_surface(surface, &data.camera, base_frame, data.postprocessing_pipeline_h)
	}
	gfx.end_draw(base_frame)

	// // No Postprocessing
	// base_frame := gfx.begin_draw(frame)
	// {
	// 	gfx.draw_model(base_frame, data.model, &data.camera, &data.transform)
	// }
	// gfx.end_draw(frame)

	// --------------------------------------------------------------------------------------------------------------------
	// End gfx.
	gfx.end_render(frame)
}

room_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Room_Scene_Data)s.data

	eldr.unload_texture(data.room_texture_h)
	gfx.destroy_model(&data.model)
	gfx.destroy_surface(data.surface_h)

	free(data)
}
