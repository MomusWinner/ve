package graphics

import "../common"
import hm "../handle_map"
import sm "core:container/small_array"
import "core:math/linalg/glsl"
import "shaderc"
import "vendor:glfw"
import tt "vendor:stb/truetype"
import vk "vendor:vulkan"
import "vma"

vec2 :: common.vec2
ivec2 :: common.ivec2
vec3 :: common.vec3
ivec3 :: common.ivec3
vec4 :: common.vec4
color :: common.color
ivec4 :: common.ivec4
mat4 :: common.mat4
quat :: common.quat

Vertex :: common.Vertex
Image :: common.Image

Sample_Count_Flags :: vk.SampleCountFlags
Sample_Count_Flag :: vk.SampleCountFlag
Semaphore :: vk.Semaphore
Vertex_Input_Binding_Description :: vk.VertexInputBindingDescription
Vertex_Input_Attribute_Description :: vk.VertexInputAttributeDescription
Push_Constant_Range :: vk.PushConstantRange
Device_Size :: vk.DeviceSize
Command_Buffer :: vk.CommandBuffer
Pipeline_Stage_Flags :: vk.PipelineStageFlags
Descriptor_Set :: vk.DescriptorSet

Buildin_Resource :: struct {
	pipeline:    struct {
		default_h:   Render_Pipeline_Handle,
		primitive_h: Render_Pipeline_Handle,
		text_h:      Render_Pipeline_Handle,
	},
	square:      Model, // TODO: depricated
	unit_square: Mesh,
}

Vulkan_State :: struct {
	enabled_layer_names:      []cstring,
	instance:                 vk.Instance,
	physical_device:          vk.PhysicalDevice,
	physical_device_property: vk.PhysicalDeviceProperties,
	device:                   vk.Device,
	dbg_messenger:            Maybe(vk.DebugUtilsMessengerEXT),
	allocator:                vma.Allocator,
	graphics_queue:           vk.Queue,
	present_queue:            vk.Queue,
	surface:                  vk.SurfaceKHR,
	command_pool:             vk.CommandPool,
	descriptor_pool:          vk.DescriptorPool,
}

Graphics_Limits :: struct {
	max_sample_count:       Sample_Count_Flag,
	max_sampler_anisotropy: f32,
}

Graphics_Init_Info :: struct {
	swapchain_sample_count: Sample_Count_Flag,
}

Graphics :: struct {
	initialized:               bool,
	window:                    ^glfw.WindowHandle,
	vulkan_state:              Vulkan_State,
	limits:                    Graphics_Limits,
	swapchain:                 ^Swap_Chain,
	// managers
	unifiorm_buffer_manager:   ^Uniform_Buffer_Manager,
	material_manager:          ^Material_Manager,
	pipeline_manager:          ^Pipeline_Manager,
	surface_manager:           ^Surface_Manager,
	descriptor_layout_manager: Descriptor_Layout_Manager,
	temp_material_pool:        ^Temp_Material_Pool, // TODO: move to Temps struct
	temp_transform_pool:       ^Temp_Transform_Pool,
	bindless:                  ^Bindless,
	cmd:                       vk.CommandBuffer,
	image_available_semaphore: vk.Semaphore,
	fence:                     vk.Fence,
	swapchain_resized:         bool,
	render_started:            bool,
	deffered_destructor:       ^Deferred_Destructor,
	buildin:                   ^Buildin_Resource,
}

TextureEncoding :: enum {
	Linear,
	sRGB,
}

Texture :: struct {
	name:            string,
	image:           vk.Image,
	view:            vk.ImageView,
	sampler:         vk.Sampler,
	format:          vk.Format,
	allocation:      vma.Allocation,
	allocation_info: vma.AllocationInfo,
}

Buffer :: struct {
	buffer:          vk.Buffer,
	usage:           vk.BufferUsageFlags,
	allocation:      vma.Allocation,
	allocation_info: vma.AllocationInfo,
	mapped:          rawptr,
}

