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

Vertex :: common.Vertex
Image :: common.Image

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

Graphics :: struct {
	window:                    glfw.WindowHandle,
	instance_info:             vk.InstanceCreateInfo,
	instance:                  vk.Instance,
	dbg_messenger:             vk.DebugUtilsMessengerEXT, // TODO: Maybe()
	allocator:                 vma.Allocator,
	// 
	msaa_samples:              vk.SampleCountFlags,
	physical_device:           vk.PhysicalDevice,
	physical_device_property:  vk.PhysicalDeviceProperties,
	device:                    vk.Device,
	surface:                   vk.SurfaceKHR,
	graphics_queue:            vk.Queue,
	present_queue:             vk.Queue,
	swapchain:                 ^Swap_Chain,
	// managers
	pipeline_manager:          ^Pipeline_Manager,
	surface_manager:           ^Surface_Manager,
	temp_material_pool:        ^Temp_Material_Pool,
	temp_transform_pool:       ^Temp_Transform_Pool,
	descriptor_pool:           vk.DescriptorPool,
	bindless:                  ^Bindless,
	command_pool:              vk.CommandPool,
	cmd:                       vk.CommandBuffer,
	image_available_semaphore: vk.Semaphore,
	fence:                     vk.Fence,
	swapchain_resized:         bool,
	render_started:            bool,
	deffered_destructor:       ^Deferred_Destructor,
	buildin:                   ^Buildin_Resource,
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
	render_pass:              Maybe(vk.RenderPass),
	vertex_input_description: struct {
		input_rate:             vk.VertexInputRate,
		binding_description:    Vertex_Input_Binding_Description,
		attribute_descriptions: []Vertex_Input_Attribute_Description,
	},
	input_assembly:           struct {
		topology: vk.PrimitiveTopology,
	},
	rasterizer:               struct {
		polygonMode: vk.PolygonMode,
		lineWidth:   f32,
		cullMode:    vk.CullModeFlags,
		frontFace:   vk.FrontFace,
	},
	multisampling:            struct {
		rasterizationSamples: vk.SampleCountFlags,
		minSampleShading:     f32,
	},
	depth_stencil:            struct {
		depthTestEnable:       b32,
		depthWriteEnable:      b32,
		depthCompareOp:        vk.CompareOp,
		depthBoundsTestEnable: b32,
		stencilTestEnable:     b32,
		front:                 vk.StencilOpState,
		back:                  vk.StencilOpState,
		minDepthBounds:        f32,
		maxDepthBounds:        f32,
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
	samples:                    vk.SampleCountFlags,
	color_image:                Texture,
	depth_image:                Texture,
	image_index:                u32,
	images:                     []vk.Image,
	image_views:                []vk.ImageView,
	frame_buffers:              []vk.Framebuffer,
	render_finished_semaphores: []vk.Semaphore,
	_allocator:                 vma.Allocator,
	_device:                    vk.Device,
	_physical_device:           vk.PhysicalDevice,
	_surface:                   vk.SurfaceKHR,
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

Camera_Extension :: struct {
	data:                       Camera_Extension_Data,
	get_view_matrix_multiplier: proc(data: Camera_Extension_Data) -> mat4,
	test:                       f32,
}

Camera :: struct {
	view:       mat4,
	projection: mat4,
	position:   vec3,
	aspect:     f32,
	zoom:       vec3,
	target:     vec3,
	up:         vec3,
	fov:        f32,
	near:       f32,
	far:        f32,
	buffer_h:   Buffer_Handle,
	dirty:      bool,
	extension:  Maybe(Camera_Extension),
}

Camera_Extension_Data :: union {
	Resoulution_Independed_Ext,
}

Empty_Camera_Ext :: struct {
}

// MODEL

Material :: struct {
	color:      vec4,
	pipeline_h: Pipeline_Handle,
	texture_h:  Maybe(Texture_Handle),
	buffer_h:   Buffer_Handle,
	dirty:      bool,
}

Material_UBO :: struct {
	color:   vec4,
	texture: u32,
	pad0:    u32,
	pad1:    u32,
	pad2:    u32,
}

Transform :: struct {
	buffer_h: Buffer_Handle,
	model:    mat4,
	position: vec3,
	rotation: vec3,
	scale:    vec3,
	dirty:    bool,
}

Transform_UBO :: struct {
	model:   glsl.mat4,
	tangens: glsl.mat4,
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
	texture:                 Texture,
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
	transform: Transform,
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
	model:            Model,
	color_attachment: Maybe(Surface_Color_Attachment),
	depth_attachment: Maybe(Surface_Attachment),
	extent:           vk.Extent2D,
}

Surface_Attachment :: struct {
	resource: Texture,
	handle:   Texture_Handle,
	info:     vk.RenderingAttachmentInfo,
}

Surface_Color_Attachment :: struct {
	using base:       Surface_Attachment,
	resolve_resource: Texture,
	resolve_handle:   Texture_Handle,
}

// FAME

Frame_Status :: enum {
	Success,
	IncorrectSwapchainSize,
}

Frame_Data :: struct {
	cmd:    vk.CommandBuffer,
	status: Frame_Status,
}

Render_Frame :: struct {
	state:       bool,
	image_index: u32,
}

Sync_Data :: struct {
	wait_semaphore_infos: []vk.SemaphoreSubmitInfo,
}

// TEMP RESOURCES

Temp_Material_Pool :: Temp_Pool(Material)
Temp_Transform_Pool :: Temp_Pool(Transform)

Temp_Pool :: struct($T: typeid) {
	resources:          []T,
	next_free_resource: u32,
}
