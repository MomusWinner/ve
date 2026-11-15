package ve

import hm "container/handle_map"
import "core:c"
import sm "core:container/small_array"
import "core:fmt"
import "core:log"
import vk "vendor:vulkan"

Stage_Infos :: sm.Small_Array(MAX_PIPELINE_STAGE_COUNT, Pipeline_Stage_Info)

Shader_Stage_Flags :: distinct bit_set[Shader_Stage_Flag]
Shader_Stage_Flag :: enum {
	Vertex,
	Geometry,
	Fragment,
	Compute,
}

Shader_Constant_Value :: struct #raw_union {
	bool:  b32,
	int:   i32,
	uint:  u32,
	float: f32,
}

Shader_Constant :: struct {
	id:    u32,
	value: Shader_Constant_Value,
}
Shader_Constants :: sm.Small_Array(MAX_PIPELINE_SHADER_CONTANT_COUNT, Shader_Constant)

Shader_Source :: union {
	string,
	[]byte,
}

Pipeline_Stage_Info :: struct {
	stage:  Shader_Stage_Flag,
	// May be the path to a shader or the shader spv content
	source: Shader_Source,
	consts: Shader_Constants,
}

Front_Face :: enum c.int {
	Counter_Clockwise = 0,
	Clockwise         = 1,
}

Polygon_Mode :: enum c.int {
	Fill  = 0,
	Line  = 1,
	Point = 2,
}

Primitive_Topology :: enum c.int {
	Point_List                    = 0,
	Line_List                     = 1,
	Line_Strip                    = 2,
	Triangle_List                 = 3,
	Triangle_Strip                = 4,
	Triangle_Fan                  = 5,
	Line_List_With_Adjacency      = 6,
	Line_Strip_With_Adjacency     = 7,
	Triangle_List_With_Adjacency  = 8,
	Triangle_Strip_With_Adjacency = 9,
	Patch_List                    = 10,
}

Cull_Mode_Flags :: distinct bit_set[Cull_Mode_Flag;vk.Flags]
Cull_Mode_Flag :: enum vk.Flags {
	Front = 0,
	Back  = 1,
}

Compare_Op :: enum c.int {
	Never            = 0,
	Less             = 1,
	Equal            = 2,
	Less_Or_Equal    = 3,
	Greater          = 4,
	Not_Equal        = 5,
	Greater_Or_Equal = 6,
	Always           = 7,
}

Stencil_Op :: enum c.int {
	// keeps the current value
	Keep                = 0,
	// sets the value to 0
	Zero                = 1,
	// sets the value to reference
	Replace             = 2,
	// increments the current value and clamps to the maximum representable unsigned value
	Increment_And_Clamp = 3,
	// decrements the current value and clamps to 0
	Decrement_And_Clamp = 4,
	// bitwise-inverts the current value
	Invert              = 5,
	// increments the current value and wraps to 0 when the maximum value would have been exceeded.
	Increment_And_Wrap  = 6,
	// decrements the current value and wraps to the maximum possible value when the value would go below 0.
	Decrement_And_Wrap  = 7,
}

Create_Pipeline_Info :: struct {
	descriptor_set_infos:      Pipeline_Set_Layout_Infos,
	bindless:                  bool,
	stage_infos:               Stage_Infos,
	vertex_input_descriptions: Vertex_Input_Descriptions,
	topology:                  Primitive_Topology,
	rasterizer:                struct {
		polygon_mode: Polygon_Mode,
		line_width:   f32,
		cull_mode:    Cull_Mode_Flags,
		front_face:   Front_Face,
	},
	blending_info:             struct {
		attachment_infos: Blending_Infos,
	},
	depth:                     struct {
		enable:             b32,
		write_enable:       b32,
		compare_op:         Compare_Op,
		bounds_test_enable: b32,
		min_bounds:         f32,
		max_bounds:         f32,
		bias:               struct {
			enable:          b32,
			clamp:           f32,
			constant_factor: f32,
			slope_factor:    f32,
		},
	},
	stencil:                   struct {
		enable: b32,
		front:  Stencil_Op_State,
		back:   Stencil_Op_State,
	},
}

Create_Compute_Pipeline_Info :: struct {
	descriptor_set_infos: Pipeline_Set_Layout_Infos,
	bindless:             bool,
	source:               Shader_Source,
	consts:               Shader_Constants,
}

Stencil_Op_State :: struct {
	failOp:      Stencil_Op,
	passOp:      Stencil_Op,
	depthFailOp: Stencil_Op,
	compareOp:   Compare_Op,
	compareMask: u32,
	writeMask:   u32,
	reference:   u32,
}

Blend_Factor :: enum c.int {
	Zero                     = 0,
	One                      = 1,
	Src_Color                = 2,
	One_Minus_Src_Color      = 3,
	Dst_Color                = 4,
	One_Minus_Dst_Color      = 5,
	Src_Alpha                = 6,
	One_Minus_Src_Alpha      = 7,
	Dst_Alpha                = 8,
	One_Minus_Dst_Alpha      = 9,
	Constant_Color           = 10,
	One_Minus_Constant_Color = 11,
	Constant_Alpha           = 12,
	One_Minus_Constant_Alpha = 13,
	Src_Alpha_Saturate       = 14,
	Src1_Color               = 15,
	One_Minus_Src1_Color     = 16,
	Src1_Alpha               = 17,
	One_Minus_Src1_Alpha     = 18,
}