Resource :: union {
	Buffer,
	Texture,
	Buffer_Handle,
	Texture_Handle,
}

Deferred_Destructor :: struct {
	resources:  [DEFERRED_DESTRUCTOR_SIZE]Resource,
	next_index: int,
}

@(private)
Single_Command :: struct {
	cmd: vk.CommandBuffer,
}

// PIPELINE

Vertex_Input_Description :: struct {
	binding_description:    Vertex_Input_Binding_Description,
	attribute_descriptions: []Vertex_Input_Attribute_Description,
}

Pipeline_Set_Binding_Info :: struct {
	binding:          u32,
	descriptor_type:  vk.DescriptorType,
	descriptor_count: u32,
	stage_flags:      vk.ShaderStageFlags,
	flags:            Maybe(vk.DescriptorBindingFlags),
}

Pipeline_Resource :: union {
	Texture,
	Buffer,
}

Shader_Stage_Flags :: distinct bit_set[Shader_Stage_Flag]
Shader_Stage_Flag :: enum {
	Vertex,
	Geometry,
	Fragment,
	Compute,
}

Pipeline_Stage_Info :: struct {
	stage:       Shader_Stage_Flag,
	shader_path: string,
}

Pipeline_Set_Layout_Infos :: sm.Small_Array(MAX_PIPELINE_SET_COUNT, Pipeline_Set_Layout_Info)
Descriptor_Set_Layouts :: sm.Small_Array(MAX_PIPELINE_SET_COUNT, vk.DescriptorSetLayout)
Stage_Infos :: sm.Small_Array(MAX_PIPELINE_STAGE_COUNT, Pipeline_Stage_Info)
Pipeline_Shader_Stage_Create_Infos :: sm.Small_Array(MAX_PIPELINE_STAGE_COUNT, vk.PipelineShaderStageCreateInfo)
Pipeline_Dynamic_States :: sm.Small_Array(MAX_PIPELINE_DYNAMIC_STATE_COUNT, vk.DynamicState)

Vertex_Input_Attribute_Descriptions :: sm.Small_Array(
	MAX_PIPELINE_VERTEX_INPUT_ATTRIBUTE_COUNT,
	Vertex_Input_Attribute_Description,
)
Pipeline_Set_Binding_Infos :: sm.Small_Array(MAX_PIPELINE_BINDING_COUNT, Pipeline_Set_Binding_Info)

Pipeline_Set_Layout_Info :: struct {
	binding_infos: Pipeline_Set_Binding_Infos,
}

Create_Pipeline_Info :: struct {
	set_infos:                Pipeline_Set_Layout_Infos,
	bindless:                 bool,
	stage_infos:              Stage_Infos,
	vertex_input_description: struct {
		input_rate:             vk.VertexInputRate,
		binding_description:    Vertex_Input_Binding_Description,
		attribute_descriptions: Vertex_Input_Attribute_Descriptions,
	},
	input_assembly:           struct {
		topology: vk.PrimitiveTopology,
	},
	rasterizer:               struct {
		polygon_mode:      vk.PolygonMode,
		line_width:        f32,
		cull_mode:         vk.CullModeFlags,
		front_face:        vk.FrontFace,
		depth_bias_enable: b32,
	},
	attachment:               struct {
		sample_count:             Sample_Count_Flags,
		depth_format:             vk.Format,
		color_attachment_formats: u32,
		color_attachment_count:   u32,
	},
	depth:                    struct {
		enable:             b32,
		write_enable:       b32,
		compare_op:         vk.CompareOp,
		bounds_test_enable: b32,
		min_bounds:         f32,
		max_bounds:         f32,
	},
	stencil:                  struct {
		enable: b32,
		front:  vk.StencilOpState,
		back:   vk.StencilOpState,
	},
}

Create_Compute_Pipeline_Info :: struct {
	set_infos:   Pipeline_Set_Layout_Infos,
	shader_path: string,
}

Pipeline :: struct {
	pipeline: vk.Pipeline,
	layout:   Pipeline_Layout_Info,
}

