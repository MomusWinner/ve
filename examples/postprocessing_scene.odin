package main

import ve ".."
import gfx "../graphics"
import "base:runtime"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:time"

@(material)
Postprocessing_Material :: struct {
	texture: gfx.Texture_Handle,
	width:   f32,
	height:  f32,
}

Postprocessing_Scene_Data :: struct {
	model:          gfx.Model,
	model_material: gfx.Material_Handle,
	texture_h:      gfx.Texture_Handle,
	pipeline_h:     gfx.Render_Pipeline_Handle,
	transform:      gfx.Gfx_Transform,
	camera:         gfx.Camera,
	surface_h:      gfx.Surface_Handle,
	postproc_mtrl:  gfx.Material_Handle,
}

create_postprocessing_scene :: proc() -> Scene {
	return Scene {
		init = postprocessing_scene_init,
		update = postprocessing_scene_update,
		draw = postprocessing_scene_draw,
		destroy = postprocessing_scene_destroy,
	}
}

postprocessing_scene_init :: proc(s: ^Scene) {
	data := new(Postprocessing_Scene_Data)

	// Init Camera
	data.camera = gfx.Camera {
		position = {0, 0, 2},
		target   = {0, 0, 0},
		up       = {0, 1, 0},
	}
	gfx.camera_init(&data.camera)

	// Load Model
	data.texture_h = ve.load_texture("./assets/room.png")
	data.model = ve.load_model("./assets/room.obj")
	data.pipeline_h = create_default_pipeline()

	// Setup Material
	data.model_material = gfx.create_mtrl_base(data.pipeline_h)
	model_material, _ := gfx.get_material(data.model_material)
	gfx.mtrl_base_set_texture(model_material, data.texture_h)
	append(&data.model.materials, data.model_material)
	append(&data.model.mesh_material, 0)

	// Setup Transform
	gfx.init_gfx_trf(&data.transform)
	ve.trf_set_position(&data.transform, {0, -0.5, -1})
	ve.trf_rotate(&data.transform, {0, 1, 0}, -3.14 / 2)
	ve.trf_set_scale(&data.transform, 1)

	postprocessing_pipeline_h := create_postprocessing_pipeline()
	pipe, ok_p_ := gfx.get_render_pipeline(postprocessing_pipeline_h)

	// Setup Postprocessing Surface
	data.postproc_mtrl = create_mtrl_postprocessing(postprocessing_pipeline_h)
	postproc_mtrl, _ := gfx.get_material(data.postproc_mtrl)

	data.surface_h = gfx.create_surface_fit_screen(._4)
	surface, ok := gfx.get_surface(data.surface_h)
	assert(ok)
	mtrl_postprocessing_set_texture(postproc_mtrl, gfx.surface_add_color_attachment(surface))
	gfx.surface_add_depth_attachment(surface)

	s.data = data
}

postprocessing_scene_update :: proc(s: ^Scene) {
	data := cast(^Postprocessing_Scene_Data)s.data
}

postprocessing_scene_draw :: proc(s: ^Scene) {
	data := cast(^Postprocessing_Scene_Data)s.data

	pipeline, p_ok := gfx.get_render_pipeline(data.pipeline_h)
	assert(p_ok)

	frame := gfx.begin_render()
	// Begin gfx.
	// --------------------------------------------------------------------------------------------------------------------

	gfx.set_full_viewport_scissor(frame)
	postproc_mtrl, _ := gfx.get_material(data.postproc_mtrl)

	mtrl_postprocessing_set_width(postproc_mtrl, cast(f32)ve.get_screen_width())
	mtrl_postprocessing_set_height(postproc_mtrl, cast(f32)ve.get_screen_height())

	surface, ok := gfx.get_surface(data.surface_h)
	assert(ok)

	surface_frame := gfx.begin_surface(surface, frame)
	{
		gfx.draw_model(surface_frame, data.model, &data.camera, &data.transform)
	}
	gfx.end_surface(surface, surface_frame)

	base_frame := gfx.begin_draw(frame)
	{
		gfx.draw_surface_on_unit_square(surface, &data.camera, base_frame, postproc_mtrl)
	}
	gfx.end_draw(base_frame)

	// --------------------------------------------------------------------------------------------------------------------
	// End gfx.
	gfx.end_render(frame)
}

postprocessing_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Postprocessing_Scene_Data)s.data

	ve.unload_texture(data.texture_h)
	gfx.destroy_model(&data.model)
	gfx.destroy_surface(data.surface_h)

	free(data)
}
