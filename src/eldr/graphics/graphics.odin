package graphics

import "base:intrinsics"
import "base:runtime"

import "core:log"
import "core:math/linalg/glsl"
import "core:slice"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

import "../common"
import hm "../handle_map"
import "shaderc"
import "vma"

DEBUG :: common.DEBUG
VULKAN_API_VERSION :: vk.API_VERSION_1_4

// Enables Vulkan debug logging and validation layers.
ENABLE_VALIDATION_LAYERS :: #config(ENABLE_VALIDATION_LAYERS, ODIN_DEBUG)

DEVICE_EXTENSIONS := []cstring {
	vk.KHR_SWAPCHAIN_EXTENSION_NAME,
	vk.EXT_DESCRIPTOR_INDEXING_EXTENSION_NAME,
	// KHR_PORTABILITY_SUBSET_EXTENSION_NAME,
}

UNIFORM_DESCRIPTOR_MAX :: 300
UNIFORM_DESCRIPTOR_DYNAMIC_MAX :: 30
IMAGE_SAMPLER_DESCRIPTOR_MAX :: 300
STORAGE_DESCRIPTOR_MAX :: 300
DESCRIPTOR_SET_MAX :: 300

vec2 :: common.vec2
ivec2 :: common.ivec2
vec3 :: common.vec3
ivec3 :: common.ivec3
vec4 :: common.vec4
ivec4 :: common.ivec4
mat4 :: common.mat4

Vertex :: common.Vertex
Image :: common.Image

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

Semaphore :: vk.Semaphore
Vertex_Input_Binding_Description :: vk.VertexInputBindingDescription
Vertex_Input_Attribute_Description :: vk.VertexInputAttributeDescription
Push_Constant_Range :: vk.PushConstantRange
Device_Size :: vk.DeviceSize
Command_Buffer :: vk.CommandBuffer
Pipeline_Stage_Flags :: vk.PipelineStageFlags

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

Surface_Handle :: distinct hm.Handle

Surface_Manager :: struct {
	surfaces: hm.Handle_Map(Surface, Surface_Handle),
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
	pipeline_manager:          ^Pipeline_Manager,
	surface_manager:           ^Surface_Manager,
	descriptor_pool:           vk.DescriptorPool,
	bindless:                  ^Bindless,
	command_pool:              vk.CommandPool,
	cmd:                       vk.CommandBuffer,
	image_available_semaphore: vk.Semaphore,
	fence:                     vk.Fence,
	swapchain_resized:         bool,
	render_started:            bool,
}

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

Material :: struct {
	color:      vec4,
	pipeline_h: Pipeline_Handle,
	texture_h:  Texture_Handle,
	buffer_h:   Buffer_Handle,
}

Model_UBO :: struct {
	model:   glsl.mat4,
	tangens: glsl.mat4,
}

Material_UBO :: struct {
	color:   vec4,
	texture: u32,
	pad0:    u32,
	pad1:    u32,
	pad2:    u32,
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

get_screen_size :: proc(g: ^Graphics) -> (width: u32, height: u32) {
	width = g.swapchain.extent.width
	height = g.swapchain.extent.height
	return
}

get_screen_width :: proc(g: ^Graphics) -> u32 {
	return g.swapchain.extent.width
}

get_screen_height :: proc(g: ^Graphics) -> u32 {
	return g.swapchain.extent.height
}

get_device_width :: proc(g: ^Graphics) -> u32 {
	width, height := glfw.GetFramebufferSize(g.window)
	return cast(u32)width
}

get_device_height :: proc(g: ^Graphics) -> u32 {
	width, height := glfw.GetFramebufferSize(g.window)
	return cast(u32)height
}

screen_resized :: proc(g: ^Graphics) -> bool {
	return g.swapchain_resized
}

begin_render :: proc(g: ^Graphics) -> Frame_Data {
	assert(!g.render_started, "Call end_render() after begin_render()")
	defer g.render_started = true

	frame_data := Frame_Data {
		cmd    = g.cmd,
		status = .Success,
	}

	// Wait for previous frame
	must(vk.WaitForFences(g.device, 1, &g.fence, true, max(u64)))

	images: u32 = cast(u32)len(g.swapchain.images)
	acquire_result := vk.AcquireNextImageKHR(
		device = g.device,
		swapchain = g.swapchain.swapchain,
		timeout = max(u64),
		semaphore = g.image_available_semaphore,
		fence = {},
		pImageIndex = &g.swapchain.image_index,
	)

	#partial switch acquire_result {
	case .ERROR_OUT_OF_DATE_KHR:
		frame_data.status = .IncorrectSwapchainSize
		return {}
	case .SUCCESS, .SUBOPTIMAL_KHR:
	case:
		log.panicf("acquire next image failure: %v", acquire_result)
	}

	must(vk.ResetFences(g.device, 1, &g.fence))
	must(vk.ResetCommandBuffer(frame_data.cmd, {}))

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	must(vk.BeginCommandBuffer(frame_data.cmd, &begin_info))

	return frame_data
}

