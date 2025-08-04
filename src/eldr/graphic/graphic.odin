package graphic

import "base:intrinsics"
import "base:runtime"

import "core:log"
import "core:slice"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

import "../common"

// Enables Vulkan debug logging and validation layers.
ENABLE_VALIDATION_LAYERS :: #config(ENABLE_VALIDATION_LAYERS, ODIN_DEBUG)

DEVICE_EXTENSIONS := []cstring {
	vk.KHR_SWAPCHAIN_EXTENSION_NAME,
	// KHR_PORTABILITY_SUBSET_EXTENSION_NAME,
}

UNIFORM_DESCRIPTOR_MAX :: 30
IMAGE_SAMPLER_DESCRIPTOR_MAX :: 30
STORAGE_DESCRIPTOR_MAX :: 30
DESCRIPTOR_SET_MAX :: 30

vec2 :: common.vec2
vec3 :: common.vec3

Vertex :: common.Vertex
Image :: common.Image

Buffer :: struct {
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
}

UniformBuffer :: struct {
	using parent: Buffer,
	mapped:       rawptr,
}

VertexInputBindingDescription :: vk.VertexInputBindingDescription
VertexInputAttributeDescription :: vk.VertexInputAttributeDescription

VertexInputDescription :: struct {
	binding_description:    VertexInputBindingDescription,
	attribute_descriptions: []VertexInputAttributeDescription,
}

PipelineSetBindingInfo :: struct {
	binding:          u32,
	descriptor_type:  vk.DescriptorType,
	descriptor_count: u32,
	stage_flags:      vk.ShaderStageFlags,
}

PipelineResource :: union {
	Texture,
	UniformBuffer,
	Buffer,
}

PipelineStageInfo :: struct {
	stage:       vk.ShaderStageFlags,
	shader_path: string,
}

PipelineSetInfo :: struct {
	set:           u32,
	binding_infos: []PipelineSetBindingInfo,
}

