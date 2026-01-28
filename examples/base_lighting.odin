package main

import ve ".."
import gfx "../graphics"
import l "../math"
import vemath "../math"
import "base:runtime"
import "core:log"
import "core:math"
import lin "core:math/linalg/glsl"
import "core:math/noise"
import "core:time"

@(uniform_buffer)
Light_Ubo :: struct {
	camera:    gfx.Buffer_Handle,
	direction: vec3,
	color:     vec3,
	shadow:    gfx.Texture_Handle,
}

@(material)
Light_Material :: struct {
	diffuse:    vec3,
	ambient:    vec3,
	specular:   vec3,
	light_data: gfx.Buffer_Handle,
}

Lighting_Scene_Data :: struct {
	model:                gfx.Model,
	ground:               gfx.Model,
	transform:            gfx.Gfx_Transform,
	ground_transform:     gfx.Gfx_Transform,
	camera:               gfx.Camera,
	l_camera:             gfx.Camera,
	shadow_map_surf:      gfx.Surface_Handle,
	shadow_map_view_mesh: gfx.Mesh,
	shadow_map_texture:   gfx.Texture_Handle,
	surf_draw_mat:        gfx.Material_Handle,
	depth_only_mtrl:      gfx.Material_Handle,
	square_trf:           gfx.Gfx_Transform,
	light_data:           gfx.Uniform_Buffer_Handle,
}

DEPTH_SIZE :: 1024 * 2

create_light_scene :: proc() -> Scene {
	return Scene {
		init = light_scene_init,
		update = light_scene_update,
		draw = light_scene_draw,
		destroy = light_scene_destroy,
	}
}

light_scene_init :: proc(s: ^Scene) {
	data := new(Lighting_Scene_Data)

	// Init Camera
	data.camera = gfx.Camera{}
	gfx.camera_init(&data.camera)
	data.camera.position = {0, 2, 8}
	data.camera.target = {0, 0, 0}
	data.camera.up = {0, 1, 0}

	data.l_camera = gfx.Camera{}
	gfx.camera_init(&data.l_camera, .Orthographic)
	data.l_camera.position = {0.0001, 7, 0.0}
	data.l_camera.target = {0, 0, 0}
	data.l_camera.up = {0, 1, 0}
	data.l_camera.near = 1.0
	data.l_camera.far = 40.5
	data.l_camera.fov = 10

	// Load Model
	data.model = ve.load_model("./assets/Suzanne.obj")
	data.ground = gfx.create_square_model()

	pipeline_h := create_light_pipeline()

	// Setup Shadow Map
	data.shadow_map_surf = gfx.create_surface_with_size(DEPTH_SIZE, DEPTH_SIZE, ._1)
	surface, _ := gfx.get_surface(data.shadow_map_surf)

	data.shadow_map_texture = gfx.surface_add_readable_depth_attachment(surface)

	data.light_data = create_ubo_light()
	light_data, _ := gfx.get_uniform_buffer(data.light_data)

	// Setup Material
	light_material_h := create_mtrl_light(pipeline_h)
	light_material, _ := gfx.get_material(light_material_h)

	mtrl_light_set_diffuse(light_material, {0.29, 0.478, 0.588})
	mtrl_light_set_ambient(light_material, 0.1)
	mtrl_light_set_light_data(light_material, light_data.buffer_h)

	ubo_light_set_camera(light_data, data.l_camera._buffer_h)
	ubo_light_set_direction(light_data, {0, -1, 0})
	ubo_light_set_shadow(light_data, data.shadow_map_texture)
	ubo_light_set_color(light_data, 1)

	gfx.model_set_material(&data.model, light_material_h)

	data.ground.materials[0] = light_material_h
	data.depth_only_mtrl = gfx.create_mtrl_empty(create_depth_only_pipeline())

	// Setup Transform
	ve.init_trf(&data.transform)
	ve.trf_set_position(&data.transform, {0, 1, 0})

	ve.init_trf(&data.ground_transform)
	ve.trf_set_position(&data.ground_transform, {0, 0, 0})
	ve.trf_set_scale(&data.ground_transform, 100)
	ve.trf_rotate(&data.ground_transform, {1, 0, 0}, 3.14 / 2)

	ve.init_trf(&data.square_trf)
	ve.trf_set_position(&data.square_trf, {-0.7, -0.7, 0})
	ve.trf_set_scale(&data.square_trf, 0.3)

	data.shadow_map_view_mesh = gfx.create_square_mesh(0.5)

	postprocessing_pipeline_h := create_depth_pipeline()
	pipe, ok_p_ := gfx.get_render_pipeline(postprocessing_pipeline_h)

	// Setup Postprocessing Surface
	data.surf_draw_mat = create_mtrl_postprocessing(postprocessing_pipeline_h)
	surf_draw_mat, _ := gfx.get_material(data.surf_draw_mat)
	mtrl_postprocessing_set_texture(surf_draw_mat, data.shadow_map_texture)

	s.data = data
}

light_scene_update :: proc(s: ^Scene) {
	data := cast(^Lighting_Scene_Data)s.data

	speed: f32 = 2.0
	camera: ^gfx.Camera
	camera = &data.l_camera

	if ve.is_key_down(.Up) {
		camera.position.z += ve.get_delta_time() * speed
	}
	if ve.is_key_down(.Down) {
		camera.position.z -= ve.get_delta_time() * speed
	}
	if ve.is_key_down(.Left) {
		camera.position.x += ve.get_delta_time() * speed
	}
	if ve.is_key_down(.Right) {
		camera.position.x -= ve.get_delta_time() * speed
	}
	camera.dirty = true

	ve.cursor_disable()
	ve.camera_update_simple_controller(&data.camera)
}

light_scene_draw :: proc(s: ^Scene) {
	data := cast(^Lighting_Scene_Data)s.data

	frame := gfx.begin_render()
	surf, _ := gfx.get_surface(data.shadow_map_surf)
	surf_draw_mat, _ := gfx.get_material(data.surf_draw_mat)
	depth_only_mtrl, m_ok := gfx.get_material(data.depth_only_mtrl)
	assert(m_ok)

	// Begin gfx.
	// --------------------------------------------------------------------------------------------------------------------

	surf_frame := gfx.begin_surface(surf, frame)
	{
		gfx.set_depth_bias(surf_frame, 1.25, 0, 4.75)
		gfx.draw_model_solid(surf_frame, data.model, &data.l_camera, &data.transform, depth_only_mtrl)
		gfx.draw_model_solid(surf_frame, data.ground, &data.l_camera, &data.ground_transform, depth_only_mtrl)
	}
	gfx.end_surface(surf, frame)

	base_frame := gfx.begin_draw(frame, {0.933, 0.525, 0.899, 1})
	{
		gfx.set_full_viewport_scissor(base_frame)

		gfx.draw_model(base_frame, data.model, &data.camera, &data.transform)
		gfx.draw_model(base_frame, data.ground, &data.camera, &data.ground_transform)
		// gfx.draw_on_unit_square(base_frame, &data.square_trf, &data.camera, surf_draw_mat)
	}

	gfx.end_draw(frame)

	// --------------------------------------------------------------------------------------------------------------------
	// End gfx.
	gfx.end_render(frame)
}

light_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Lighting_Scene_Data)s.data

	gfx.destroy_model(&data.model)
	gfx.destroy_mesh(&data.shadow_map_view_mesh)
	gfx.destroy_model(&data.ground)

	free(data)
}
