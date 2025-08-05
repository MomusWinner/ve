package main

import "eldr"
import gfx "eldr/graphics"

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

create_default_pipeline :: proc(e: ^eldr.Eldr) {
	vert_bind, vert_attr := default_shader_attribute()

	bindings := make([]gfx.Pipeline_Set_Binding_Info, 2)
	bindings[0] = gfx.Pipeline_Set_Binding_Info {
		binding          = 0,
		descriptor_type  = .UNIFORM_BUFFER,
		descriptor_count = 1,
		stage_flags      = {.VERTEX},
	}
	bindings[1] = gfx.Pipeline_Set_Binding_Info {
		binding          = 1,
		descriptor_type  = .COMBINED_IMAGE_SAMPLER,
		descriptor_count = 1,
		stage_flags      = {.FRAGMENT},
	}

	set_infos := []gfx.Pipeline_Set_Info{gfx.Pipeline_Set_Info{set = 0, binding_infos = bindings}}

	create_info := gfx.Create_Pipeline_Info {
		name = "default_pipeline",
		set_infos = set_infos,
		vertex_input_description = {
			input_rate = .VERTEX,
			binding_description = vert_bind,
			attribute_descriptions = vert_attr[:],
		},
		stage_infos = []gfx.Pipeline_Stage_Info {
			gfx.Pipeline_Stage_Info{stage = {.VERTEX}, shader_path = "assets/vert.spv"},
			gfx.Pipeline_Stage_Info{stage = {.FRAGMENT}, shader_path = "assets/frag.spv"},
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

	gfx.create_pipeline(e.g, &create_info)
}
