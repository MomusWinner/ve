package graphic

import "base:runtime"

import "core:log"
import "core:slice"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

create_swapchain :: proc(g: ^Graphic) {
	indices := find_queue_families(g.physical_device, g.surface)

	support, result := query_swapchain_support(g.physical_device, g.surface, context.temp_allocator)
	if result != .SUCCESS {
		log.panicf("vulkan: query swapchain failed: %v", result)
	}

	surface_format := choose_swapchain_surface_format(support.formats)
	present_mode := choose_swapchain_present_mode(support.presentModes)
	extent := choose_swapchain_extent(g.window, support.capabilities)

	image_count := support.capabilities.minImageCount + 1
	if support.capabilities.maxImageCount > 0 && image_count > support.capabilities.maxImageCount {
		image_count = support.capabilities.maxImageCount
	}

	create_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = g.surface,
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

	swapchain: vk.SwapchainKHR
	must(vk.CreateSwapchainKHR(g.device, &create_info, nil, &swapchain))

	g.swapchain = new(SwapChain)
	g.swapchain.swapchain = swapchain
	g.swapchain.format = surface_format
	g.swapchain.extent = extent
	setup_swapchain_images(g.swapchain, g.device)

	g.swapchain.render_finished_semaphores = make([]vk.Semaphore, len(g.swapchain.images))
	sem_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	for _, i in g.swapchain.images {
		must(vk.CreateSemaphore(g.device, &sem_info, nil, &g.swapchain.render_finished_semaphores[i]))
	}
}

destroy_swapchain :: proc(g: ^Graphic) {
	destroy_texture_image(g, &g.swapchain.color_image)
	destroy_texture_image(g, &g.swapchain.depth_image)

	for sem in g.swapchain.render_finished_semaphores {
		vk.DestroySemaphore(g.device, sem, nil)
	}
	delete(g.swapchain.render_finished_semaphores)

	for view in g.swapchain.image_views {
		vk.DestroyImageView(g.device, view, nil)
	}

	delete(g.swapchain.image_views)

	delete(g.swapchain.images)

	vk.DestroySwapchainKHR(g.device, g.swapchain.swapchain, nil)

	free(g.swapchain)
}

create_color_resource :: proc(g: ^Graphic) {
	color_format := g.swapchain.format.format
	image, memory := create_image(
		g,
		g.swapchain.extent.width,
		g.swapchain.extent.height,
		1,
		g.msaa_samples,
		color_format,
		.OPTIMAL,
		{.TRANSIENT_ATTACHMENT, .COLOR_ATTACHMENT},
		{.DEVICE_LOCAL},
	)

	view := create_image_view(g.device, image, color_format, {.COLOR}, 1)

	g.swapchain.color_image = TextureImage {
		image  = image,
		view   = view,
		memory = memory,
	}
}

create_framebuffers :: proc(g: ^Graphic) {
	g.swapchain.frame_buffers = make([]vk.Framebuffer, len(g.swapchain.image_views))
	for view, i in g.swapchain.image_views {
		attachments := []vk.ImageView{g.swapchain.color_image.view, g.swapchain.depth_image.view, view}

		frame_buffer := vk.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = g.render_pass,
			attachmentCount = cast(u32)len(attachments),
			pAttachments    = raw_data(attachments),
			width           = g.swapchain.extent.width,
			height          = g.swapchain.extent.height,
			layers          = 1,
		}
		must(vk.CreateFramebuffer(g.device, &frame_buffer, nil, &g.swapchain.frame_buffers[i]))
	}
}

destroy_framebuffers :: proc(g: ^Graphic) {
	for frame_buffer in g.swapchain.frame_buffers {
		vk.DestroyFramebuffer(g.device, frame_buffer, nil)
	}
	delete(g.swapchain.frame_buffers)
}

setup_swapchain_images :: proc(swapchain: ^SwapChain, device: vk.Device) {
	count: u32
	must(vk.GetSwapchainImagesKHR(device, swapchain.swapchain, &count, nil))

	swapchain.images = make([]vk.Image, count)
	swapchain.image_views = make([]vk.ImageView, count)
	must(vk.GetSwapchainImagesKHR(device, swapchain.swapchain, &count, raw_data(swapchain.images)))

	for image, i in swapchain.images {
		swapchain.image_views[i] = create_image_view(device, image, swapchain.format.format, {.COLOR}, 1)
	}
}

recreate_swapchain :: proc(g: ^Graphic) {
	// Don't do anything when minimized.
	for w, h := glfw.GetFramebufferSize(g.window); w == 0 || h == 0; w, h = glfw.GetFramebufferSize(g.window) {
		glfw.WaitEvents()

		// Handle closing while minimized.
		if glfw.WindowShouldClose(g.window) {break}
	}

	vk.DeviceWaitIdle(g.device)

	destroy_framebuffers(g)
	destroy_swapchain(g)

	create_swapchain(g)
	g.swapchain.depth_image = create_depth_resources(g)
	create_color_resource(g)
	create_framebuffers(g)
}