CreatePipelineInfo :: struct {
	name:                     string,
	set_infos:                []PipelineSetInfo,
	stage_infos:              []PipelineStageInfo,
	vertex_input_description: struct {
		input_rate:             vk.VertexInputRate,
		binding_description:    VertexInputBindingDescription,
		attribute_descriptions: []VertexInputAttributeDescription,
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

Pipeline :: struct {
	pipeline:               vk.Pipeline,
	create_info:            ^CreatePipelineInfo,
	layout:                 vk.PipelineLayout,
	descriptor_set_layouts: []vk.DescriptorSetLayout,
}

PipelineManager :: struct {
	pipeline_by_name: map[string]^Pipeline,
}

Graphic :: struct {
	window:                    glfw.WindowHandle,
	instance_info:             vk.InstanceCreateInfo,
	instance:                  vk.Instance,
	dbg_messenger:             vk.DebugUtilsMessengerEXT, // Null on release
	// Device
	msaa_samples:              vk.SampleCountFlags,
	physical_device:           vk.PhysicalDevice,
	physical_device_property:  vk.PhysicalDeviceProperties,
	device:                    vk.Device,
	// Surface
	surface:                   vk.SurfaceKHR,
	// Queue
	graphics_queue:            vk.Queue,
	present_queue:             vk.Queue,
	// Swap chain 
	swapchain:                 ^SwapChain,
	image_index:               u32,
	render_pass:               vk.RenderPass,
	// Pipeline
	pipeline_manager:          ^PipelineManager,
	descriptor_pool:           vk.DescriptorPool,
	// Command pool
	command_pool:              vk.CommandPool,
	command_buffer:            vk.CommandBuffer,
	// Semaphores
	image_available_semaphore: vk.Semaphore,
	fence:                     vk.Fence,
	// Flags
	framebuffer_resized:       bool,
	render_started:            bool,
}

SwapChain :: struct {
	swapchain:                  vk.SwapchainKHR,
	format:                     vk.SurfaceFormatKHR,
	extent:                     vk.Extent2D,
	depth_image:                TextureImage,
	color_image:                TextureImage,
	images:                     []vk.Image,
	image_views:                []vk.ImageView,
	frame_buffers:              []vk.Framebuffer,
	render_finished_semaphores: []vk.Semaphore,
}

destroy_graphic :: proc(g: ^Graphic) {
	destroy_framebuffers(g)
	destroy_sync_obj(g)
	destroy_command_pool(g)
	_destroy_descriptor_pool(g)
	destroy_render_pass(g)
	destroy_swapchain(g)
	_destroy_pipeline_mananger(g)
	destroy_logical_device(g)
	destroy_surface(g)
	destroy_instance(g)

	free(g)
}

BeginRenderError :: enum {
	None,
	OutOfDate,
	NotEnded,
}

begin_render :: proc(g: ^Graphic) -> BeginRenderError {
	if g.render_started {
		log.error("Call end_render() after begin_render()")
		return .NotEnded
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
		pImageIndex = &g.image_index,
	)

	#partial switch acquire_result {
	case .ERROR_OUT_OF_DATE_KHR:
		recreate_swapchain(g)
		return .OutOfDate

	case .SUCCESS, .SUBOPTIMAL_KHR:
	case:
		log.panicf("vulkan: acquire next image failure: %v", acquire_result)
	}

	must(vk.ResetFences(g.device, 1, &g.fence))
	must(vk.ResetCommandBuffer(g.command_buffer, {}))

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	must(vk.BeginCommandBuffer(g.command_buffer, &begin_info))

	clear_values := [2]vk.ClearValue{}
	clear_values[0].color.float32 = {0.0, 0.0, 0.0, 1.0}
	clear_values[1].depthStencil = {1.0, 0}

	render_pass_info := vk.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = g.render_pass,
		framebuffer = g.swapchain.frame_buffers[g.image_index],
		renderArea = {extent = g.swapchain.extent},
		clearValueCount = len(clear_values),
		pClearValues = raw_data(&clear_values),
	}
	vk.CmdBeginRenderPass(g.command_buffer, &render_pass_info, .INLINE)

	return .None
}

end_render :: proc(g: ^Graphic, wait_semaphores: []vk.Semaphore, wait_stages: []vk.PipelineStageFlags) {
	if !g.render_started {
		log.error("Call begin_render() before end_render()")
	}

	vk.CmdEndRenderPass(g.command_buffer)
	must(vk.EndCommandBuffer(g.command_buffer))

	// wait_semaphores := append(&wait_semaphores, g.image_available_semaphore)
	required_wait_semaphores := concat(wait_semaphores, []vk.Semaphore{g.image_available_semaphore})
	defer delete(required_wait_semaphores)

	required_wait_stages := concat(wait_stages, []vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}})
	defer delete(required_wait_stages)

	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = cast(u32)len(required_wait_semaphores),
		pWaitSemaphores      = raw_data(required_wait_semaphores),
		pWaitDstStageMask    = raw_data(required_wait_stages),
		commandBufferCount   = 1,
		pCommandBuffers      = &g.command_buffer,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &g.swapchain.render_finished_semaphores[g.image_index],
	}
	must(vk.QueueSubmit(g.graphics_queue, 1, &submit_info, g.fence))

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &g.swapchain.render_finished_semaphores[g.image_index],
		swapchainCount     = 1,
		pSwapchains        = &g.swapchain.swapchain,
		pImageIndices      = &g.image_index,
	}
	present_result := vk.QueuePresentKHR(g.present_queue, &present_info)

	switch {
	case present_result == .ERROR_OUT_OF_DATE_KHR || present_result == .SUBOPTIMAL_KHR || g.framebuffer_resized:
		g.framebuffer_resized = false
		recreate_swapchain(g)
	case present_result == .SUCCESS:
	case:
		log.panicf("vulkan: present failure: %v", present_result)
	}

	defer g.render_started = false
}
