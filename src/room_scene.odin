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

	// gfx.camera_add_resoulution_independed_ext(
	// 	&data.camera,
	// 	gfx.ivec2{cast(i32)eldr.get_width(), cast(i32)eldr.get_height()},
	// 	gfx.ivec2{3000, 900},
	// )

	data.room_texture_h = eldr.load_texture("./assets/room.png")
	data.model = eldr.load_model("./assets/room.obj")

	pipeline_h := create_default_pipeline()

	eldr.material_init(&data.material, pipeline_h)
	data.material.texture_h = data.room_texture_h
	data.material.color = {1, 1, 1, 1}
	eldr.material_update(&data.material)
	append(&data.model.materials, data.material)
	append(&data.model.mesh_material, 0)

	eldr.transform_init(&data.transform)

	data.transform.position = {0, 0, 0}
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
	// eldr.camera_set_zoom(&data.camera, vec3{result, 1, 1})
	data.transform.position.x = result * 2
	data.transform.dirty = true
	eldr.transform_apply(&data.transform)
}

room_scene_draw :: proc(s: ^Scene) {
	data := cast(^Room_Scene_Data)s.data

	pipeline := eldr.get_graphics_pipeline(data.pipeline_h)

	eldr.transform_apply(&data.transform)

	frame := eldr.begin_render()

	if eldr.screen_resized() {
		eldr.camera_set_aspect(&data.camera, cast(f32)eldr.get_screen_width(), cast(f32)eldr.get_screen_height())
		eldr.camera_apply(&data.camera)
	}
	// Begin gfx.
	// --------------------------------------------------------------------------------------------------------------------

	eldr.cmd_set_full_viewport(frame.cmd)
	// gfx.resoulution_independed_set_viewport(&data.camera, eldr.ctx.g, frame.cmd)

	// Postprocessing

	surface, ok := eldr.get_surface(data.surface_h)
	assert(ok)
	// Surface
	surface_frame := eldr.surface_begin(surface)
	eldr.draw_model(data.model, data.camera, data.transform, frame.cmd)
	eldr.surface_end(surface, surface_frame)

	// Swapchain
	eldr.begin_draw(frame)
	eldr.surface_draw(surface, frame, data.postprocessing_pipeline_h)
	eldr.end_draw(frame)


	// No Postprocessing
	// eldr.begin_draw(frame)
	// eldr.draw_model(data.model, data.camera, data.transform, frame.cmd)
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
