package graphics

import "core:log"
import vk "vendor:vulkan"

create_primitive_pipeline :: proc(g: ^Graphics) -> Pipeline_Handle {
	vert_bind, vert_attr := default_shader_attribute()

	set_infos := []Pipeline_Set_Info{create_bindless_pipeline_set_info(context.temp_allocator)}

	push_constants := []Push_Constant_Range { 	// const
		{offset = 0, size = size_of(Push_Constant), stageFlags = vk.ShaderStageFlags_ALL_GRAPHICS},
	}

	create_info := Create_Pipeline_Info {
		set_infos = set_infos[:],
		push_constants = push_constants,
		vertex_input_description = {
			input_rate = .VERTEX,
			binding_description = vert_bind,
			attribute_descriptions = vert_attr[:],
		},
		stage_infos = []Pipeline_Stage_Info {
			{stage = {.VERTEX}, shader_path = "assets/shaders/shape.vert"},
			{stage = {.FRAGMENT}, shader_path = "assets/shaders/shape.frag"},
		},
		input_assembly = {topology = .TRIANGLE_LIST},
		rasterizer = {polygonMode = .FILL, lineWidth = 1, cullMode = {}, frontFace = .CLOCKWISE},
		multisampling = {rasterizationSamples = {._1}, minSampleShading = 1},
		depth_stencil = {
			depthTestEnable = true,
			depthWriteEnable = true,
			depthCompareOp = .LESS,
			depthBoundsTestEnable = false,
			minDepthBounds = 0,
			maxDepthBounds = 0,
			stencilTestEnable = false,
			front = {},
			back = {},
		},
	}

	handle, ok := create_graphics_pipeline(g, &create_info)
	if !ok {
		log.info("couldn't create default pipeline")
	}

	return handle
}

create_square :: proc(g: ^Graphics) -> Model {
	SIZE :: 0.3
	vertices := make([]Vertex, 6, context.allocator) // TODO: move to manager
	vertices[0] = {{SIZE, SIZE, 0.0}, {SIZE, SIZE}, {0.0, 0.0, SIZE}, {1.0, 1.0, 1.0, 1.0}}
	vertices[1] = {{SIZE, -SIZE, 0.0}, {SIZE, 0.0}, {0.0, SIZE, 0.0}, {1.0, 1.0, 1.0, 1.0}}
	vertices[2] = {{-SIZE, -SIZE, 0.0}, {0.0, 0.0}, {SIZE, 0.0, 0.0}, {1.0, 1.0, 1.0, 1.0}}

	vertices[3] = {{SIZE, SIZE, 0.0}, {SIZE, SIZE}, {0.0, 0.0, SIZE}, {1.0, 1.0, 1.0, 1.0}}
	vertices[4] = {{-SIZE, SIZE, 0.0}, {0.0, SIZE}, {SIZE, SIZE, SIZE}, {1.0, 1.0, 1.0, 1.0}}
	vertices[5] = {{-SIZE, -SIZE, 0}, {0.0, 0.0}, {0.0, SIZE, 0.0}, {1.0, 1.0, 1.0, 1.0}}

	mesh := create_mesh(g, vertices, {})
	meshes := make([]Mesh, 1)
	meshes[0] = mesh

	materials := make([dynamic]Material, 1, context.allocator)
	mesh_material := make([dynamic]int, 1, context.allocator)
	mesh_material[0] = 0

	model := create_model(meshes, materials, mesh_material)

	return model
}

draw_square :: proc(g: ^Graphics, frame: Frame_Data, camera: Camera, position: vec3, scale: vec3, color: vec4) {
	model := g.buildin.square

	material := _temp_pool_acquire(g.temp_material_pool)
	model.materials[0] = material
	model.materials[0].pipeline_h = g.buildin.primitive_pipeline_h
	model.materials[0].color = color
	_material_apply(&model.materials[0], g)

	transform := _temp_pool_acquire(g.temp_transform_pool)
	transform_set_position(&transform, position)
	transform_set_scale(&transform, scale)
	_transform_apply(&transform, g)

	draw_model(g, model, camera, &transform, frame.cmd)
}
