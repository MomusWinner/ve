package main

import "../eldr"
import gfx "../eldr/graphics"
import "base:runtime"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:time"

Model_Scene_Data :: struct {
	texture_h:                 gfx.Texture_Handle,
	model:                     gfx.Model,
	material:                  gfx.Material,
	transform:                 gfx.Gfx_Transform,
	camera:                    gfx.Camera,
	pipeline_h:                gfx.Pipeline_Handle,
	postprocessing_pipeline_h: gfx.Pipeline_Handle,
	model_rotation:            f32,
}

create_model_scene :: proc() -> Scene {
	return Scene {
		init = model_scene_init,
		update = model_scene_update,
		draw = model_scene_draw,
		destroy = model_scene_destroy,
	}
}

model_scene_init :: proc(s: ^Scene) {
	data := new(Model_Scene_Data)

	// Init Camera
	data.camera = gfx.Camera {
		position = {0, 0, 2},
		target   = {0, 0, 0},
		up       = {0, 1, 0},
	}
	gfx.camera_init(&data.camera)

	// Load Model
	data.texture_h = eldr.load_texture("./assets/room.png")
	data.model = eldr.load_model("./assets/room.obj")
	data.pipeline_h = create_default_pipeline()

	// Setup Material
	gfx.init_mtrl_base(&data.material, data.pipeline_h)
	gfx.mtrl_base_set_texture_h(&data.material, data.texture_h)
	append(&data.model.materials, data.material)
	append(&data.model.mesh_material, 0)

	// Setup Transform
	gfx.init_gfx_trf(&data.transform)
	eldr.trf_set_position(&data.transform, {0, -0.5, -1})
	eldr.trf_set_scale(&data.transform, {0.5, 0.5, 0.5})

	data.postprocessing_pipeline_h = create_postprocessing_pipeline()

	s.data = data
}

model_scene_update :: proc(s: ^Scene) {
	data := cast(^Model_Scene_Data)s.data
	data.model_rotation += eldr.get_delta_time()
	eldr.trf_rotate(&data.transform, {0, 1, 0}, data.model_rotation)
}

model_scene_draw :: proc(s: ^Scene) {
	data := cast(^Model_Scene_Data)s.data

	pipeline, p_ok := gfx.get_graphics_pipeline(data.pipeline_h)
	assert(p_ok)

	frame := gfx.begin_render()

	// Begin gfx.
	// --------------------------------------------------------------------------------------------------------------------

	gfx.set_full_viewport_scissor(frame)

	// No Postprocessing
	base_frame := gfx.begin_draw(frame)
	{
		gfx.draw_model(base_frame, data.model, &data.camera, &data.transform)
	}
	gfx.end_draw(frame)

	// --------------------------------------------------------------------------------------------------------------------
	// End gfx.
	gfx.end_render(frame)
}

model_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Model_Scene_Data)s.data

	eldr.unload_texture(data.texture_h)
	gfx.destroy_model(&data.model)

	free(data)
}
