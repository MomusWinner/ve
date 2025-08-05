package graphics

import "base:runtime"

import "core:log"
import "core:slice"
import "core:strings"

import "core:os"
import "vendor:glfw"
import vk "vendor:vulkan"

when ODIN_OS == .Darwin {
	// NOTE: just a bogus import of the system library,
	// needed so we can add a linker flag to point to /usr/local/lib (where vulkan is installed by default)
	// when trying to load vulkan.
	@(require, extra_linker_flags = "-rpath /usr/local/lib")
	foreign import __ "system:System.framework"
}

@(private)
g_logger_ctx: runtime.Context

set_logger :: proc(logger: log.Logger) {
	context.logger = logger
	g_logger_ctx = context
}

init_graphic :: proc(g: ^Graphics, window: glfw.WindowHandle) {
	g.window = window
	g.image_index = 0

	g.pipeline_manager = _create_pipeline_manager()
	_create_instance(g)
	_create_surface(g)
	_pick_physical_device(g)
	_create_logical_device(g)
	g.swapchain = _swapchain_new(g.window, g.physical_device, g.device, g.surface, g.msaa_samples)
	create_render_pass(g)
	_create_descriptor_pool(g)

	create_command_pool(g)
	create_command_buffers(g)
	create_sync_obj(g)

	sc := _begin_single_command(g)
	_swapchain_setup(g.swapchain, g.render_pass, sc.command_buffer)
	_end_single_command(sc)
}

destroy_graphic :: proc(g: ^Graphics) {
	destroy_sync_obj(g)
	destroy_command_pool(g)
	_destroy_descriptor_pool(g)
	destroy_render_pass(g)
	_swapchain_destroy(g.swapchain)
	_destroy_pipeline_mananger(g)
	destroy_logical_device(g)
	_destroy_surface(g)
	_destroy_instance(g)

	free(g)
}


destroy_logical_device :: proc(g: ^Graphics) {
	vk.DestroyDevice(g.device, nil)
}

create_render_pass :: proc(g: ^Graphics) {
	color_attachment := vk.AttachmentDescription {
		format         = g.swapchain.format.format,
		samples        = g.msaa_samples,
		loadOp         = .CLEAR,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .COLOR_ATTACHMENT_OPTIMAL,
	}

	color_attachment_ref := vk.AttachmentReference {
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}

	depth_attachment := vk.AttachmentDescription {
		format         = _find_depth_format(g.physical_device),
		samples        = g.msaa_samples,
		loadOp         = .CLEAR,
		storeOp        = .DONT_CARE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	}

	depth_attachment_ref := vk.AttachmentReference {
		attachment = 1,
		layout     = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	}

	color_attachment_resolve := vk.AttachmentDescription {
		format         = g.swapchain.format.format,
		samples        = {._1},
		loadOp         = .DONT_CARE,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .PRESENT_SRC_KHR,
	}

	color_attachment_resolve_ref := vk.AttachmentReference {
		attachment = 2,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}

	attachments := []vk.AttachmentDescription{color_attachment, depth_attachment, color_attachment_resolve}

	subpass := vk.SubpassDescription {
		pipelineBindPoint       = .GRAPHICS,
		colorAttachmentCount    = 1,
		pColorAttachments       = &color_attachment_ref,
		pDepthStencilAttachment = &depth_attachment_ref,
		pResolveAttachments     = &color_attachment_resolve_ref,
	}

	dependency := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
		srcAccessMask = {},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE, .DEPTH_STENCIL_ATTACHMENT_WRITE},
	}

	render_pass := vk.RenderPassCreateInfo {
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = cast(u32)len(attachments),
		pAttachments    = raw_data(attachments),
		subpassCount    = 1,
		pSubpasses      = &subpass,
		dependencyCount = 1,
		pDependencies   = &dependency,
	}

	must(vk.CreateRenderPass(g.device, &render_pass, nil, &g.render_pass))
}

destroy_render_pass :: proc(g: ^Graphics) {
	vk.DestroyRenderPass(g.device, g.render_pass, nil)
}


create_command_pool :: proc(g: ^Graphics) {
	indices := find_queue_families(g.physical_device, g.surface)
	pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = indices.graphics.?,
	}
	must(vk.CreateCommandPool(g.device, &pool_info, nil, &g.command_pool))
}

destroy_command_pool :: proc(g: ^Graphics) {
	vk.DestroyCommandPool(g.device, g.command_pool, nil)
}

create_command_buffers :: proc(g: ^Graphics) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = g.command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	must(vk.AllocateCommandBuffers(g.device, &alloc_info, &g.command_buffer))
}

