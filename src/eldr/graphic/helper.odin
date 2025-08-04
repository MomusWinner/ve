package graphic

import vk "vendor:vulkan"

begin_single_command :: proc(g: ^Graphic) -> vk.CommandBuffer {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = g.command_pool,
		commandBufferCount = 1,
	}

	command_buffer: vk.CommandBuffer
	must(vk.AllocateCommandBuffers(g.device, &alloc_info, &command_buffer))

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	must(vk.BeginCommandBuffer(command_buffer, &begin_info))

	return command_buffer
}

end_single_command :: proc(g: ^Graphic, command_buffer: vk.CommandBuffer) {
	cb := command_buffer

	must(vk.EndCommandBuffer(command_buffer))

	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &cb,
	}

	must(vk.QueueSubmit(g.graphics_queue, 1, &submit_info, 0))
	must(vk.QueueWaitIdle(g.graphics_queue))

	vk.FreeCommandBuffers(g.device, g.command_pool, 1, &cb)
}

find_supported_format :: proc(
	physical_device: vk.PhysicalDevice,
	candidates: []vk.Format,
	tiling: vk.ImageTiling,
	features: vk.FormatFeatureFlags,
) -> vk.Format {
	for format in candidates {
		props: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(physical_device, format, &props)

		if (tiling == .OPTIMAL && (props.optimalTilingFeatures & features) == features) {
			return format
		} else if (tiling == .LINEAR && (props.optimalTilingFeatures & features) == features) {
			return format
		}
	}

	panic("failed to find supported format!")
}
