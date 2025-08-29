package main

import "base:runtime"
import "core:log"
import "core:math"
import "core:math/linalg/glsl"
import "core:math/rand"
import "eldr"
import "vendor:glfw"
import vk "vendor:vulkan"

Room_Scene_Data :: struct {
	room_texture_h: eldr.Texture_Handle,
	model:          eldr.Model,
	material:       eldr.Material,
	transform:      eldr.Transform,
	camera:         eldr.Camera,
	pipeline_h:     eldr.Pipeline_Handle,
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
	room_data := new(Room_Scene_Data)

	eldr.camera_init(&room_data.camera)
	room_data.camera.position = {0, 0, 2}
	room_data.camera.target = {0, 0, 0}
	room_data.camera.up = {0, 1, 0}
	room_data.camera.dirty = true

	room_data.room_texture_h = eldr.load_texture("./assets/room.png")
	room_data.model = eldr.load_model("./assets/room.obj")

	pipeline_h := create_default_pipeline()

	eldr.material_init(&room_data.material, pipeline_h)
	room_data.material.texture_h = room_data.room_texture_h
	room_data.material.color = {1, 1, 1, 1}
	eldr.material_update(&room_data.material)
	append(&room_data.model.materials, room_data.material)
	append(&room_data.model.mesh_material, 0)

	eldr.transform_init(&room_data.transform)

	room_data.transform.position = {0, 0, 0}
	room_data.transform.scale = {1, 1, 1}
	room_data.transform.dirty = true

	s.data = room_data
}

room_scene_update :: proc(s: ^Scene, dt: f64) {
}

room_scene_draw :: proc(s: ^Scene) {
	data := cast(^Room_Scene_Data)s.data

	pipeline := eldr.get_graphics_pipeline(data.pipeline_h)

	eldr.camera_apply(&data.camera, cast(f32)eldr.get_width(), cast(f32)eldr.get_height())
	eldr.transform_apply(&data.transform)

	frame, _ := eldr.begin_render()
	// Begin gfx.
	// --------------------------------------------------------------------------------------------------------------------

	eldr.set_full_viewport(frame.cmd)
	eldr.draw_model(data.model, data.camera, data.transform, frame.cmd)

	// --------------------------------------------------------------------------------------------------------------------
	// End gfx.
	eldr.end_render()
}

room_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Room_Scene_Data)s.data

	eldr.unload_texture(data.room_texture_h)

	eldr.destroy_model(&data.model)
	free(data)
}

// UniformBufferObject :: struct {
// 	model:      glsl.mat4,
// 	view:       glsl.mat4,
// 	projection: glsl.mat4,
// }
//
// init_unfiform_buffer :: proc(buffer: ^gfx.Buffer, extend: vk.Extent2D) {
// 	ubo := UniformBufferObject{}
// 	ubo.model = glsl.mat4Rotate(glsl.vec3{0, 0, 0}, glsl.radians_f32(0))
// 	ubo.model = glsl.mat4Translate(glsl.vec3{0, 0, 0})
// 	ubo.view = glsl.mat4LookAt(glsl.vec3{2, 2, 2}, glsl.vec3{0, 0, 0}, glsl.vec3{0, 0, 1})
// 	ubo.projection = glsl.mat4Perspective(
// 		glsl.radians_f32(45),
// 		(cast(f32)extend.width / cast(f32)extend.height),
// 		0.1,
// 		10,
// 	)
// 	// NOTE: GLM was originally designed for OpenGL, where the Y coordinate of the clip coordinates is inverted
// 	ubo.projection[1][1] *= -1
//
// 	runtime.mem_copy(buffer.mapped, &ubo, size_of(ubo))
// }
//
// update_unfiform_buffer :: proc(buffer: ^gfx.Buffer, extend: vk.Extent2D) {
// 	ubo := UniformBufferObject{}
// 	ubo.model = glsl.mat4Rotate(glsl.vec3{1, 1, 1}, cast(f32)glfw.GetTime() * glsl.radians_f32(90))
// 	ubo.view = glsl.mat4LookAt(glsl.vec3{0, 0, 2}, glsl.vec3{0, 0, 0}, glsl.vec3{0, 1, 0})
// 	ubo.projection = glsl.mat4Perspective(
// 		glsl.radians_f32(45),
// 		(cast(f32)extend.width / cast(f32)extend.height),
// 		0.1,
// 		10,
// 	)
// 	// NOTE: GLM was originally designed for OpenGL, where the Y coordinate of the clip coordinates is inverted
// 	ubo.projection[1][1] *= -1
//
// 	runtime.mem_copy(buffer.mapped, &ubo, size_of(ubo)) // TODO: create special function
// }
