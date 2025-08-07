package graphics

import "base:intrinsics"
import "base:runtime"

import "core:log"
import "core:slice"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

import "../common"
import hm "../handle_map"
import "vma"

VULKAN_API_VERSION :: vk.API_VERSION_1_4

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

Handle :: hm.Handle

vec2 :: common.vec2
vec3 :: common.vec3

Vertex :: common.Vertex
Image :: common.Image

TextureImage :: struct {
	image:  vk.Image,
	view:   vk.ImageView,
	memory: vk.DeviceMemory,
}

Texture :: struct {
	image:   TextureImage,
	sampler: vk.Sampler,
}

Buffer :: struct {
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
}

Uniform_Buffer :: struct {
	using parent: Buffer,
	mapped:       rawptr,
}

Vertex_Input_Binding_Description :: vk.VertexInputBindingDescription
Vertex_Input_Attribute_Description :: vk.VertexInputAttributeDescription

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
	Uniform_Buffer,
	Buffer,
}

Pipeline_Stage_Info :: struct {
	stage:       vk.ShaderStageFlags,
	shader_path: string,
}

Pipeline_Set_Info :: struct {
	set:           u32,
	binding_infos: []Pipeline_Set_Binding_Info,
}

Create_Pipeline_Info :: struct {
	set_infos:                []Pipeline_Set_Info,
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

Pipeline_Manager :: struct {
	pipelines:         hm.Handle_Map(Graphics_Pipeline),
	compute_pipelines: hm.Handle_Map(Compute_Pipeline),
	allocator:         runtime.Allocator,
}

Swap_Chain :: struct {
	swapchain:                  vk.SwapchainKHR,
	format:                     vk.SurfaceFormatKHR,
	extent:                     vk.Extent2D,
	samples:                    vk.SampleCountFlags,
	color_image:                TextureImage,
	depth_image:                TextureImage,
	image_index:                u32,
	images:                     []vk.Image,
	image_views:                []vk.ImageView,
	frame_buffers:              []vk.Framebuffer,
	render_finished_semaphores: []vk.Semaphore,
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
	descriptor_pool:           vk.DescriptorPool,
	// Command pool
	command_pool:              vk.CommandPool,
	draw_cb:                   vk.CommandBuffer,
	// Sync
	image_available_semaphore: vk.Semaphore,
	fence:                     vk.Fence,
	// Flags
	framebuffer_resized:       bool,
	render_started:            bool,
}

BeginRenderError :: enum {
	None,
	OutOfDate,
	NotEnded,
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

begin_render :: proc(g: ^Graphics) -> BeginRenderError {
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
		pImageIndex = &g.swapchain.image_index,
	)

	#partial switch acquire_result {
	case .ERROR_OUT_OF_DATE_KHR:
		_recreate_swapchain(g)
		return .OutOfDate

	case .SUCCESS, .SUBOPTIMAL_KHR:
	case:
		log.panicf("acquire next image failure: %v", acquire_result)
	}

	must(vk.ResetFences(g.device, 1, &g.fence))
	must(vk.ResetCommandBuffer(g.draw_cb, {}))

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	must(vk.BeginCommandBuffer(g.draw_cb, &begin_info))

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
	vk.CmdBeginRenderPass(g.draw_cb, &render_pass_info, .INLINE)

	return .None
}

end_render :: proc(g: ^Graphics, wait_semaphores: []vk.Semaphore, wait_stages: []vk.PipelineStageFlags) {
	if !g.render_started {
		log.error("Call begin_render() before end_render()")
	}
	assert(len(wait_semaphores) == len(wait_stages))

	vk.CmdEndRenderPass(g.draw_cb)
	must(vk.EndCommandBuffer(g.draw_cb))

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
		pCommandBuffers      = &g.draw_cb,
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
