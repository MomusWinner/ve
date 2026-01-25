package graphics

import "base:runtime"

import "core:log"
import "core:slice"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"
import "vma"

@(private)
_init_swapchain :: proc(sample_count: Sample_Count_Flag) {
	ctx.swapchain = _swapchain_new(sample_count)
	sc := begin_single_cmd()
	_swapchain_setup(ctx.swapchain, sc.cmd)
	end_single_cmd(sc)
}

@(private)
_destroy_swapchain :: proc() {
	_swapchain_destroy(ctx.swapchain)
}

@(private)
_recreate_swapchain :: proc() {
	_swapchain_recreate(ctx.swapchain)
}

@(private)
_swapchaint_get_color_attachment_info :: proc(clear_color: vec4) -> vk.RenderingAttachmentInfo {
	vk_clear_color := vk.ClearValue {
		color = {float32 = clear_color},
	}

	color_attachment_info := vk.RenderingAttachmentInfo {
		sType              = .RENDERING_ATTACHMENT_INFO,
		pNext              = nil,
		imageLayout        = .ATTACHMENT_OPTIMAL,
		resolveImageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp             = .CLEAR,
		storeOp            = .STORE,
		clearValue         = vk_clear_color,
	}

	msaa_color_texture, has_msaa_color := ctx.swapchain.msaa_color_texture.?

	if has_msaa_color {
		color_attachment_info.imageView = msaa_color_texture.view
		color_attachment_info.resolveImageView = ctx.swapchain.image_views[ctx.swapchain.image_index]
		color_attachment_info.resolveMode = {.AVERAGE_KHR}
	} else {
		color_attachment_info.imageView = ctx.swapchain.image_views[ctx.swapchain.image_index]}

	return color_attachment_info
}

@(private = "file")
@(require_results)
_swapchain_new :: proc(sample_count: Sample_Count_Flag) -> ^Swap_Chain {
	indices := _find_queue_families(ctx.vulkan_state.physical_device, ctx.vulkan_state.surface)

	support, result := _query_swapchain_support(
		ctx.vulkan_state.physical_device,
		ctx.vulkan_state.surface,
		context.temp_allocator,
	)
	if result != .SUCCESS {
		log.panicf("query swapchain failed: %v", result)
	}

	surface_format := _choose_swapchain_surface_format(support.formats)
	present_mode := _choose_swapchain_present_mode(support.presentModes)
	extent := _choose_swapchain_extent(ctx.window, support.capabilities)

	image_count := support.capabilities.minImageCount + 1
	if support.capabilities.maxImageCount > 0 && image_count > support.capabilities.maxImageCount {
		image_count = support.capabilities.maxImageCount
	}

	create_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = ctx.vulkan_state.surface,
		minImageCount    = image_count,
		imageFormat      = surface_format.format,
		imageColorSpace  = surface_format.colorSpace,
		imageExtent      = extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		preTransform     = support.capabilities.currentTransform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = present_mode,
		clipped          = true,
	}

	if indices.graphics != indices.present {
		create_info.imageSharingMode = .CONCURRENT
		create_info.queueFamilyIndexCount = 2
		create_info.pQueueFamilyIndices = raw_data([]u32{indices.graphics.?, indices.present.?})
	}

	vk_swapchain: vk.SwapchainKHR
	must(vk.CreateSwapchainKHR(ctx.vulkan_state.device, &create_info, nil, &vk_swapchain))

	swapchain := new(Swap_Chain)
	swapchain.swapchain = vk_swapchain
	swapchain.color_format = surface_format
	swapchain.extent = extent
	swapchain.sample_count = sample_count
	_swapchain_setup_images(swapchain)
	_swapchain_setup_semaphores(swapchain)

	return swapchain
}

@(private = "file")
_swapchain_setup :: proc(swapchain: ^Swap_Chain, command_buffer: vk.CommandBuffer) {
	if swapchain.sample_count != ._1 {
		_swapchain_setup_msaa_color_texture(swapchain)
	}
	_swapchain_setupt_depth_texture(swapchain, command_buffer)
}

@(private = "file")
_swapchain_recreate :: proc(swapchain: ^Swap_Chain) {
	vk.DeviceWaitIdle(ctx.vulkan_state.device)

	_swapchain_destroy(swapchain)

	swapchain := _swapchain_new(swapchain.sample_count)

	sc := begin_single_cmd()
	_swapchain_setup(swapchain, sc.cmd)
	end_single_cmd(sc)
}


@(private = "file")
_swapchain_destroy :: proc(swapchain: ^Swap_Chain) {
	msaa_color_texture, has_color_texture := swapchain.msaa_color_texture.?
	if has_color_texture {
		destroy_texture(&msaa_color_texture)
	}
	destroy_texture(&swapchain.depth_image)

	for sem in swapchain.render_finished_semaphores {
		vk.DestroySemaphore(ctx.vulkan_state.device, sem, nil)
	}
	delete(swapchain.render_finished_semaphores)

	for view in swapchain.image_views {
		vk.DestroyImageView(ctx.vulkan_state.device, view, nil)
	}

	delete(swapchain.image_views)
	delete(swapchain.images)

	vk.DestroySwapchainKHR(ctx.vulkan_state.device, swapchain.swapchain, nil)

	free(swapchain)
}