Blend_Op :: enum c.int {
	Add              = 0,
	Subtract         = 1,
	Reverse_Subtract = 2,
	Min              = 3,
	Max              = 4,
}

Blending_Info :: struct {
	src_color_blend_factor: Blend_Factor,
	dst_color_blend_factor: Blend_Factor,
	color_blend_op:         Blend_Op,
	src_alpha_blend_factor: Blend_Factor,
	dst_alpha_blend_factor: Blend_Factor,
	alpha_blend_op:         Blend_Op,
	color_write_mask:       vk.ColorComponentFlags,
}

Blending_Infos :: sm.Small_Array(MAX_COLOR_ATTACHMENTS, Blending_Info)

Handles :: struct {
	h0: Resource_Handle,
	h1: Resource_Handle,
	h2: Resource_Handle,
	h3: Resource_Handle,
	h4: Resource_Handle,
	h5: Resource_Handle,
	h6: Resource_Handle,
	h7: Resource_Handle,
	h8: Resource_Handle,
	h9: Resource_Handle,
}

Vertex_Input_Rate :: enum {
	Vertex,
	Instance,
}

Vertex_Input_Attribute_Description :: struct {
	location: u32,
	format:   Format,
	offset:   u32,
}

Vertex_Input_Attribute_Descriptions :: sm.Small_Array(
	MAX_PIPELINE_VERTEX_INPUT_ATTRIBUTE_COUNT,
	Vertex_Input_Attribute_Description,
)

Vertex_Input_Description :: struct {
	binding:    u32,
	stride:     u32,
	input_rate: Vertex_Input_Rate,
	attributes: Vertex_Input_Attribute_Descriptions,
}
Vertex_Input_Descriptions :: sm.Small_Array(MAX_PIPELINE_BINDING_COUNT, Vertex_Input_Description)

Graphics_Pipeline :: distinct hm.Handle
Compute_Pipeline :: distinct hm.Handle

Pipeline_Layout :: vk.PipelineLayout

shaders_hot_reload :: proc(loc := #caller_location) {
	when !ENABLE_SHADER_COMPILATION {
		log.warn(
			"Shader compilation is not enabled (ENABLE_SHADER_COMPILATION). Now, only *.spv files are reloaded." +
			"Shader hot reloading is only recommended for development!",
			location = loc,
		)
	}
	_pipeline_manager_hot_reload()
}

create_vertex_input_description :: proc() -> Vertex_Input_Description {
	attribute_descriptions := Vertex_Input_Attribute_Descriptions{}
	sm.push_back_elems(
		&attribute_descriptions,
		Vertex_Input_Attribute_Description {
			location = 0,
			format = .RGB_f32,
			offset = cast(u32)offset_of(Vertex, position),
		},
		Vertex_Input_Attribute_Description {
			location = 1,
			format = .RG_f32,
			offset = cast(u32)offset_of(Vertex, tex_coord),
		},
		Vertex_Input_Attribute_Description {
			location = 2,
			format = .RGB_f32,
			offset = cast(u32)offset_of(Vertex, normal),
		},
	)

	return Vertex_Input_Description {
		binding = 0,
		stride = size_of(Vertex),
		input_rate = .Vertex,
		attributes = attribute_descriptions,
	}
}

@(require_results)
create_graphics_pipeline :: proc(
	create_pipeline_info: Create_Pipeline_Info,
	loc := #caller_location,
) -> Graphics_Pipeline {
	return _pipeline_manager_add_graphics_pipeline(
		ctx.gfx.pipeline_manager,
		Graphics_Pipeline_Data{create_info = create_pipeline_info},
	)
}

destroy_graphics_pipeline :: proc(pipeline: Graphics_Pipeline) -> bool {
	return _destroy_graphics_pipeline_h(pipeline)
}


// TODO: need a procedure that returns full information about the graphics/compute pipeline
graphics_pipeline_get_vertex_input :: proc(
	pipeline: Graphics_Pipeline,
	binding: u32,
	loc := #caller_location,
) -> (
	Vertex_Input_Description,
	bool,
) {
	data := _get_graphics_pipeline(pipeline, loc)
	for input in sm.slice(&data.create_info.vertex_input_descriptions) {
		if input.binding == binding do return input, true
	}
	return {}, false
}

@(require_results)
create_compute_pipeline :: proc(create_pipeline_info: Create_Compute_Pipeline_Info) -> Compute_Pipeline {
	pipeline := _create_compute_pipeline(create_pipeline_info, context.allocator)
	handle := _pipeline_manager_registe_compute_pipeline(ctx.gfx.pipeline_manager, pipeline)

	return handle
}

destroy_compute_pipeline :: proc(pipeline: Compute_Pipeline) -> bool {
	return _destroy_compute_pipeline_h(pipeline)
}
