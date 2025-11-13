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

Room_Scene_Data :: struct {
	room_texture_h:            eldr.Texture_Handle,
	model:                     eldr.Model,
	material:                  eldr.Material,
	transform:                 eldr.Transform,
	camera:                    eldr.Camera,
	pipeline_h:                eldr.Pipeline_Handle,
	surface_h:                 eldr.Surface_Handle,
	postprocessing_pipeline_h: eldr.Pipeline_Handle,
}

create_room_scene :: proc() -> Scene {
	return Scene {
		init = room_scene_init,
		update = room_scene_update,
		draw = room_scene_draw,
		destroy = room_scene_destroy,
	}
}

depth_h: eldr.Texture_Handle

room_scene_init :: proc(s: ^Scene) {
	data := new(Room_Scene_Data)

	eldr.camera_init(&data.camera)
	data.camera.position = {0, 0, 2}
	data.camera.target = {0, 0, 0}
	data.camera.up = {0, 1, 0}
	data.camera.dirty = true

	data.room_texture_h = eldr.load_texture("./assets/room.png")
	data.model = eldr.load_model("./assets/room.obj")

	pipeline_h := create_default_pipeline()

	eldr.material_init(&data.material, pipeline_h)
	data.material.texture_h = data.room_texture_h

	data.material.color = {1, 1, 1, 1}
	append(&data.model.materials, data.material)
	append(&data.model.mesh_material, 0)

	eldr.init_transform(&data.transform)

	data.transform.position = {0, 0, -1}
	data.transform.scale = {1, 1, 1}
	data.transform.dirty = true

	data.surface_h = eldr.create_surface()
	surface, ok := eldr.get_surface(data.surface_h)
	assert(ok)
	eldr.surface_add_color_attachment(surface)
	eldr.surface_add_depth_attachment(surface)
	data.postprocessing_pipeline_h = create_postprocessing_pipeline()

	s.data = data
}

value: f32
room_scene_update :: proc(s: ^Scene) {
	data := cast(^Room_Scene_Data)s.data
	value += eldr.get_delta_time()
	result := math.sin_f32(value)
	data.transform.position.x = result * 2
	data.transform.dirty = true
}

room_scene_draw :: proc(s: ^Scene) {
	data := cast(^Room_Scene_Data)s.data

	pipeline := eldr.get_graphics_pipeline(data.pipeline_h)

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
		eldr.draw_model(surface_frame, data.model, &data.camera, &data.transform)
	}
	eldr.end_surface(surface, surface_frame)

	// Swapchain
	base_frame := eldr.begin_draw(frame)
	{
		eldr.draw_surface(surface, base_frame, data.postprocessing_pipeline_h)
	}
	eldr.end_draw(base_frame)

	// // No Postprocessing
	// base_frame := eldr.begin_draw(frame)
	// {
	// 	eldr.draw_model(base_frame, data.model, &data.camera, &data.transform)
	// }
	// eldr.end_draw(frame)

	// --------------------------------------------------------------------------------------------------------------------
	// End gfx.
	eldr.end_render(frame)
}

room_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Room_Scene_Data)s.data

	eldr.unload_texture(data.room_texture_h)
	eldr.destroy_model(&data.model)
	eldr.destroy_surface(data.surface_h)

	free(data)
}
