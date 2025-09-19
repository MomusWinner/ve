package main

import "core:log"
import "core:mem/virtual"
import "eldr"
import gfx "eldr/graphics"
import vk "vendor:vulkan"

default_shader_attribute :: proc() -> (eldr.VertexInputBindingDescription, [3]eldr.VertexInputAttributeDescription) {
	bind_description := eldr.VertexInputBindingDescription {
		binding   = 0,
		stride    = size_of(eldr.Vertex),
		inputRate = .VERTEX,
	}

	attribute_descriptions := [3]eldr.VertexInputAttributeDescription {
		eldr.VertexInputAttributeDescription {
			binding = 0,
			location = 0,
			format = .R32G32B32_SFLOAT,
			offset = cast(u32)offset_of(eldr.Vertex, position),
		},
		eldr.VertexInputAttributeDescription {
			binding = 0,
			location = 1,
			format = .R32G32_SFLOAT,
			offset = cast(u32)offset_of(eldr.Vertex, tex_coord),
		},
		eldr.VertexInputAttributeDescription {
			binding = 0,
			location = 2,
			format = .R32G32B32_SFLOAT,
			offset = cast(u32)offset_of(eldr.Vertex, normal),
		},
	}

	return bind_description, attribute_descriptions
}

create_default_pipeline :: proc() -> eldr.Pipeline_Handle {
	vert_bind, vert_attr := default_shader_attribute()

	set_infos := []eldr.Pipeline_Set_Info{eldr.create_bindless_pipeline_set_info(context.temp_allocator)}

	push_constants := []gfx.Push_Constant_Range { 	// const
		{offset = 0, size = size_of(gfx.Push_Constant), stageFlags = vk.ShaderStageFlags_ALL_GRAPHICS},
	}

	create_info := eldr.Create_Pipeline_Info {
		set_infos = set_infos[:],
		push_constants = push_constants,
		vertex_input_description = {
			input_rate = .VERTEX,
			binding_description = vert_bind,
			attribute_descriptions = vert_attr[:],
		},
		stage_infos = []eldr.Pipeline_Stage_Info {
			{stage = {.VERTEX}, shader_path = "assets/shaders/default.vert"},
			{stage = {.FRAGMENT}, shader_path = "assets/shaders/default.frag"},
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

	handle, ok := eldr.create_graphics_pipeline(&create_info)
	if !ok {
		log.info("couldn't create default pipeline")
	}

	return handle
}

// set_infos := []eldr.Pipeline_Set_Info {
// 	{
// 		set           = 0,
// 		binding_infos = {
// 			{binding = 0, descriptor_type = .COMBINED_IMAGE_SAMPLER, stage_flags = {.FRAGMENT}},
//
// 			// set:           u32,
// 			// binding_infos: []Pipeline_Set_Binding_Info,
// 			// flags:         []vk.DescriptorBindingFlags,
//
// 			// binding:          u32,
// 			// descriptor_type:  vk.DescriptorType,
// 			// descriptor_count: u32,
// 			// stage_flags:      vk.ShaderStageFlags,
// 		},
// 		flags         = {{.UPDATE_AFTER_BIND, .PARTIALLY_BOUND}},
// 	},
// }

create_postprocessing_pipeline :: proc() -> eldr.Pipeline_Handle {
	vert_bind, vert_attr := default_shader_attribute()

	set_infos := []eldr.Pipeline_Set_Info{eldr.create_bindless_pipeline_set_info(context.temp_allocator)}

	push_constants := []gfx.Push_Constant_Range { 	// const
		{offset = 0, size = size_of(gfx.Push_Constant), stageFlags = vk.ShaderStageFlags_ALL_GRAPHICS},
	}

	create_info := eldr.Create_Pipeline_Info {
		set_infos = set_infos[:],
		push_constants = push_constants,
		vertex_input_description = {
			input_rate = .VERTEX,
			binding_description = vert_bind,
			attribute_descriptions = vert_attr[:],
		},
		stage_infos = []eldr.Pipeline_Stage_Info {
			{stage = {.VERTEX}, shader_path = "assets/shaders/postprocessing.vert"},
			{stage = {.FRAGMENT}, shader_path = "assets/shaders/postprocessing.frag"},
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

	handle, ok := eldr.create_graphics_pipeline(&create_info)
	if !ok {
		log.info("couldn't create default pipeline")
	}

	return handle
}
