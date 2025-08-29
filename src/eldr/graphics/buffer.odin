package graphics

import "base:intrinsics"
import "base:runtime"
import "core:log"
import "core:slice"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"
import "vma"

destroy_buffer :: proc(g: ^Graphics, buffer: ^Buffer) {
	_destroy_buffer_from_allocator(g.allocator, buffer)
}

_destroy_buffer_from_allocator :: proc(allocator: vma.Allocator, buffer: ^Buffer) {
	if (buffer.mapped != nil) {
		vma.UnmapMemory(allocator, buffer.allocation)
		buffer.mapped = nil
	}
	vma.DestroyBuffer(allocator, buffer.buffer, buffer.allocation)
}

create_vertex_buffer :: proc(g: ^Graphics, vertices: rawptr, size: vk.DeviceSize) -> Buffer {
	return _create_device_local_buffer(g, size, vertices, {.VERTEX_BUFFER}, {.SHADER_READ}, {.VERTEX_SHADER})
}

create_index_buffer :: proc(g: ^Graphics, indices: rawptr, size: vk.DeviceSize) -> Buffer {
	return _create_device_local_buffer(g, size, indices, {.INDEX_BUFFER}, {.INDEX_READ}, {.VERTEX_INPUT})
}

create_uniform_buffer :: proc(g: ^Graphics, size: vk.DeviceSize) -> Buffer {
	return _create_mapped_buffer(g, size, {.UNIFORM_BUFFER}, {.UNIFORM_READ}, {.VERTEX_SHADER})
}

// destroy_uniform_buffer :: proc(g: ^Graphics, uniform_buffer: ^Uniform_Buffer) {
// 	vma.UnmapMemory(g.allocator, uniform_buffer.allocation)
// 	destroy_buffer(g, &uniform_buffer.base)
// 	uniform_buffer.mapped = nil
// }

// TODO: only for particle
create_ssbo :: proc(g: ^Graphics, data: rawptr, size: vk.DeviceSize) -> Buffer {
	return _create_device_local_buffer(
		g,
		size,
		data,
		{.VERTEX_BUFFER, .STORAGE_BUFFER},
		{.SHADER_READ},
		{.VERTEX_SHADER},
	)
}

@(private)
_fill_buffer :: proc(
	g: ^Graphics,
	buffer: ^Buffer,
	buffer_size: vk.DeviceSize,
	data: rawptr,
	offset: vk.DeviceSize = 0,
) {
	vma.CopyMemoryToAllocation(g.allocator, data, buffer.allocation, offset, buffer_size)
}

@(private)
_copy_buffer :: proc {
	_copy_buffer_from_cmd,
	_copy_buffer_from_default,
}

@(private)
_copy_buffer_from_cmd :: proc(
	g: ^Graphics,
	cb: vk.CommandBuffer,
	src_buffer: Buffer,
	dst_buffer: Buffer,
	device_size: vk.DeviceSize,
) {
	copy := vk.BufferCopy {
		srcOffset = 0,
		dstOffset = 0,
		size      = device_size,
	}
	vk.CmdCopyBuffer(cb, src_buffer.buffer, dst_buffer.buffer, 1, &copy)
}

@(private)
_copy_buffer_from_default :: proc(g: ^Graphics, src_buffer: Buffer, dst_buffer: Buffer, device_size: vk.DeviceSize) {
	sc := _cmd_single_begin(g)

	copy := vk.BufferCopy {
		srcOffset = 0,
		dstOffset = 0,
		size      = device_size,
	}
	vk.CmdCopyBuffer(sc.command_buffer, src_buffer.buffer, dst_buffer.buffer, 1, &copy)

	_cmd_single_end(sc)
}

@(private)
_create_buffer :: proc(
	g: ^Graphics,
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
	vma.CreateBuffer(g.allocator, &buffer_info, &allocation_create_info, &vk_buffer, &allocation, &allocation_info)
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
	g: ^Graphics,
	size: vk.DeviceSize,
	data: rawptr,
	usage: vk.BufferUsageFlags,
	dst_access_mask: vk.AccessFlags,
	dst_stage_mask: vk.PipelineStageFlags,
) -> Buffer {
	sc := _cmd_single_begin(g)

	// Staging buffer
	staging_buffer := _create_buffer(g, size, {.TRANSFER_SRC}, .AUTO, {.HOST_ACCESS_SEQUENTIAL_WRITE})
	_fill_buffer(g, &staging_buffer, size, data)
	_cmd_buffer_barrier(sc.command_buffer, staging_buffer, {.HOST_WRITE}, {.TRANSFER_READ}, {.HOST}, {.TRANSFER})
	defer destroy_buffer(g, &staging_buffer)

	// Result buffer
	buffer := _create_buffer(g, size, {.TRANSFER_DST} + usage, .AUTO_PREFER_DEVICE, {})
	_copy_buffer(g, sc.command_buffer, staging_buffer, buffer, size)
	_cmd_buffer_barrier(sc.command_buffer, buffer, {.TRANSFER_WRITE}, dst_access_mask, {.TRANSFER}, dst_stage_mask)

	_cmd_single_end(sc)

	return buffer
}

@(private = "file")
_create_mapped_buffer :: proc(
	g: ^Graphics,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	dst_access_mask: vk.AccessFlags,
	dst_stage_mask: vk.PipelineStageFlags,
) -> Buffer {
	buffer := _create_buffer(g, size, usage, .AUTO_PREFER_HOST, {.HOST_ACCESS_SEQUENTIAL_WRITE, .MAPPED}, {}, {})

	sc := _cmd_single_begin(g)

	must(vma.MapMemory(g.allocator, buffer.allocation, &buffer.mapped))
	_cmd_buffer_barrier(sc.command_buffer, buffer, {.HOST_WRITE}, dst_access_mask, {.HOST}, dst_stage_mask)

	_cmd_single_end(sc)

	return buffer
}
