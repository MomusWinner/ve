package graphics

import "base:runtime"

import "core:log"
import "core:slice"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

@(private)
_swapchain_new :: proc(
	window: glfw.WindowHandle,
	physical_device: vk.PhysicalDevice,
	device: vk.Device,
	surface: vk.SurfaceKHR,
	samples: vk.SampleCountFlags,
) -> ^Swap_Chain {
	indices := find_queue_families(physical_device, surface)

	support, result := query_swapchain_support(physical_device, surface, context.temp_allocator)
	if result != .SUCCESS {
		log.panicf("query swapchain failed: %v", result)
	}

	surface_format := _choose_swapchain_surface_format(support.formats)
	present_mode := _choose_swapchain_present_mode(support.presentModes)
	extent := _choose_swapchain_extent(window, support.capabilities)

	image_count := support.capabilities.minImageCount + 1
	if support.capabilities.maxImageCount > 0 && image_count > support.capabilities.maxImageCount {
		image_count = support.capabilities.maxImageCount
	}

	create_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = surface,
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
	must(vk.CreateSwapchainKHR(device, &create_info, nil, &vk_swapchain))

	swapchain := new(Swap_Chain)
	swapchain.swapchain = vk_swapchain
	swapchain.format = surface_format
	swapchain.extent = extent
	swapchain.samples = samples
	swapchain._device = device
	swapchain._physical_device = physical_device
	swapchain._surface = surface
	_swapchain_setup_images(swapchain)
	_swapchain_setup_semaphores(swapchain)

	return swapchain
}

@(private)
_swapchain_setup :: proc(swapchain: ^Swap_Chain, render_pass: vk.RenderPass, command_buffer: vk.CommandBuffer) {
	_swapchain_setup_color_resource(swapchain)
	_swapchain_setupt_depth_buffer(swapchain, command_buffer)
	_swapchain_setup_framebuffers(swapchain, render_pass)
}

@(private)
_swapchain_destroy :: proc(swapchain: ^Swap_Chain) {
	_swapchain_destroy_framebuffers(swapchain)

	destroy_texture_image(swapchain._device, &swapchain.color_image)
	destroy_texture_image(swapchain._device, &swapchain.depth_image)

	for sem in swapchain.render_finished_semaphores {
		vk.DestroySemaphore(swapchain._device, sem, nil)
	}
	delete(swapchain.render_finished_semaphores)

	for view in swapchain.image_views {
		vk.DestroyImageView(swapchain._device, view, nil)
	}

	delete(swapchain.image_views)

	delete(swapchain.images)

	vk.DestroySwapchainKHR(swapchain._device, swapchain.swapchain, nil)

	free(swapchain)
}

@(private)
_recreate_swapchain :: proc(g: ^Graphics) {
	// Don't do anything when minimized.
	for w, h := glfw.GetFramebufferSize(g.window); w == 0 || h == 0; w, h = glfw.GetFramebufferSize(g.window) {
		glfw.WaitEvents()

		// Handle closing while minimized.
		if glfw.WindowShouldClose(g.window) {break}
	}

	vk.DeviceWaitIdle(g.device)

	_swapchain_destroy(g.swapchain)

	g.swapchain = _swapchain_new(g.window, g.physical_device, g.device, g.surface, g.msaa_samples)

	sc := _begin_single_command(g)
	_swapchain_setup(g.swapchain, g.render_pass, sc.command_buffer)
	_end_single_command(sc)
}

@(private = "file")
_swapchain_setup_color_resource :: proc(swapchain: ^Swap_Chain) {
	color_format := swapchain.format.format

	image, memory := _create_image(
		swapchain._device,
		swapchain._physical_device,
		swapchain.extent.width,
		swapchain.extent.height,
		1,
		swapchain.samples,
		color_format,
		vk.ImageTiling.OPTIMAL,
		vk.ImageUsageFlags{.TRANSIENT_ATTACHMENT, .COLOR_ATTACHMENT},
		vk.MemoryPropertyFlags{.DEVICE_LOCAL},
	)

	view := create_image_view(swapchain._device, image, color_format, {.COLOR}, 1)

	swapchain.color_image = TextureImage {
		image  = image,
		view   = view,
		memory = memory,
	}
}

@(private = "file")
_swapchain_setupt_depth_buffer :: proc(swapchain: ^Swap_Chain, command_buffer: vk.CommandBuffer) {
	format := _find_depth_format(swapchain._physical_device)
	image, memory := _create_image(
		swapchain._device,
		swapchain._physical_device,
		swapchain.extent.width,
		swapchain.extent.height,
		1,
		swapchain.samples,
		format,
		vk.ImageTiling.OPTIMAL,
		vk.ImageUsageFlags{.DEPTH_STENCIL_ATTACHMENT},
		vk.MemoryPropertyFlags{.DEVICE_LOCAL},
	)

	_transition_image_layout(command_buffer, image, {.DEPTH}, format, .UNDEFINED, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL, 1)

	view := create_image_view(swapchain._device, image, format, {.DEPTH}, 1)
	swapchain.depth_image = TextureImage{image, view, memory}
}

@(private = "file")
_swapchain_setup_framebuffers :: proc(swapchain: ^Swap_Chain, render_pass: vk.RenderPass) {
	swapchain.frame_buffers = make([]vk.Framebuffer, len(swapchain.image_views))
	for view, i in swapchain.image_views {
		attachments := []vk.ImageView{swapchain.color_image.view, swapchain.depth_image.view, view}

		frame_buffer := vk.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = render_pass,
			attachmentCount = cast(u32)len(attachments),
			pAttachments    = raw_data(attachments),
			width           = swapchain.extent.width,
			height          = swapchain.extent.height,
			layers          = 1,
		}
		must(vk.CreateFramebuffer(swapchain._device, &frame_buffer, nil, &swapchain.frame_buffers[i]))
	}
}

@(private = "file")
_swapchain_destroy_framebuffers :: proc(swapchain: ^Swap_Chain) {
	for frame_buffer in swapchain.frame_buffers {
		vk.DestroyFramebuffer(swapchain._device, frame_buffer, nil)
	}
	delete(swapchain.frame_buffers)
}

@(private = "file")
_swapchain_setup_images :: proc(swapchain: ^Swap_Chain) {
	count: u32
	must(vk.GetSwapchainImagesKHR(swapchain._device, swapchain.swapchain, &count, nil))

	swapchain.images = make([]vk.Image, count)
	swapchain.image_views = make([]vk.ImageView, count)
	must(vk.GetSwapchainImagesKHR(swapchain._device, swapchain.swapchain, &count, raw_data(swapchain.images)))

	for image, i in swapchain.images {
		swapchain.image_views[i] = create_image_view(swapchain._device, image, swapchain.format.format, {.COLOR}, 1)
	}
}

@(private = "file")
_swapchain_setup_semaphores :: proc(swapchain: ^Swap_Chain) {
	swapchain.render_finished_semaphores = make([]vk.Semaphore, len(swapchain.images))
	sem_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	for _, i in swapchain.images {
		must(vk.CreateSemaphore(swapchain._device, &sem_info, nil, &swapchain.render_finished_semaphores[i]))
	}
}

@(private = "file")
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
_choose_swapchain_extent :: proc(window: glfw.WindowHandle, capabilities: vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
	if capabilities.currentExtent.width != max(u32) {
		return capabilities.currentExtent
	}

	width, height := glfw.GetFramebufferSize(window)
	return (vk.Extent2D {
				width = clamp(u32(width), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
				height = clamp(u32(height), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
			})
}
