package graphics

import vk "vendor:vulkan"

SingleCommand :: struct {
	command_buffer: vk.CommandBuffer,
	_device:        vk.Device,
	_command_pool:  vk.CommandPool,
	_queue:         vk.Queue,
}

_begin_single_command :: proc {
	_begin_single_command_from_device,
	_begin_single_command_from_graphics,
}

_begin_single_command_from_graphics :: proc(g: ^Graphics) -> SingleCommand {
	return _begin_single_command_from_device(g.device, g.command_pool, g.graphics_queue)
}

_begin_single_command_from_device :: proc(
	device: vk.Device,
	command_pool: vk.CommandPool,
	queue: vk.Queue,
) -> SingleCommand {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = command_pool,
		commandBufferCount = 1,
	}

	command_buffer: vk.CommandBuffer
	must(vk.AllocateCommandBuffers(device, &alloc_info, &command_buffer))

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	must(vk.BeginCommandBuffer(command_buffer, &begin_info))

	return SingleCommand {
		command_buffer = command_buffer,
		_device = device,
		_command_pool = command_pool,
		_queue = queue,
	}
}

_end_single_command :: proc(single_command: SingleCommand) {
	command_buffer := single_command.command_buffer

	must(vk.EndCommandBuffer(command_buffer))

	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &command_buffer,
	}

	must(vk.QueueSubmit(single_command._queue, 1, &submit_info, 0))
	must(vk.QueueWaitIdle(single_command._queue))

	vk.FreeCommandBuffers(single_command._device, single_command._command_pool, 1, &command_buffer)
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
