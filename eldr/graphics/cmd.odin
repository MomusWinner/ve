package graphics

import vk "vendor:vulkan"

cmd_bind_vertex_buffer :: proc(
	frame_data: Frame_Data,
	buffer: Buffer,
	offset := vk.DeviceSize{},
	loc := #caller_location,
) {
	assert(.VERTEX_BUFFER in buffer.usage, loc = loc)

	offset := offset
	buffer := buffer

	vk.CmdBindVertexBuffers(frame_data.cmd, 0, 1, &buffer.buffer, &offset)
}

cmd_bind_index_buffer :: proc(
	frame_data: Frame_Data,
	buffer: Buffer,
	offset := vk.DeviceSize{},
	index_type := vk.IndexType.UINT16,
	loc := #caller_location,
) {
	assert(.INDEX_BUFFER in buffer.usage, loc = loc)

	offset := offset
	buffer := buffer

	vk.CmdBindIndexBuffer(frame_data.cmd, buffer.buffer, offset, index_type)
}

cmd_push_constants :: proc(frame_data: Frame_Data, pipeline: Pipeline, const: ^$T, loc := #caller_location) {
	assert_frame_data(frame_data, loc)
	layout := get_pipeline_layout(pipeline.layout)

	vk.CmdPushConstants(frame_data.cmd, layout, vk.ShaderStageFlags_ALL_GRAPHICS, 0, size_of(const^), const)
}

cmd_draw :: proc(frame_data: Frame_Data, vertex_count: u32, instance_count: u32 = 1, loc := #caller_location) {
	assert_frame_data(frame_data, loc)

	vk.CmdDraw(frame_data.cmd, vertex_count, instance_count, 0, 0)
}

cmd_draw_indexed :: proc(frame_data: Frame_Data, vertex_count: u32, instance_count: u32 = 1, loc := #caller_location) {
	assert_frame_data(frame_data, loc)

	vk.CmdDrawIndexed(frame_data.cmd, vertex_count, 1, 0, 0, 0)
}

cmd_bind_render_pipeline :: proc(
	frame_data: Frame_Data,
	pipeline: ^Render_Pipeline,
	loc := #caller_location,
) -> Graphics_Pipeline {
	assert_frame_data(frame_data, loc)

	g_pipeline := render_pipeline_get_pipeline(pipeline, frame_data.surface_info)
	vk.CmdBindPipeline(frame_data.cmd, .GRAPHICS, g_pipeline.pipeline)

	return g_pipeline
}

cmd_bind_compute_pipeline :: proc(pipeline: Compute_Pipeline, frame_data: Frame_Data, loc := #caller_location) {
	assert_frame_data(frame_data, loc)

	vk.CmdBindPipeline(frame_data.cmd, .COMPUTE, pipeline.pipeline)
}

cmd_bind_descriptor_set_graphics :: proc(
	frame_data: Frame_Data,
	pipeline: ^Pipeline,
	descriptor_sets: ..vk.DescriptorSet,
	// loc := #caller_location,
) {
	_cmd_bind_descriptor_set(frame_data, .GRAPHICS, pipeline, descriptor_sets)
}

cmd_bind_descriptor_set_compute :: proc(
	frame_data: Frame_Data,
	pipeline: ^Pipeline,
	descriptor_sets: ..vk.DescriptorSet,
	loc := #caller_location,
) {
	_cmd_bind_descriptor_set(frame_data, .COMPUTE, pipeline, descriptor_sets, loc)
}

@(private = "file")
_cmd_bind_descriptor_set :: proc(
	frame_data: Frame_Data,
	bind_point: vk.PipelineBindPoint,
	pipeline: ^Pipeline,
	descriptor_sets: []vk.DescriptorSet,
	loc := #caller_location,
) {
	assert_gfx_ctx(loc)

	layout := get_pipeline_layout(pipeline.layout)

	vk.CmdBindDescriptorSets(
		frame_data.cmd,
		bind_point,
		layout,
		0,
		cast(u32)len(descriptor_sets),
		raw_data(descriptor_sets),
		0,
		nil,
	)
}

@(private)
@(require_results)
_cmd_single_begin :: proc() -> SingleCommand {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = ctx.vulkan_state.command_pool,
		commandBufferCount = 1,
	}

	command_buffer: vk.CommandBuffer
	must(vk.AllocateCommandBuffers(ctx.vulkan_state.device, &alloc_info, &command_buffer))

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	must(vk.BeginCommandBuffer(command_buffer, &begin_info))

	return SingleCommand{cmd = command_buffer}
}

@(private)
_cmd_single_end :: proc(single_command: SingleCommand) {
	command_buffer := single_command.cmd

	must(vk.EndCommandBuffer(command_buffer))

	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &command_buffer,
	}

	must(vk.QueueSubmit(ctx.vulkan_state.graphics_queue, 1, &submit_info, 0))
	must(vk.QueueWaitIdle(ctx.vulkan_state.graphics_queue))

	vk.FreeCommandBuffers(ctx.vulkan_state.device, ctx.vulkan_state.command_pool, 1, &command_buffer)
}

@(private)
_cmd_buffer_barrier :: proc(
	cmd: vk.CommandBuffer,
	buffer: Buffer,
	src_access_mask: vk.AccessFlags,
	dst_access_mask: vk.AccessFlags,
	src_stage_mask: vk.PipelineStageFlags,
	dst_stage_mask: vk.PipelineStageFlags,
) {
	buffer_barrier := vk.BufferMemoryBarrier {
		sType               = .BUFFER_MEMORY_BARRIER,
		srcAccessMask       = src_access_mask,
		dstAccessMask       = dst_access_mask,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		buffer              = buffer.buffer,
		offset              = 0,
		size                = cast(vk.DeviceSize)vk.WHOLE_SIZE,
	}
	vk.CmdPipelineBarrier(cmd, src_stage_mask, dst_stage_mask, {}, 0, nil, 1, &buffer_barrier, 0, nil)
}