create_sync_obj :: proc(g: ^Graphics) {
	// g.image_available_semaphores = make([]vk.Semaphore, length)

	sem_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	must(vk.CreateFence(g.device, &fence_info, nil, &g.fence))
	must(vk.CreateSemaphore(g.device, &sem_info, nil, &g.image_available_semaphore))
	// must(vk.CreateSemaphore(g.device, &sem_info, nil, &g.render_finished_semaphore))
}

destroy_sync_obj :: proc(g: ^Graphics) {
	// for sem in g.image_available_semaphores {vk.DestroySemaphore(g.device, sem, nil)}
	vk.DestroySemaphore(g.device, g.image_available_semaphore, nil)
	// vk.DestroySemaphore(g.device, g.render_finished_semaphore, nil)
	vk.DestroyFence(g.device, g.fence, nil)
}

get_sample_count :: proc(properties: vk.PhysicalDeviceProperties) -> vk.SampleCountFlag {
	counts := properties.limits.framebufferColorSampleCounts
	if ._64 in counts {
		return ._64
	} else if ._32 in counts {
		return ._32
	} else if ._16 in counts {
		return ._16
	} else if ._8 in counts {
		return ._8
	} else if ._4 in counts {
		return ._4
	} else if ._2 in counts {
		return ._2
	}

	return ._1
}

QueueFamilyIndices :: struct {
	graphics: Maybe(u32),
	present:  Maybe(u32),
}

find_queue_families :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> (ids: QueueFamilyIndices) {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, nil)

	families := make([]vk.QueueFamilyProperties, count, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, raw_data(families))

	for family, i in families {
		if .GRAPHICS in family.queueFlags && .COMPUTE in family.queueFlags {
			ids.graphics = cast(u32)i
		}

		supported: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), surface, &supported)
		if supported {
			ids.present = cast(u32)i
		}

		_, has_graphics := ids.graphics.?
		_, has_present := ids.present.?

		if has_graphics && has_present {
			break
		}
	}

	return
}

Swapchain_Support :: struct {
	capabilities: vk.SurfaceCapabilitiesKHR,
	formats:      []vk.SurfaceFormatKHR,
	presentModes: []vk.PresentModeKHR,
}

@(private)
query_swapchain_support :: proc(
	device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	allocator := context.temp_allocator,
) -> (
	support: Swapchain_Support,
	result: vk.Result,
) {
	// NOTE: looks like a wrong binding with the third arg being a multipointer.
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &support.capabilities) or_return

	{
		count: u32
		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &count, nil) or_return

		support.formats = make([]vk.SurfaceFormatKHR, count, allocator)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &count, raw_data(support.formats)) or_return
	}

	{
		count: u32
		vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &count, nil) or_return

		support.presentModes = make([]vk.PresentModeKHR, count, allocator)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &count, raw_data(support.presentModes)) or_return
	}

	return
}

vk_messenger_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = g_logger_ctx

	level: log.Level
	if .ERROR in messageSeverity {
		level = .Error
	} else if .WARNING in messageSeverity {
		level = .Warning
	} else if .INFO in messageSeverity {
		level = .Info
	} else {
		level = .Debug
	}

	log.logf(level, "VULKAN: %s", pCallbackData.pMessage)
	return false
}

@(private)
physical_device_extensions :: proc(
	device: vk.PhysicalDevice,
	allocator := context.temp_allocator,
) -> (
	exts: []vk.ExtensionProperties,
	res: vk.Result,
) {
	count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, nil) or_return

	exts = make([]vk.ExtensionProperties, count, allocator)
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, raw_data(exts)) or_return

	return
}
create_shader_module :: proc {
	create_shader_module_from_file,
	create_shader_module_from_memory,
}

create_shader_module_from_file :: proc(device: vk.Device, path: string) -> (module: vk.ShaderModule, ok: bool) {
	data, success := os.read_entire_file(path)
	if !success {
		log.error("coulnd't load shader module: ", path)
	}
	defer delete(data)

	return create_shader_module_from_memory(device, data), success
}

create_shader_module_from_memory :: proc(device: vk.Device, code: []byte) -> (module: vk.ShaderModule) {
	as_u32 := slice.reinterpret([]u32, code)

	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = raw_data(as_u32),
	}
	must(vk.CreateShaderModule(device, &create_info, nil, &module))
	return
}

byte_arr_str :: proc(arr: ^[$N]byte) -> string {
	return strings.truncate_to_byte(string(arr[:]), 0)
}

must :: proc(result: vk.Result, msg: string = "", loc := #caller_location) {
	if result != .SUCCESS {
		log.panicf("vulkan failure: %s (%v)", msg, result, location = loc)
	}
}
