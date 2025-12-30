package graphics

import sm "core:container/small_array"
import "core:log"
import "vendor:glfw"
import vk "vendor:vulkan"

@(require_results)
get_screen_size :: proc() -> (width: u32, height: u32) {
	width = ctx.swapchain.extent.width
	height = ctx.swapchain.extent.height
	return
}

@(require_results)
get_screen_width :: proc() -> u32 {return ctx.swapchain.extent.width}
@(require_results)
get_screen_height :: proc() -> u32 {return ctx.swapchain.extent.height}
@(require_results)
get_screen_aspect :: proc() -> f32 {return cast(f32)get_screen_width() / cast(f32)get_screen_height()}

get_device_width :: proc() -> u32 {
	width, height := glfw.GetFramebufferSize(ctx.window^)
	return cast(u32)width
}

get_device_height :: proc() -> u32 {
	width, height := glfw.GetFramebufferSize(ctx.window^)
	return cast(u32)height
}

screen_resized :: proc() -> bool {
	return ctx.swapchain_resized
}

set_full_viewport_scissor :: proc(frame_data: Frame_Data, loc := #caller_location) {
	assert_gfx_ctx(loc)
	width := get_screen_width()
	height := get_screen_height()

	set_viewport(frame_data, width, height, loc = loc)
	set_scissor(frame_data, width, height, loc = loc)
}

set_viewport :: proc(frame_data: Frame_Data, width, height: u32, max_depth: f32 = 0.1, loc := #caller_location) {
	assert_gfx_ctx(loc)

	viewport := vk.Viewport {
		width    = cast(f32)width,
		height   = cast(f32)height,
		maxDepth = max_depth,
	}
	vk.CmdSetViewport(frame_data.cmd, 0, 1, &viewport)
}

set_scissor :: proc(frame_data: Frame_Data, width, height: u32, offset: ivec2 = 0, loc := #caller_location) {
	assert_gfx_ctx(loc)

	scissor := vk.Rect2D {
		extent = {width = width, height = height},
		offset = {x = offset.x, y = offset.y},
	}
	vk.CmdSetScissor(frame_data.cmd, 0, 1, &scissor)
}

begin_render :: proc(loc := #caller_location) -> Frame_Data {
	assert_gfx_ctx(loc)
	assert(!ctx.render_started, "Call end_render() after begin_render()", loc)

	defer ctx.render_started = true

	frame_data := Frame_Data {
		cmd    = ctx.cmd,
		status = .Success,
	}

	// Wait for previous frame
	must(vk.WaitForFences(ctx.vulkan_state.device, 1, &ctx.fence, true, max(u64)))

	images: u32 = cast(u32)len(ctx.swapchain.images)
	acquire_result := vk.AcquireNextImageKHR(
		device = ctx.vulkan_state.device,
		swapchain = ctx.swapchain.swapchain,
		timeout = max(u64),
		semaphore = ctx.image_available_semaphore,
		fence = {},
		pImageIndex = &ctx.swapchain.image_index,
	)

	#partial switch acquire_result {
	case .ERROR_OUT_OF_DATE_KHR:
		frame_data.status = .IncorrectSwapchainSize
		return {}
	case .SUCCESS, .SUBOPTIMAL_KHR:
	case:
		log.panicf("acquire next image failure: %v", acquire_result)
	}

	must(vk.ResetFences(ctx.vulkan_state.device, 1, &ctx.fence))
	must(vk.ResetCommandBuffer(frame_data.cmd, {}))

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	must(vk.BeginCommandBuffer(frame_data.cmd, &begin_info))

	return frame_data
}

