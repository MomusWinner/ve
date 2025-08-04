package graphic

import "base:intrinsics"
import "base:runtime"

import "core:log"
import "core:slice"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

// TODO: research
find_memory_type :: proc(
	physical_device: vk.PhysicalDevice,
	type_filter: u32,
	properties: vk.MemoryPropertyFlags,
) -> (
	memory_type: u32,
	ok: bool,
) {
	mem_property: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(physical_device, &mem_property)

	for i: u32 = 0; i < mem_property.memoryTypeCount; i += 1 {
		if (type_filter & (1 << i) != 0) &&
		   (mem_property.memoryTypes[i].propertyFlags >= properties) {
			return i, true
		}
	}

	return 0, false
}

create_buffer :: proc(
	g: ^Graphic,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	properties: vk.MemoryPropertyFlags,
) -> Buffer {
	buffer_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}

	buffer: Buffer
	must(vk.CreateBuffer(g.device, &buffer_info, nil, &buffer.buffer))

	mem_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(g.device, buffer.buffer, &mem_requirements)

	memory_type, ok := find_memory_type(
		g.physical_device,
		mem_requirements.memoryTypeBits,
		properties,
	)
	if !ok {
		log.fatal("Failed to find suitable memory type!")
	}

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = memory_type,
	}

	if vk.AllocateMemory(g.device, &alloc_info, nil, &buffer.memory) != .SUCCESS {
		log.fatal("Failed to allocate buffer memory")
	}

	vk.BindBufferMemory(g.device, buffer.buffer, buffer.memory, 0)

	return buffer
}

destroy_buffer :: proc(g: ^Graphic, buffer: ^Buffer) {
	vk.DestroyBuffer(g.device, buffer.buffer, nil)
	vk.FreeMemory(g.device, buffer.memory, nil)
	buffer.buffer = 0
	buffer.memory = 0
}

fill_buffer :: proc(g: ^Graphic, buffer: Buffer, buffer_size: vk.DeviceSize, vertices: rawptr) {
	data: rawptr
	vk.MapMemory(g.device, buffer.memory, 0, buffer_size, {}, &data)
	intrinsics.mem_copy(data, vertices, buffer_size)
	vk.UnmapMemory(g.device, buffer.memory)
}


copy_buffer :: proc(
	g: ^Graphic,
	src_buffer: Buffer,
	dst_buffer: Buffer,
	device_size: vk.DeviceSize,
) {
	command_buffer := begin_single_command(g)

	copy := vk.BufferCopy {
		srcOffset = 0,
		dstOffset = 0,
		size      = device_size,
	}
	vk.CmdCopyBuffer(command_buffer, src_buffer.buffer, dst_buffer.buffer, 1, &copy)

	end_single_command(g, command_buffer)
}

create_vertex_buffer :: proc(g: ^Graphic, vertices: rawptr, size: vk.DeviceSize) -> Buffer {
	staging_buffer := create_buffer(g, size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT})
	fill_buffer(g, staging_buffer, size, vertices)

	vertex_buffer := create_buffer(g, size, {.TRANSFER_DST, .VERTEX_BUFFER}, {.DEVICE_LOCAL})
	copy_buffer(g, staging_buffer, vertex_buffer, size)

	destroy_buffer(g, &staging_buffer)

	return vertex_buffer
}

create_index_buffer :: proc(g: ^Graphic, indices: rawptr, size: vk.DeviceSize) -> Buffer {
	staging_buffer := create_buffer(g, size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT})
	fill_buffer(g, staging_buffer, size, indices)

	index_buffer := create_buffer(g, size, {.TRANSFER_DST, .INDEX_BUFFER}, {.DEVICE_LOCAL})
	copy_buffer(g, staging_buffer, index_buffer, size)

	destroy_buffer(g, &staging_buffer)

	return index_buffer
}

create_uniform_buffer :: proc(g: ^Graphic, size: vk.DeviceSize) -> UniformBuffer {
	unfiorm_buffer := UniformBuffer {
		parent = create_buffer(g, size, {.UNIFORM_BUFFER}, {.HOST_COHERENT, .HOST_VISIBLE}),
	}

	vk.MapMemory(g.device, unfiorm_buffer.memory, 0, size, {}, &unfiorm_buffer.mapped)

	return unfiorm_buffer
}

destroy_uniform_buffer :: proc(g: ^Graphic, uniform_buffer: ^UniformBuffer) {
	vk.UnmapMemory(g.device, uniform_buffer.memory)
	destroy_buffer(g, &uniform_buffer.parent)
	uniform_buffer.mapped = nil
}
