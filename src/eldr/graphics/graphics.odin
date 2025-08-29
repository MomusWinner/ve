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
vec3 :: common.vec3
vec4 :: common.vec4
mat4 :: common.mat4

Vertex :: common.Vertex
Image :: common.Image

Texture :: struct {
	name:            string,
	image:           vk.Image,
	view:            vk.ImageView,
	sampler:         vk.Sampler,
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

// Uniform_Buffer :: struct {
// 	using base: Buffer,
// 	mapped:     rawptr,
// }

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
	// Uniform_Buffer,
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
	// uint camera;
	// uint model;
	// uint material;
	// uint pad0;
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

Graphics :: struct {
	window:                    glfw.WindowHandle,
	instance_info:             vk.InstanceCreateInfo,
	instance:                  vk.Instance,
	dbg_messenger:             vk.DebugUtilsMessengerEXT, // Null on release
	allocator:                 vma.Allocator,

	// Device
	msaa_samples:              vk.SampleCountFlags,
	physical_device:           vk.PhysicalDevice,
	physical_device_property:  vk.PhysicalDeviceProperties,
	device:                    vk.Device,
	// Surface
	surface:                   vk.SurfaceKHR,
	// Queue
	graphics_queue:            vk.Queue,
	present_queue:             vk.Queue, // Swap chain 
	swapchain:                 ^Swap_Chain,
	render_pass:               vk.RenderPass,
	// Pipeline
	pipeline_manager:          ^Pipeline_Manager,
	// Descriptors
	descriptor_pool:           vk.DescriptorPool,
	// bindless_params:           ^Bindless_Params,
	bindless:                  ^Bindless,
	// Command pool
	command_pool:              vk.CommandPool,
	cmd:                       vk.CommandBuffer,
	// Sync
	image_available_semaphore: vk.Semaphore,
	fence:                     vk.Fence,
	// Flags
	framebuffer_resized:       bool,
	render_started:            bool,
}

Material :: struct {
	color:      vec4,
	pipeline_h: Pipeline_Handle,
	texture_h:  Texture_Handle,
	buffer_h:   Buffer_Handle,
}

// Camera_UBO :: struct {
// 	view:       glsl.mat4,
// 	projection: glsl.mat4,
// }

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

Begin_Render_Error :: enum {
	None,
	OutOfDate,
	NotEnded,
}

Frame_Data :: struct {
	cmd: vk.CommandBuffer,
}

Render_Frame :: struct {
	state:       bool,
	image_index: u32,
}

get_screen_size :: proc(g: ^Graphics) -> (width: u32, height: u32) {
	width = g.swapchain.extent.width
	height = g.swapchain.extent.height
	return
}

begin_render :: proc(g: ^Graphics) -> (Frame_Data, Begin_Render_Error) {
	if g.render_started {
		log.error("Call end_render() after begin_render()")
		return {}, .NotEnded
	}
	defer g.render_started = true

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
		_recreate_swapchain(g)
		return {}, .OutOfDate

	case .SUCCESS, .SUBOPTIMAL_KHR:
	case:
		log.panicf("acquire next image failure: %v", acquire_result)
	}

	must(vk.ResetFences(g.device, 1, &g.fence))
	must(vk.ResetCommandBuffer(g.cmd, {}))

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	must(vk.BeginCommandBuffer(g.cmd, &begin_info))

	clear_values := [2]vk.ClearValue{}
	clear_values[0].color.float32 = {0.0, 0.0, 0.0, 1.0}
	clear_values[1].depthStencil = {1.0, 0}

	render_pass_info := vk.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = g.render_pass,
		framebuffer = g.swapchain.frame_buffers[g.swapchain.image_index],
		renderArea = {extent = g.swapchain.extent},
		clearValueCount = len(clear_values),
		pClearValues = raw_data(&clear_values),
	}
	vk.CmdBeginRenderPass(g.cmd, &render_pass_info, .INLINE)

	return Frame_Data{cmd = g.cmd}, .None
}

end_render :: proc(g: ^Graphics, wait_semaphores: []Semaphore, wait_stages: []Pipeline_Stage_Flags) {
	if !g.render_started {
		log.error("Call begin_render() before end_render()")
	}
	assert(len(wait_semaphores) == len(wait_stages))

	vk.CmdEndRenderPass(g.cmd)
	must(vk.EndCommandBuffer(g.cmd))

	// wait_semaphores := append(&wait_semaphores, g.image_available_semaphore)
	required_wait_semaphores := concat(wait_semaphores, []vk.Semaphore{g.image_available_semaphore})
	defer delete(required_wait_semaphores)

	required_wait_stages := concat(wait_stages, []Pipeline_Stage_Flags{{.COLOR_ATTACHMENT_OUTPUT}})
	defer delete(required_wait_stages)

	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = cast(u32)len(required_wait_semaphores),
		pWaitSemaphores      = raw_data(required_wait_semaphores),
		pWaitDstStageMask    = raw_data(required_wait_stages),
		commandBufferCount   = 1,
		pCommandBuffers      = &g.cmd,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &g.swapchain.render_finished_semaphores[g.swapchain.image_index],
	}
	must(vk.QueueSubmit(g.graphics_queue, 1, &submit_info, g.fence))

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
	case present_result == .ERROR_OUT_OF_DATE_KHR || present_result == .SUBOPTIMAL_KHR || g.framebuffer_resized:
		g.framebuffer_resized = false
		_recreate_swapchain(g)
	case present_result == .SUCCESS:
	case:
		log.panicf("vulkan: present failure: %v", present_result)
	}

	defer g.render_started = false
}

get_width :: proc(g: ^Graphics) -> u32 {
	return g.swapchain.extent.width
}

get_height :: proc(g: ^Graphics) -> u32 {
	return g.swapchain.extent.height
}

set_full_viewport :: proc(g: ^Graphics, cmd: Command_Buffer) {
	viewport := vk.Viewport {
		width    = cast(f32)get_width(g),
		height   = cast(f32)get_height(g),
		maxDepth = 1.0,
	}
	vk.CmdSetViewport(cmd, 0, 1, &viewport)

	scissor := vk.Rect2D {
		extent = g.swapchain.extent,
	}
	vk.CmdSetScissor(cmd, 0, 1, &scissor)
}
