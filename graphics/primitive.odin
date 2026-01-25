package graphics

import "../common"
import sm "core:container/small_array"
import "core:log"
import vk "vendor:vulkan"

create_primitive_pipeline :: proc() -> Render_Pipeline_Handle {
	vert_bind, vert_attr := default_shader_attribute()

	set_infos := Pipeline_Set_Layout_Infos{}
	sm.push_back(&set_infos, create_bindless_pipeline_set_info())

	stages := Stage_Infos{}
	sm.push_back_elems(
		&stages,
		Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/buildin/shaders/shape.vert"},
		Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/buildin/shaders/shape.frag"},
	)


	create_info := Create_Pipeline_Info {
		set_infos = set_infos,
		bindless = true,
		vertex_input_description = {
			input_rate = .VERTEX,
			binding_description = vert_bind,
			attribute_descriptions = vert_attr,
		},
		stage_infos = stages,
		input_assembly = {topology = .TRIANGLE_LIST},
		rasterizer = {polygon_mode = .FILL, line_width = 1, cull_mode = {}, front_face = .COUNTER_CLOCKWISE},
		depth = {
			enable = true,
			write_enable = true,
			compare_op = .LESS,
			bounds_test_enable = false,
			min_bounds = 0,
			max_bounds = 0,
		},
		stencil = {enable = true, front = {}, back = {}},
	}

	return create_render_pipeline(create_info)
}

create_square_mesh :: proc(size: f32, allocator := context.allocator) -> Mesh {
	vertices := make([]Vertex, 6, context.allocator)
	vertices[0] = {{size, size, 0.0}, {size, size}, {0.0, 0.0, -1.0}, {1.0, 1.0, 1.0, 1.0}}
	vertices[1] = {{size, -size, 0.0}, {size, 0.0}, {0.0, 0.0, -1.0}, {1.0, 1.0, 1.0, 1.0}}
	vertices[2] = {{-size, -size, 0.0}, {0.0, 0.0}, {0.0, 0.0, -1.0}, {1.0, 1.0, 1.0, 1.0}}

	vertices[3] = {{size, size, 0.0}, {size, size}, {0.0, 0.0, -1.0}, {1.0, 1.0, 1.0, 1.0}}
	vertices[4] = {{-size, -size, 0}, {0.0, 0.0}, {0.0, 0.0, -1.0}, {1.0, 1.0, 1.0, 1.0}}
	vertices[5] = {{-size, size, 0.0}, {0.0, size}, {0.0, 0.0, -1.0}, {1.0, 1.0, 1.0, 1.0}}

	return create_mesh(vertices, {})
}

create_square_model :: proc() -> Model {
	mesh := create_square_mesh(0.3)
	meshes := make([]Mesh, 1)
	meshes[0] = mesh

	materials := make([dynamic]Material_Handle, 1, context.allocator)
	mesh_material := make([dynamic]int, 1, context.allocator)
	mesh_material[0] = 0

	model := create_model(meshes, materials, mesh_material)

	return model
}

draw_square :: proc(frame_data: Frame_Data, camera: ^Camera, position: vec3, scale: vec3, color: vec4) {
	model := ctx.buildin.square

	material_h := _temp_pool_acquire_material()
	model.materials[0] = material_h
	material, ok := get_material(material_h)
	assert(ok)
	mtrl_set_pipeline(material, ctx.buildin.pipeline.primitive_h)
	mtrl_base_set_color(material, color)

	transform := _temp_pool_acquire_transform()
	common.trf_set_position(&transform, position)
	common.trf_set_scale(&transform, scale)
	_trf_apply(&transform)

	draw_model(frame_data, model, camera, &transform)
}

draw_square_texture :: proc(
	frame_data: Frame_Data,
	camera: ^Camera,
	position: vec3,
	scale: vec3,
	texture: Texture_Handle,
) {
	model := ctx.buildin.square

	material_h := _temp_pool_acquire_material()
	model.materials[0] = material_h
	material, ok := get_material(material_h)
	assert(ok)
	mtrl_set_pipeline(material, ctx.buildin.pipeline.primitive_h)
	mtrl_base_set_texture(material, texture)

	transform := _temp_pool_acquire_transform()
	common.trf_set_position(&transform, position)
	common.trf_set_scale(&transform, scale)
	_trf_apply(&transform)

	draw_model(frame_data, model, camera, &transform)
}