@(private = "file")
_swapchain_setup_msaa_color_texture :: proc(swapchain: ^Swap_Chain) {
	color_format := swapchain.color_format.format

	image, allocation, allocation_info := _create_image(
		swapchain.extent.width,
		swapchain.extent.height,
		1,
		swapchain.sample_count,
		color_format,
		vk.ImageTiling.OPTIMAL,
		vk.ImageUsageFlags{.TRANSIENT_ATTACHMENT, .COLOR_ATTACHMENT},
		vma.MemoryUsage.AUTO_PREFER_DEVICE,
		vma.AllocationCreateFlags{},
	)

	view := _create_image_view(image, color_format, {.COLOR}, 1)

	texture := Texture {
		name            = "swapchain_msaa_color_texture",
		image           = image,
		format          = color_format,
		view            = view,
		allocation      = allocation,
		allocation_info = allocation_info,
	}

	swapchain.msaa_color_texture = texture

	s := begin_single_cmd()
	_transition_image_layout(
		s.cmd,
		texture.image,
		{.COLOR},
		ctx.swapchain.color_format.format,
		.UNDEFINED,
		.COLOR_ATTACHMENT_OPTIMAL,
		1,
	)
	end_single_cmd(s)
}

@(private = "file")
_swapchain_setupt_depth_texture :: proc(swapchain: ^Swap_Chain, command_buffer: vk.CommandBuffer) {
	format := _find_depth_format(ctx.vulkan_state.physical_device)
	image, allocation, allocation_info := _create_image(
		swapchain.extent.width,
		swapchain.extent.height,
		1,
		swapchain.sample_count,
		format,
		vk.ImageTiling.OPTIMAL,
		vk.ImageUsageFlags{.DEPTH_STENCIL_ATTACHMENT},
		vma.MemoryUsage.AUTO_PREFER_DEVICE,
		vma.AllocationCreateFlags{},
	)

	_transition_image_layout(command_buffer, image, {.DEPTH}, format, .UNDEFINED, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL, 1)

	view := _create_image_view(image, format, {.DEPTH}, 1)
	swapchain.depth_image = Texture {
		image           = image,
		format          = format,
		view            = view,
		allocation      = allocation,
		allocation_info = allocation_info,
	}
}

@(private = "file")
_swapchain_setup_images :: proc(swapchain: ^Swap_Chain) {
	swapchain.image_index = 0

	count: u32
	must(vk.GetSwapchainImagesKHR(ctx.vulkan_state.device, swapchain.swapchain, &count, nil))

	swapchain.images = make([]vk.Image, count)
	swapchain.image_views = make([]vk.ImageView, count)
	must(vk.GetSwapchainImagesKHR(ctx.vulkan_state.device, swapchain.swapchain, &count, raw_data(swapchain.images)))

	for image, i in swapchain.images {
		swapchain.image_views[i] = _create_image_view(image, swapchain.color_format.format, {.COLOR}, 1)
	}
}

@(private = "file")
_swapchain_setup_semaphores :: proc(swapchain: ^Swap_Chain) {
	swapchain.render_finished_semaphores = make([]vk.Semaphore, len(swapchain.images))
	sem_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	for _, i in swapchain.images {
		must(vk.CreateSemaphore(ctx.vulkan_state.device, &sem_info, nil, &swapchain.render_finished_semaphores[i]))
	}
}

@(private = "file")
@(require_results)
_choose_swapchain_surface_format :: proc(formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
	for format in formats {
		if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
			return format
		}
	}

	// Fallback non optimal.
	return formats[0]
}

@(private = "file")
@(require_results)
_choose_swapchain_present_mode :: proc(modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
	// We would like mailbox for the best tradeoff between tearing and latency.
	for mode in modes {
		if mode == .MAILBOX {
			return .MAILBOX
		}
	}
	log.error("Fifo selected")

	// As a fallback, fifo (basically vsync) is always available.
	return .FIFO
}

@(private = "file")
@(require_results)
_choose_swapchain_extent :: proc(window: ^glfw.WindowHandle, capabilities: vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
	// special value (0xFFFFFFFF, 0xFFFFFFFF) indicating that the surface size will be determined
	// by the extent of a swapchain targeting the surface.
	if capabilities.currentExtent.width != max(u32) {
		return capabilities.currentExtent
	}

	width, height := glfw.GetFramebufferSize(window^)
	return vk.Extent2D {
		width = clamp(u32(width), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
		height = clamp(u32(height), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
	}
}
