package main

import ve ".."
import gfx "../graphics"
import sm "core:container/small_array"
import "core:log"
import "core:mem/virtual"
import vk "vendor:vulkan"

default_shader_attribute :: proc() -> (gfx.Vertex_Input_Binding_Description, gfx.Vertex_Input_Attribute_Descriptions) {
	bind_description := gfx.Vertex_Input_Binding_Description {
		binding   = 0,
		stride    = size_of(gfx.Vertex),
		inputRate = .VERTEX,
	}

	attribute_descriptions := gfx.Vertex_Input_Attribute_Descriptions{}
	sm.push_back_elems(
		&attribute_descriptions,
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
	)

	return bind_description, attribute_descriptions
}

create_default_pipeline :: proc() -> gfx.Render_Pipeline_Handle {
	vert_bind, vert_attr := default_shader_attribute()

	set_infos := gfx.Pipeline_Set_Layout_Infos{}
	sm.push_back(&set_infos, gfx.create_bindless_pipeline_set_info())

	stages := gfx.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		gfx.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/buildin/shaders/default.vert"},
		gfx.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/buildin/shaders/default.frag"},
	)

	create_info := gfx.Create_Pipeline_Info {
		set_infos = set_infos,
		bindless = true,
		vertex_input_description = {
			input_rate = .VERTEX,
			binding_description = vert_bind,
			attribute_descriptions = vert_attr,
		},
		stage_infos = stages,
		input_assembly = {topology = .TRIANGLE_LIST},
		rasterizer = {polygon_mode = .FILL, line_width = 1, cull_mode = {.BACK}, front_face = .COUNTER_CLOCKWISE},
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

	return gfx.create_render_pipeline(create_info)
}

create_postprocessing_pipeline :: proc() -> gfx.Render_Pipeline_Handle {
	vert_bind, vert_attr := default_shader_attribute()

	set_infos := gfx.Pipeline_Set_Layout_Infos{}
	sm.push_back(&set_infos, gfx.create_bindless_pipeline_set_info())

	stages := gfx.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		gfx.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/postprocessing.vert"},
		gfx.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/shaders/postprocessing.frag"},
	)

	create_info := gfx.Create_Pipeline_Info {
		set_infos = set_infos,
		bindless = true,
		vertex_input_description = {
			input_rate = .VERTEX,
			binding_description = vert_bind,
			attribute_descriptions = vert_attr,
		},
		stage_infos = stages,
		input_assembly = {topology = .TRIANGLE_LIST},
		rasterizer = {polygon_mode = .FILL, line_width = 1, cull_mode = {.BACK}, front_face = .COUNTER_CLOCKWISE},
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

	return gfx.create_render_pipeline(create_info)
}

create_depth_pipeline :: proc() -> gfx.Render_Pipeline_Handle {
	vert_bind, vert_attr := default_shader_attribute()

	set_infos := gfx.Pipeline_Set_Layout_Infos{}
	sm.push_back(&set_infos, gfx.create_bindless_pipeline_set_info())

	stages := gfx.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		gfx.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/depth.vert"},
		gfx.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/shaders/depth.frag"},
	)

	create_info := gfx.Create_Pipeline_Info {
		set_infos = set_infos,
		bindless = true,
		vertex_input_description = {
			input_rate = .VERTEX,
			binding_description = vert_bind,
			attribute_descriptions = vert_attr,
		},
		stage_infos = stages,
		input_assembly = {topology = .TRIANGLE_LIST},
		rasterizer = {polygon_mode = .FILL, line_width = 1, cull_mode = {.BACK}, front_face = .COUNTER_CLOCKWISE},
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

	return gfx.create_render_pipeline(create_info)
}

create_light_pipeline :: proc() -> gfx.Render_Pipeline_Handle {
	vert_bind, vert_attr := default_shader_attribute()

	set_infos := gfx.Pipeline_Set_Layout_Infos{}
	sm.push_back(&set_infos, gfx.create_bindless_pipeline_set_info())

	stages := gfx.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		gfx.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/light.vert"},
		gfx.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/shaders/light.frag"},
	)

	create_info := gfx.Create_Pipeline_Info {
		set_infos = set_infos,
		bindless = true,
		vertex_input_description = {
			input_rate = .VERTEX,
			binding_description = vert_bind,
			attribute_descriptions = vert_attr,
		},
		stage_infos = stages,
		input_assembly = {topology = .TRIANGLE_LIST},
		rasterizer = {polygon_mode = .FILL, line_width = 1, cull_mode = {.BACK}, front_face = .COUNTER_CLOCKWISE},
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

	return gfx.create_render_pipeline(create_info)
}

create_depth_only_pipeline :: proc() -> gfx.Render_Pipeline_Handle {
	vert_bind, vert_attr := default_shader_attribute()

	set_infos := gfx.Pipeline_Set_Layout_Infos{}
	sm.push_back(&set_infos, gfx.create_bindless_pipeline_set_info())

	stages := gfx.Stage_Infos{}
	sm.push_back_elems(&stages, gfx.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/light.vert"})

	create_info := gfx.Create_Pipeline_Info {
		set_infos = set_infos,
		bindless = true,
		vertex_input_description = {
			input_rate = .VERTEX,
			binding_description = vert_bind,
			attribute_descriptions = vert_attr,
		},
		stage_infos = stages,
		input_assembly = {topology = .TRIANGLE_LIST},
		rasterizer = {
			depth_bias_enable = true,
			polygon_mode = .FILL,
			line_width = 1,
			cull_mode = {.BACK},
			front_face = .COUNTER_CLOCKWISE,
		},
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

	return gfx.create_render_pipeline(create_info)
}