Render_Pipeline :: struct {
	cache:       map[Surface_Info]Graphics_Pipeline,
	create_info: Create_Pipeline_Info,
}

Graphics_Pipeline :: struct {
	using base:   Pipeline,
	surface_info: Surface_Info,
}

Compute_Pipeline :: struct {
	using base:  Pipeline,
	create_info: ^Create_Compute_Pipeline_Info,
}

Push_Constant :: struct {
	model:    mat4,
	camera:   u32,
	material: u32,
	pad0:     u32,
	pad1:     u32,
}

Pipeline_Handle :: distinct hm.Handle
Render_Pipeline_Handle :: distinct hm.Handle

Pipeline_Manager :: struct {
	render_pipelines:   hm.Handle_Map(Render_Pipeline, Render_Pipeline_Handle),
	compute_pipelines:  hm.Handle_Map(Compute_Pipeline, Pipeline_Handle),
	compiler:           shaderc.compilerT,
	compiler_options:   shaderc.compileOptionsT,
	enable_compilation: bool,
}

// SWAP CHAIN

Swap_Chain :: struct {
	swapchain:                  vk.SwapchainKHR,
	color_format:               vk.SurfaceFormatKHR,
	extent:                     vk.Extent2D,
	sample_count:               Sample_Count_Flag,
	msaa_color_texture:         Maybe(Texture),
	depth_image:                Texture,
	image_index:                u32,
	images:                     []vk.Image,
	image_views:                []vk.ImageView,
	frame_buffers:              []vk.Framebuffer,
	render_finished_semaphores: []vk.Semaphore,
}

// FEATURES

Physical_Device_Features :: struct {
	dynamic_rendering_local_read: vk.PhysicalDeviceDynamicRenderingLocalReadFeatures,
	// ^
	// | pNext
	dynamic_rendering:            vk.PhysicalDeviceDynamicRenderingFeatures,
	// ^
	// | pNext
	descriptor_indexing:          vk.PhysicalDeviceDescriptorIndexingFeatures,
	// ^
	// | pNext
	synchronization:              vk.PhysicalDeviceSynchronization2Features,
	// ^
	// | pNext
	features:                     vk.PhysicalDeviceFeatures2,
}

// CAMERA

Camera_UBO :: struct {
	view:       mat4,
	projection: mat4,
	position:   vec3,
}

Camera_Projection_Type :: enum {
	Perspective,
	Orthographic,
	Custom,
}

Camera_Custom_Projection_Proc :: #type proc "c" (user_data: rawptr, camera: ^Camera, aspect: f32) -> mat4

Camera :: struct {
	type:        Camera_Projection_Type,
	position:    vec3,
	zoom:        vec3,
	target:      vec3,
	up:          vec3,
	fov:         f32,
	near:        f32,
	far:         f32,
	dirty:       bool,
	last_aspect: f32,
	custom:      struct {
		projection: Camera_Custom_Projection_Proc,
		user_data:  rawptr,
	},
	_buffer_h:   Buffer_Handle, // Camera_UBO
}

// MODEL