end_render :: proc(frame_data: Frame_Data, sync_data: Sync_Data = {}) {
	if !ctx.render_started {
		log.error("Call begin_render() before end_render()")
	}
	defer ctx.render_started = false

	frame_data := frame_data

	must(vk.EndCommandBuffer(frame_data.cmd))

	wait_semaphore_infos := merge(
		sync_data.wait_semaphore_infos,
		[]vk.SemaphoreSubmitInfo {
			{
				sType = .SEMAPHORE_SUBMIT_INFO,
				semaphore = ctx.image_available_semaphore,
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
		semaphore = ctx.swapchain.render_finished_semaphores[ctx.swapchain.image_index],
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
	must(vk.QueueSubmit2(ctx.vulkan_state.graphics_queue, 1, &submit_info, ctx.fence))

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &ctx.swapchain.render_finished_semaphores[ctx.swapchain.image_index],
		swapchainCount     = 1,
		pSwapchains        = &ctx.swapchain.swapchain,
		pImageIndices      = &ctx.swapchain.image_index,
	}
	present_result := vk.QueuePresentKHR(ctx.vulkan_state.present_queue, &present_info)

	switch {
	case present_result == .ERROR_OUT_OF_DATE_KHR || present_result == .SUBOPTIMAL_KHR:
		frame_data.status = .IncorrectSwapchainSize
	case present_result == .SUCCESS:
	case:
		log.panicf("vulkan: present failure: %v", present_result)
	}

	if ctx.swapchain_resized {
		ctx.swapchain_resized = false
	}

	if frame_data.status == .IncorrectSwapchainSize {
		ctx.swapchain_resized = true
		on_screen_resized()
	}

	_clear_temp_pool()
	_clear_deffered_destructor()
}

begin_draw :: proc(frame: Frame_Data, clear_color: vec4 = {0.0, 0.0, 0.0, 1.0}) -> Frame_Data {
	clear_color := vk.ClearValue {
		color = {float32 = clear_color},
	}

	_transition_image_layout(
		frame.cmd,
		ctx.swapchain.images[ctx.swapchain.image_index],
		{.COLOR},
		ctx.swapchain.format.format,
		.UNDEFINED,
		.COLOR_ATTACHMENT_OPTIMAL,
		1,
	)

	color_attachment_info := vk.RenderingAttachmentInfo {
		sType              = .RENDERING_ATTACHMENT_INFO,
		pNext              = nil,
		imageView          = ctx.swapchain.color_image.view,
		imageLayout        = .ATTACHMENT_OPTIMAL,
		resolveMode        = {.AVERAGE_KHR},
		resolveImageView   = ctx.swapchain.image_views[ctx.swapchain.image_index],
		resolveImageLayout = .COLOR_ATTACHMENT_OPTIMAL,
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
		imageView   = ctx.swapchain.depth_image.view,
		imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .DONT_CARE,
		clearValue  = depth_stencil_clear_value,
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = ctx.swapchain.extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment_info,
		pDepthAttachment = &depth_stencil_attachment_info,
	}

	vk.CmdBeginRendering(frame.cmd, &rendering_info)

	frame := frame

	frame.surface_info = Surface_Info {
		type         = .Swapchain,
		sample_count = ctx.swapchain.sample_count,
		depth_format = ctx.swapchain.depth_image.format,
	}
	sm.push(&frame.surface_info.color_formats, ctx.swapchain.color_image.format)

	return frame
}

end_draw :: proc(frame: Frame_Data) {
	vk.CmdEndRendering(frame.cmd)

	_transition_image_layout(
		frame.cmd,
		ctx.swapchain.images[ctx.swapchain.image_index],
		{.COLOR},
		ctx.swapchain.format.format,
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR,
		1,
	)
}

on_screen_resized :: proc() {
	// Don't do anything when minimized.
	for w, h := glfw.GetFramebufferSize(ctx.window^); w == 0 || h == 0; w, h = glfw.GetFramebufferSize(ctx.window^) {
		glfw.WaitEvents()

		// Handle closing while minimized.
		if glfw.WindowShouldClose(ctx.window^) {return}
	}
	_recreate_swapchain()
	_surface_manager_resize_fit_screen_surfaces(ctx.surface_manager)
}

wait_render_completion :: proc() {
	vk.DeviceWaitIdle(ctx.vulkan_state.device)
}
