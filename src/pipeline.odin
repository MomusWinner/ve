package main

import "core:log"
import "core:mem/virtual"
import "eldr"
import gfx "eldr/graphics"
import vk "vendor:vulkan"

default_shader_attribute :: proc(
) -> (
	gfx.Vertex_Input_Binding_Description,
	[4]gfx.Vertex_Input_Attribute_Description,
) {
	bind_description := gfx.Vertex_Input_Binding_Description {
		binding   = 0,
		stride    = size_of(gfx.Vertex),
		inputRate = .VERTEX,
	}

	attribute_descriptions := [4]gfx.Vertex_Input_Attribute_Description {
		gfx.Vertex_Input_Attribute_Description {
			binding = 0,
			location = 0,
			format = .R32G32B32_SFLOAT,
			offset = cast(u32)offset_of(gfx.Vertex, position),
		},
		gfx.Vertex_Input_Attribute_Description {
			binding = 0,
			location = 1,
			format = .R32G32_SFLOAT,
			offset = cast(u32)offset_of(gfx.Vertex, tex_coord),
		},
		gfx.Vertex_Input_Attribute_Description {
			binding = 0,
			location = 2,
			format = .R32G32B32_SFLOAT,
			offset = cast(u32)offset_of(gfx.Vertex, normal),
		},
		gfx.Vertex_Input_Attribute_Description {
			binding = 0,
			location = 3,
			format = .R32G32B32A32_SFLOAT,
			offset = cast(u32)offset_of(gfx.Vertex, color),
		},
	}

	return bind_description, attribute_descriptions
}

create_default_pipeline :: proc() -> gfx.Pipeline_Handle {
	vert_bind, vert_attr := default_shader_attribute()

	set_infos := []gfx.Pipeline_Set_Info{gfx.create_bindless_pipeline_set_info(context.temp_allocator)}

	push_constants := []gfx.Push_Constant_Range { 	// const
		{offset = 0, size = size_of(gfx.Push_Constant), stageFlags = vk.ShaderStageFlags_ALL_GRAPHICS},
	}

	create_info := gfx.Create_Pipeline_Info {
		set_infos = set_infos[:],
		push_constants = push_constants,
		vertex_input_description = {
			input_rate = .VERTEX,
			binding_description = vert_bind,
			attribute_descriptions = vert_attr[:],
		},
		stage_infos = []gfx.Pipeline_Stage_Info {
			{stage = {.VERTEX}, shader_path = "assets/buildin/shaders/default.vert"},
			{stage = {.FRAGMENT}, shader_path = "assets/buildin/shaders/default.frag"},
		},
		input_assembly = {topology = .TRIANGLE_LIST},
		rasterizer = {polygon_mode = .FILL, line_width = 1, cull_mode = {.BACK}, front_face = .COUNTER_CLOCKWISE},
		multisampling = {sample_count = ._4, min_sample_shading = 1},
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

	handle, ok := gfx.create_graphics_pipeline(&create_info)
	if !ok {
		log.info("couldn't create default pipeline")
	}

	return handle
}

create_postprocessing_pipeline :: proc() -> gfx.Pipeline_Handle {
	vert_bind, vert_attr := default_shader_attribute()

	set_infos := []gfx.Pipeline_Set_Info{gfx.create_bindless_pipeline_set_info(context.temp_allocator)}

	push_constants := []gfx.Push_Constant_Range { 	// const
		{offset = 0, size = size_of(gfx.Push_Constant), stageFlags = vk.ShaderStageFlags_ALL_GRAPHICS},
	}

	create_info := gfx.Create_Pipeline_Info {
		set_infos = set_infos[:],
		push_constants = push_constants,
		vertex_input_description = {
			input_rate = .VERTEX,
			binding_description = vert_bind,
			attribute_descriptions = vert_attr[:],
		},
		stage_infos = []gfx.Pipeline_Stage_Info {
			{stage = {.VERTEX}, shader_path = "assets/buildin/shaders/postprocessing.vert"},
			{stage = {.FRAGMENT}, shader_path = "assets/buildin/shaders/postprocessing.frag"},
		},
		input_assembly = {topology = .TRIANGLE_LIST},
		rasterizer = {polygon_mode = .FILL, line_width = 1, cull_mode = {.BACK}, front_face = .COUNTER_CLOCKWISE},
		multisampling = {sample_count = ._4, min_sample_shading = 1},
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

	handle, ok := gfx.create_graphics_pipeline(&create_info)
	if !ok {
		log.info("couldn't create default pipeline")
	}

	return handle
}
