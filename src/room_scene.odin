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

room_scene_init :: proc(s: ^Scene) {
	data := new(Room_Scene_Data)

	eldr.camera_init(&data.camera, cast(f32)eldr.get_screen_width(), cast(f32)eldr.get_screen_height())
	data.camera.position = {0, 0, 2}
	data.camera.target = {0, 0, 0}
	data.camera.up = {0, 1, 0}
	data.camera.dirty = true
	eldr.camera_apply(&data.camera)

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

	data.surface_h = eldr.create_surface(eldr.get_screen_width(), eldr.get_screen_height())
	surface, ok := eldr.get_surface(data.surface_h)
	assert(ok)
	eldr.surface_add_color_attachment(surface)
	eldr.surface_add_depth_attachment(surface)
	data.postprocessing_pipeline_h = create_postprocessing_pipeline()

	s.data = data
}

value: f32
room_scene_update :: proc(s: ^Scene, dt: f64) {
	data := cast(^Room_Scene_Data)s.data
	value += cast(f32)dt
	result := math.sin_f32(value)
	data.transform.position.x = result * 2
	data.transform.dirty = true
}

room_scene_draw :: proc(s: ^Scene) {
	data := cast(^Room_Scene_Data)s.data

	pipeline := eldr.get_graphics_pipeline(data.pipeline_h)

	frame := eldr.begin_render()

	if eldr.screen_resized() {
		eldr.camera_set_aspect(&data.camera, cast(f32)eldr.get_screen_width(), cast(f32)eldr.get_screen_height())
		eldr.camera_apply(&data.camera)
	}
	// Begin gfx.
	// --------------------------------------------------------------------------------------------------------------------

	eldr.cmd_set_full_viewport(frame.cmd)

	// // Postprocessing
	//
	// // Surface
	// surface, ok := eldr.get_surface(data.surface_h)
	// assert(ok)
	// surface_frame := eldr.surface_begin(surface)
	// eldr.draw_model(data.model, data.camera, data.transform, frame.cmd)
	// gfx.draw_text(
	// 	eldr.ctx.g,
	// 	eldr.ctx.g.text_manager,
	// 	surface_frame,
	// 	"H",
	// 	data.font,
	// 	vec3{0, 0, 0},
	// 	gfx.vec4{255, 0, 0, 255},
	// 	5,
	// )
	// eldr.surface_end(surface, surface_frame)
	//
	// // Swapchain
	// eldr.begin_draw(frame)
	// eldr.surface_draw(surface, frame, data.postprocessing_pipeline_h)
	// eldr.end_draw(frame)

	// No Postprocessing
	eldr.begin_draw(frame)

	eldr.draw_model(data.model, data.camera, &data.transform, frame.cmd)

	eldr.end_draw(frame)

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
