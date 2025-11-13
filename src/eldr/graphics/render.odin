package graphics

import "core:log"
import "vendor:glfw"
import vk "vendor:vulkan"

@(require_results)
get_screen_size :: proc(g: ^Graphics) -> (width: u32, height: u32) {
	width = g.swapchain.extent.width
	height = g.swapchain.extent.height
	return
}

@(require_results)
get_screen_width :: proc(g: ^Graphics) -> u32 {return g.swapchain.extent.width}
@(require_results)
get_screen_height :: proc(g: ^Graphics) -> u32 {return g.swapchain.extent.height}
@(require_results)
get_screen_aspect :: proc(g: ^Graphics) -> f32 {return cast(f32)get_screen_width(g) / cast(f32)get_screen_height(g)}

get_device_width :: proc(g: ^Graphics) -> u32 {
	width, height := glfw.GetFramebufferSize(g.window^)
	return cast(u32)width
}

get_device_height :: proc(g: ^Graphics) -> u32 {
	width, height := glfw.GetFramebufferSize(g.window^)
	return cast(u32)height
}

screen_resized :: proc(g: ^Graphics) -> bool {
	return g.swapchain_resized
}

set_full_viewport_scissor :: proc(g: ^Graphics, frame_data: Frame_Data, loc := #caller_location) {
	assert_not_nil(g, loc)

	width := get_screen_width(g)
	height := get_screen_height(g)

	set_viewport(g, frame_data, width, height, loc = loc)
	set_scissor(g, frame_data, width, height, loc = loc)
}

set_viewport :: proc(
	g: ^Graphics,
	frame_data: Frame_Data,
	width, height: u32,
	max_depth: f32 = 0.1,
	loc := #caller_location,
) {
	viewport := vk.Viewport {
		width    = cast(f32)width,
		height   = cast(f32)height,
		maxDepth = max_depth,
	}
	vk.CmdSetViewport(frame_data.cmd, 0, 1, &viewport)
}

set_scissor :: proc(
	g: ^Graphics,
	frame_data: Frame_Data,
	width, height: u32,
	offset: ivec2 = 0,
	loc := #caller_location,
) {
	scissor := vk.Rect2D {
		extent = {width = width, height = height},
		offset = {x = offset.x, y = offset.y},
	}
	vk.CmdSetScissor(frame_data.cmd, 0, 1, &scissor)
}

begin_render :: proc(g: ^Graphics) -> Frame_Data {
	assert(!g.render_started, "Call end_render() after begin_render()")
	defer g.render_started = true

	frame_data := Frame_Data {
		cmd    = g.cmd,
		status = .Success,
	}

	// Wait for previous frame
	must(vk.WaitForFences(g.vulkan_state.device, 1, &g.fence, true, max(u64)))

	images: u32 = cast(u32)len(g.swapchain.images)
	acquire_result := vk.AcquireNextImageKHR(
		device = g.vulkan_state.device,
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

	must(vk.ResetFences(g.vulkan_state.device, 1, &g.fence))
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
	defer g.render_started = false

	frame_data := frame_data

	must(vk.EndCommandBuffer(frame_data.cmd))

	wait_semaphore_infos := merge(
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
	must(vk.QueueSubmit2(g.vulkan_state.graphics_queue, 1, &submit_info, g.fence))

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &g.swapchain.render_finished_semaphores[g.swapchain.image_index],
		swapchainCount     = 1,
		pSwapchains        = &g.swapchain.swapchain,
		pImageIndices      = &g.swapchain.image_index,
	}
	present_result := vk.QueuePresentKHR(g.vulkan_state.present_queue, &present_info)

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

	_temp_pool_clear(g.temp_material_pool)
	_temp_pool_clear(g.temp_transform_pool)
	_deffered_destructor_clean(g)
}

begin_draw :: proc(g: ^Graphics, frame: Frame_Data) -> Frame_Data {
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

	frame := frame
	frame.surface_info = {
		type         = .Swapchain,
		sample_count = g.swapchain.sample_count,
	}

	return frame
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

on_screen_resized :: proc(g: ^Graphics) {
	// Don't do anything when minimized.
	for w, h := glfw.GetFramebufferSize(g.window^); w == 0 || h == 0; w, h = glfw.GetFramebufferSize(g.window^) {
		glfw.WaitEvents()

		// Handle closing while minimized.
		if glfw.WindowShouldClose(g.window^) {return}
	}
	_recreate_swapchain(g.swapchain, g.vulkan_state, g.window)
	_surface_manager_recreate_surfaces(g.surface_manager, g)
}

wait_render_completion :: proc(g: ^Graphics) {
	vk.DeviceWaitIdle(g.vulkan_state.device)
}
