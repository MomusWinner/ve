package main

import ve ".."
import "base:runtime"
import "core:math"
import "core:math/rand"

INSTANCE_COUNT :: 500_000

Rock_Instance :: struct {
	position: vec3,
	color:    vec3,
	scale:    f32,
}

Instancing_Scene_Data :: struct {
	camera:       ve.Camera,
	cube:         ve.Mesh,
	trf:          ve.Transform,
	pipeline:     ve.Graphics_Pipeline,
	instance_vbo: ve.Buffer,
	rotation:     f32,
}

create_instancing_scene :: proc() -> Scene {
	return Scene {
		init = instancing_scene_init,
		update = instancing_scene_update,
		draw = instancing_scene_draw,
		destroy = instancing_scene_destroy,
	}
}

instancing_scene_init :: proc(s: ^Scene) {
	d := new(Instancing_Scene_Data)

	ve.cursor_set_mode(.Disabled)

	ve.init_camera(&d.camera)
	d.camera.position = {0, 0, 2}

	d.cube = ve.create_primitive_cube()
	d.pipeline = create_instancing_pipeline()

	ve.init_trf(&d.trf)
	ve.trf_set_position(&d.trf, {0, -5, -5})
	ve.trf_set_scale(&d.trf, {0.2, 0.2, 0.2})

	rocks := make([]Rock_Instance, INSTANCE_COUNT, context.temp_allocator)
	for i in 0 ..< INSTANCE_COUNT {
		rho := rand.float32_range(30, 200)
		theta := 2 * math.PI * rand.float32()
		trf: ve.Transform
		ve.init_trf(&trf)
		ve.trf_set_position(&trf, vec3{rho * math.cos_f32(theta), rand.float32_range(-4, 4), rho * math.sin_f32(theta)})
		rocks[i] = Rock_Instance {
			position = trf.position,
			color    = {rand.float32_range(0, 1), rand.float32_range(0, 1), rand.float32_range(0, 1)},
			scale    = rand.float32_range(0.1, 0.3),
		}
	}

	d.instance_vbo = ve.create_buffer({.Vertex}, size_of(Rock_Instance) * INSTANCE_COUNT, raw_data(rocks))

	s.data = d
}

instancing_scene_update :: proc(s: ^Scene) {
	d := cast(^Instancing_Scene_Data)s.data
	d.rotation += ve.time_get_delta() * 0.1
	ve.trf_rotate(&d.trf, {0, 1, 0}, d.rotation)
	ve.camera_update_simple_controller(&d.camera)
}

instancing_scene_draw :: proc(s: ^Scene) {
	d := cast(^Instancing_Scene_Data)s.data

	ve.begin_pass()

	ve.set_camera(d.camera)

	ve.begin_draw()
	{
		ve.cmd_bind_vertex_buffer(d.instance_vbo, 1)
		ve.draw_mesh(d.cube, d.pipeline, ve.trf_get_matrix(d.trf), instance_count = INSTANCE_COUNT)
	}
	ve.end_draw()

	ve.end_pass()
}

instancing_scene_destroy :: proc(s: ^Scene) {
	d := cast(^Instancing_Scene_Data)s.data

	ve.destroy_camera(&d.camera)
	ve.destroy_mesh(&d.cube)
	ve.destroy_graphics_pipeline(d.pipeline)
	ve.destroy_buffer(d.instance_vbo)

	free(d)
}