end_render :: proc(g: ^Graphics, frame_data: Frame_Data, sync_data: Sync_Data) {
	if !g.render_started {
		log.error("Call begin_render() before end_render()")
	}

	frame_data := frame_data

	must(vk.EndCommandBuffer(frame_data.cmd))

	wait_semaphore_infos := concat(
		sync_data.wait_semaphore_infos,
		[]vk.SemaphoreSubmitInfo {
			{
				sType = .SEMAPHORE_SUBMIT_INFO,
				semaphore = g.image_available_semaphore,
				stageMask = {.COLOR_ATTACHMENT_OUTPUT},
				deviceIndex = 0,
			},
		},
		context.temp_allocator,
	)

	comand_buffer_info := vk.CommandBufferSubmitInfo {
		sType         = .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer = frame_data.cmd,
	}

	signal_semaphore_info := vk.SemaphoreSubmitInfo {
		sType     = .SEMAPHORE_SUBMIT_INFO,
		semaphore = g.swapchain.render_finished_semaphores[g.swapchain.image_index],
	}

	submit_info := vk.SubmitInfo2 {
		sType                    = .SUBMIT_INFO_2,
		waitSemaphoreInfoCount   = cast(u32)len(wait_semaphore_infos),
		pWaitSemaphoreInfos      = raw_data(wait_semaphore_infos),
		commandBufferInfoCount   = 1,
		pCommandBufferInfos      = &comand_buffer_info,
		signalSemaphoreInfoCount = 1,
		pSignalSemaphoreInfos    = &signal_semaphore_info,
	}
	must(vk.QueueSubmit2(g.graphics_queue, 1, &submit_info, g.fence))

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &g.swapchain.render_finished_semaphores[g.swapchain.image_index],
		swapchainCount     = 1,
		pSwapchains        = &g.swapchain.swapchain,
		pImageIndices      = &g.swapchain.image_index,
	}
	present_result := vk.QueuePresentKHR(g.present_queue, &present_info)

	switch {
	case present_result == .ERROR_OUT_OF_DATE_KHR || present_result == .SUBOPTIMAL_KHR:
		frame_data.status = .IncorrectSwapchainSize
	case present_result == .SUCCESS:
	case:
		log.panicf("vulkan: present failure: %v", present_result)
	}

	if g.swapchain_resized {
		g.swapchain_resized = false
	}

	if frame_data.status == .IncorrectSwapchainSize {
		g.swapchain_resized = true
		on_screen_resized(g)
	}

	defer g.render_started = false
}

begin_draw :: proc(g: ^Graphics, frame: Frame_Data) {
	clear_color := vk.ClearValue {
		color = {float32 = {0.0, 0.0, 0.0, 1.0}},
	}

	_transition_image_layout_from_cmd(
		frame.cmd,
		g.swapchain.images[g.swapchain.image_index],
		{.COLOR},
		g.swapchain.format.format,
		.UNDEFINED,
		.COLOR_ATTACHMENT_OPTIMAL,
		1,
	)

	color_attachment_info := vk.RenderingAttachmentInfo {
		sType              = .RENDERING_ATTACHMENT_INFO,
		pNext              = nil,
		imageView          = g.swapchain.color_image.view,
		imageLayout        = .ATTACHMENT_OPTIMAL,
		resolveMode        = {.AVERAGE_KHR},
		resolveImageView   = g.swapchain.image_views[g.swapchain.image_index],
		resolveImageLayout = .GENERAL,
		loadOp             = .CLEAR,
		storeOp            = .STORE,
		clearValue         = clear_color,
	}

	depth_stencil_clear_value := vk.ClearValue {
		depthStencil = {1, 0},
	}

	depth_stencil_attachment_info := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		pNext       = nil,
		imageView   = g.swapchain.depth_image.view,
		imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .DONT_CARE,
		clearValue  = depth_stencil_clear_value,
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = g.swapchain.extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment_info,
		pDepthAttachment = &depth_stencil_attachment_info,
	}

	vk.CmdBeginRendering(frame.cmd, &rendering_info)
}

end_draw :: proc(g: ^Graphics, frame: Frame_Data) {
	vk.CmdEndRendering(frame.cmd)

	_transition_image_layout_from_cmd(
		frame.cmd,
		g.swapchain.images[g.swapchain.image_index],
		{.COLOR},
		g.swapchain.format.format,
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR,
		1,
	)
}

cmd_set_full_viewport :: proc(g: ^Graphics, cmd: Command_Buffer) {
	viewport := vk.Viewport {
		width    = cast(f32)get_screen_width(g),
		height   = cast(f32)get_screen_height(g),
		maxDepth = 1.0,
	}
	vk.CmdSetViewport(cmd, 0, 1, &viewport)

	scissor := vk.Rect2D {
		extent = g.swapchain.extent,
	}
	vk.CmdSetScissor(cmd, 0, 1, &scissor)
}

on_screen_resized :: proc(g: ^Graphics) {
	_recreate_swapchain(g)
	_surface_manager_recreate_surfaces(g.surface_manager, g)
}