Uniform_Buffer :: struct {
	buffer_h: Buffer_Handle,
	dirty:    bool,
	apply:    proc(data: ^Uniform_Buffer, loc := #caller_location),
	data:     rawptr,
	type:     typeid,
}

Material :: struct {
	pipeline_h: Render_Pipeline_Handle,
	buffer_h:   Buffer_Handle,
	dirty:      bool,
	apply:      proc(data: ^Material, loc := #caller_location),
	data:       rawptr,
	type:       typeid,
}

@(material)
Base_Material :: struct {
	color:   vec4,
	texture: Texture_Handle,
}

Gfx_Transform :: struct {
	using base: common.Transform,
	buffer_h:   Buffer_Handle,
}

Transform_UBO :: struct {
	model: glsl.mat4,
}

Mesh :: struct {
	vbo:      Buffer,
	ebo:      Maybe(Buffer),
	vertices: []Vertex,
	indices:  []u16,
}

Model :: struct {
	meshes:        []Mesh,
	materials:     [dynamic]Material_Handle,
	mesh_material: [dynamic]int,
}

// TEXT

Font :: struct {
	name:                    string,
	size:                    f32,
	texture_h:               Texture_Handle,
	packed_chars:            []tt.packedchar,
	aligned_quads:           []tt.aligned_quad,
	codepoint_to_char_index: map[int]int,
	default_char:            rune,
}

FontVertex :: struct {
	position:   vec3,
	tex_coords: vec2,
}

Text :: struct {
	font:      ^Font,
	text:      string,
	size:      f32,
	vbo:       Buffer,
	last_vbo:  Buffer,
	vertices:  []FontVertex,
	transform: Gfx_Transform,
	material:  Material_Handle,
}

CharacterRegion :: struct {
	start: i32,
	size:  i32,
}

Create_Font_Info :: struct {
	path:         string,
	size:         f32,
	padding:      i32,
	atlas_width:  i32,
	atlas_height: i32,
	regions:      []CharacterRegion,
	default_char: rune,
}

// SURFACE (ELDR SURFACE)

Surface_Handle :: distinct hm.Handle

Surface_Manager :: struct {
	surfaces: hm.Handle_Map(Surface, Surface_Handle),
}

Surface :: struct {
	fit_screen:       bool,
	width, height:    u32,
	transform:        Gfx_Transform,
	color_attachment: Maybe(Surface_Color_Attachment),
	depth_attachment: Maybe(Surface_Depth_Attachment),
	sample_count:     Sample_Count_Flag,
	anisotropy:       f32,
}

Surface_Color_Attachment :: struct {
	info:         vk.RenderingAttachmentInfo,
	msaa_texture: Maybe(Texture),
	texture_h:    Texture_Handle,
}

Surface_Depth_Attachment :: union {
	Surface_Common_Depth_Attachment,
	Surface_Readable_Depth_Attachment,
}

Surface_Common_Depth_Attachment :: struct {
	resource: Texture,
	info:     vk.RenderingAttachmentInfo,
}

Surface_Readable_Depth_Attachment :: struct {
	msaa_texture: Maybe(Texture),
	texture_h:    Texture_Handle,
	info:         vk.RenderingAttachmentInfo,
}

// FRAME

Frame_Status :: enum {
	Success,
	IncorrectSwapchainSize,
}

Surface_Info_Type :: enum {
	None,
	Swapchain,
	Surface,
}

Surface_Info :: struct {
	type:          Surface_Info_Type,
	sample_count:  Sample_Count_Flag,
	depth_format:  vk.Format,
	color_formats: sm.Small_Array(MAX_COLOR_ATTACHMENTS, vk.Format),
	width:         u32,
	height:        u32,
}

Frame_Data :: struct {
	cmd:          vk.CommandBuffer,
	status:       Frame_Status,
	surface_info: Surface_Info,
	camera:       Camera,
}

Render_Frame :: struct {
	state:       bool,
	image_index: u32,
}

Sync_Data :: struct {
	wait_semaphore_infos: []vk.SemaphoreSubmitInfo,
}

// BINDLESS

Texture_Handle :: distinct hm.Handle
Nil_Texture_Handle :: Texture_Handle{max(u32), max(u32)}
Buffer_Handle :: distinct hm.Handle
Nil_Buffer_Handle :: Buffer_Handle{max(u32), max(u32)}

Bindless :: struct {
	set:        vk.DescriptorSet,
	set_layout: vk.DescriptorSetLayout,
	textures:   hm.Handle_Map(Texture, Texture_Handle),
	buffers:    hm.Handle_Map(Buffer, Buffer_Handle),
}

// TEMP RESOURCES

Temp_Material_Pool :: Temp_Pool(Material_Handle)
Temp_Transform_Pool :: Temp_Pool(Gfx_Transform)

Temp_Pool :: struct($T: typeid) {
	resources:          []T,
	next_free_resource: u32,
}
