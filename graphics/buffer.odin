package graphics

import "base:intrinsics"
import "base:runtime"
import "core:log"
import "core:slice"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"
import "vma"

destroy_buffer :: proc(buffer: ^Buffer, loc := #caller_location) {
	assert_not_nil(buffer, loc)

	if (buffer.mapped != nil) {
		vma.UnmapMemory(ctx.vulkan_state.allocator, buffer.allocation)
		buffer.mapped = nil
	}
	vma.DestroyBuffer(ctx.vulkan_state.allocator, buffer.buffer, buffer.allocation)
}

create_vertex_buffer :: proc(vertices: rawptr, size: vk.DeviceSize, loc := #caller_location) -> Buffer {
	assert(vertices != nil, loc = loc)
	assert(size > 0, loc = loc)

	return _create_device_local_buffer(size, vertices, {.VERTEX_BUFFER}, {.SHADER_READ}, {.VERTEX_SHADER})
}

create_index_buffer :: proc(indices: rawptr, size: vk.DeviceSize, loc := #caller_location) -> Buffer {
	assert(indices != nil, loc = loc)
	assert(size > 0, loc = loc)

	return _create_device_local_buffer(size, indices, {.INDEX_BUFFER}, {.INDEX_READ}, {.VERTEX_INPUT})
}

create_uniform_buffer :: proc(size: vk.DeviceSize, loc := #caller_location) -> Buffer {
	assert(size > 0, loc = loc)

	return _create_mapped_buffer(size, {.UNIFORM_BUFFER}, {.UNIFORM_READ}, {.VERTEX_SHADER})
}

// TODO: only for particle
create_ssbo :: proc(g: ^Graphics, data: rawptr, size: vk.DeviceSize) -> Buffer {
	return _create_device_local_buffer(size, data, {.VERTEX_BUFFER, .STORAGE_BUFFER}, {.SHADER_READ}, {.VERTEX_SHADER})
}

fill_buffer :: proc(
	buffer: ^Buffer,
	buffer_size: vk.DeviceSize,
	data: rawptr,
	offset: vk.DeviceSize = 0,
	loc := #caller_location,
) {
	assert_not_nil(buffer, loc)
	assert(buffer_size > 0, loc = loc)

	must(vma.CopyMemoryToAllocation(ctx.vulkan_state.allocator, data, buffer.allocation, offset, buffer_size))
}

@(private)
_copy_buffer :: proc(cb: vk.CommandBuffer, src_buffer: Buffer, dst_buffer: Buffer, size: vk.DeviceSize) {
	copy := vk.BufferCopy {
		srcOffset = 0,
		dstOffset = 0,
		size      = size,
	}
	vk.CmdCopyBuffer(cb, src_buffer.buffer, dst_buffer.buffer, 1, &copy)
}

@(private)
_create_buffer :: proc(
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	memory_usage: vma.MemoryUsage,
	memory_flags: vma.AllocationCreateFlags,
	required_flags: vk.MemoryPropertyFlags = {},
	preferred_flags: vk.MemoryPropertyFlags = {},
) -> Buffer {
	buffer_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}

	allocation_create_info := vma.AllocationCreateInfo {
		usage          = memory_usage,
		flags          = memory_flags,
		requiredFlags  = required_flags,
		preferredFlags = preferred_flags,
	}

	vk_buffer: vk.Buffer
	allocation: vma.Allocation
	allocation_info: vma.AllocationInfo
	vma.CreateBuffer(
		ctx.vulkan_state.allocator,
		&buffer_info,
		&allocation_create_info,
		&vk_buffer,
		&allocation,
		&allocation_info,
	)
	buffer := Buffer {
		buffer          = vk_buffer,
		usage           = usage,
		allocation      = allocation,
		allocation_info = allocation_info,
	}

	return buffer
}

@(private = "file")
_create_device_local_buffer :: proc(
	size: vk.DeviceSize,
	data: rawptr,
	usage: vk.BufferUsageFlags,
	dst_access_mask: vk.AccessFlags,
	dst_stage_mask: vk.PipelineStageFlags,
) -> Buffer {
	sc := begin_single_cmd()

	// Staging buffer
	staging_buffer := _create_buffer(size, {.TRANSFER_SRC}, .AUTO, {.HOST_ACCESS_SEQUENTIAL_WRITE})
	fill_buffer(&staging_buffer, size, data)
	_cmd_buffer_barrier(sc.cmd, staging_buffer, {.HOST_WRITE}, {.TRANSFER_READ}, {.HOST}, {.TRANSFER})
	defer destroy_buffer(&staging_buffer)

	// Result buffer
	buffer := _create_buffer(size, {.TRANSFER_DST} + usage, .AUTO_PREFER_DEVICE, {})
	_copy_buffer(sc.cmd, staging_buffer, buffer, size)
	_cmd_buffer_barrier(sc.cmd, buffer, {.TRANSFER_WRITE}, dst_access_mask, {.TRANSFER}, dst_stage_mask)

	end_single_cmd(sc)

	return buffer
}

@(private = "file")
_create_mapped_buffer :: proc(
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	dst_access_mask: vk.AccessFlags,
	dst_stage_mask: vk.PipelineStageFlags,
) -> Buffer {
	buffer := _create_buffer(size, usage, .AUTO_PREFER_HOST, {.HOST_ACCESS_SEQUENTIAL_WRITE, .MAPPED}, {}, {})

	sc := begin_single_cmd()

	must(vma.MapMemory(ctx.vulkan_state.allocator, buffer.allocation, &buffer.mapped))
	_cmd_buffer_barrier(sc.cmd, buffer, {.HOST_WRITE}, dst_access_mask, {.HOST}, dst_stage_mask)

	end_single_cmd(sc)

	return buffer
}
