package graphics

import "../common"
import hm "../handle_map"
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

Sample_Count_Flag :: vk.SampleCountFlag
Semaphore :: vk.Semaphore
Vertex_Input_Binding_Description :: vk.VertexInputBindingDescription
Vertex_Input_Attribute_Description :: vk.VertexInputAttributeDescription
Push_Constant_Range :: vk.PushConstantRange
Device_Size :: vk.DeviceSize
Command_Buffer :: vk.CommandBuffer
Pipeline_Stage_Flags :: vk.PipelineStageFlags

Buildin_Resource :: struct {
	default_pipeline_h:   Pipeline_Handle,
	primitive_pipeline_h: Pipeline_Handle,
	text_pipeline_h:      Pipeline_Handle,
	square:               Model,
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
	pipeline_manager:          ^Pipeline_Manager,
	surface_manager:           ^Surface_Manager,
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
}

Pipeline_Resource :: union {
	Texture,
	Buffer,
}

Pipeline_Stage_Info :: struct {
	stage:       vk.ShaderStageFlags,
	shader_path: string,
}

Pipeline_Set_Info :: struct {
	set:           u32,
	binding_infos: []Pipeline_Set_Binding_Info,
	flags:         []vk.DescriptorBindingFlags,
}

Create_Pipeline_Info :: struct {
	set_infos:                []Pipeline_Set_Info,
	push_constants:           []Push_Constant_Range,
	stage_infos:              []Pipeline_Stage_Info,
	vertex_input_description: struct {
		input_rate:             vk.VertexInputRate,
		binding_description:    Vertex_Input_Binding_Description,
		attribute_descriptions: []Vertex_Input_Attribute_Description,
	},
	input_assembly:           struct {
		topology: vk.PrimitiveTopology,
	},
	rasterizer:               struct {
		polygon_mode: vk.PolygonMode,
		line_width:   f32,
		cull_mode:    vk.CullModeFlags,
		front_face:   vk.FrontFace,
	},
	multisampling:            struct {
		sample_count:       Sample_Count_Flag,
		min_sample_shading: f32,
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
	set_infos:   []Pipeline_Set_Info,
	shader_path: string,
}

Pipeline :: struct {
	pipeline:               vk.Pipeline,
	layout:                 vk.PipelineLayout,
	descriptor_set_layouts: []vk.DescriptorSetLayout,
}

Graphics_Pipeline :: struct {
	using base:  Pipeline,
	create_info: ^Create_Pipeline_Info,
}

Compute_Pipeline :: struct {
	using base:  Pipeline,
	create_info: ^Create_Compute_Pipeline_Info,
}

Pipeline_Ptr :: union {
	^Graphics_Pipeline,
	^Compute_Pipeline,
}

Push_Constant :: struct {
	camera:   u32,
	model:    u32,
	material: u32,
	pad0:     u32,
}

Pipeline_Handle :: distinct hm.Handle

Pipeline_Manager :: struct {
	pipelines:          hm.Handle_Map(Graphics_Pipeline, Pipeline_Handle),
	compute_pipelines:  hm.Handle_Map(Compute_Pipeline, Pipeline_Handle),
	compiler:           shaderc.compilerT,
	compiler_options:   shaderc.compileOptionsT,
	enable_compilation: bool,
}

// SWAP CHAIN

Swap_Chain :: struct {
	swapchain:                  vk.SwapchainKHR,
	format:                     vk.SurfaceFormatKHR,
	extent:                     vk.Extent2D,
	sample_count:               Sample_Count_Flag,
	color_image:                Texture,
	depth_image:                Texture,
	image_index:                u32,
	images:                     []vk.Image,
	image_views:                []vk.ImageView,
	frame_buffers:              []vk.Framebuffer,
	render_finished_semaphores: []vk.Semaphore,
}

// FEATURES

Physical_Device_Features :: struct {
	dynamic_rendering:   vk.PhysicalDeviceDynamicRenderingFeatures,
	// ^
	// | pNext
	descriptor_indexing: vk.PhysicalDeviceDescriptorIndexingFeatures,
	// ^
	// | pNext
	synchronization:     vk.PhysicalDeviceSynchronization2Features,
	// ^
	// | pNext
	features:            vk.PhysicalDeviceFeatures2,
}

// CAMERA

Camera_UBO :: struct {
	view:       mat4,
	projection: mat4,
}

Camera :: struct {
	position:    vec3,
	zoom:        vec3,
	target:      vec3,
	up:          vec3,
	fov:         f32,
	near:        f32,
	far:         f32,
	dirty:       bool,
	last_aspect: f32,
	_buffer_h:   Buffer_Handle, // Camera_UBO
}

// MODEL


Material :: struct {
	pipeline_h: Pipeline_Handle,
	buffer_h:   Buffer_Handle,
	dirty:      bool,
	apply:      proc(data: ^Material, loc := #caller_location),
	data:       rawptr,
	type:       typeid,
}

@(material)
Base_Material :: struct {
	color:     vec4,
	texture_h: Texture_Handle,
}

Base_Material_UBO :: struct {
	color:   vec4,
	texture: u32,
	pad0:    u32,
	pad1:    u32,
	pad2:    u32,
}

Some_Material :: struct {
	color:   vec4,
	texture: u32,
	test:    u32,
	test2:   u32,
	test3:   u32,
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
	materials:     [dynamic]Material,
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
	material:  Material,
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
	mesh:             Mesh,
	transform:        Gfx_Transform,
	color_attachment: Maybe(Surface_Color_Attachment),
	depth_attachment: Maybe(Surface_Depth_Attachment),
	extent:           vk.Extent2D,
	sample_count:     Sample_Count_Flag,
	anisotropy:       f32,
}

Surface_Depth_Attachment :: struct {
	resource: Texture,
	info:     vk.RenderingAttachmentInfo,
}

Surface_Color_Attachment :: struct {
	info:           vk.RenderingAttachmentInfo,
	resource:       Texture,
	resolve_handle: Texture_Handle,
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
	type:         Surface_Info_Type,
	sample_count: Sample_Count_Flag,
}

Frame_Data :: struct {
	cmd:          vk.CommandBuffer,
	status:       Frame_Status,
	surface_info: Surface_Info,
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
Nil_Buffer_Handle :: Texture_Handle{max(u32), max(u32)}

Bindless :: struct {
	set:        vk.DescriptorSet,
	set_layout: vk.DescriptorSetLayout,
	textures:   hm.Handle_Map(Texture, Texture_Handle),
	buffers:    hm.Handle_Map(Buffer, Buffer_Handle),
}

// TEMP RESOURCES

Temp_Material_Pool :: Temp_Pool(Material)
Temp_Transform_Pool :: Temp_Pool(Gfx_Transform)

Temp_Pool :: struct($T: typeid) {
	resources:          []T,
	next_free_resource: u32,
}
