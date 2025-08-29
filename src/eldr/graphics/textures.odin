package graphics

import "core:log"
import "core:math"
import "core:os"
import vk "vendor:vulkan"
import "vma"

create_texture :: proc(g: ^Graphics, image: Image, name: string = "empty", mip_levels: f32 = 0) -> Texture {
	levels: f32 = 0
	if mip_levels <= 0 {
		// levels = math.floor_f32(math.log2(cast(f32)max(image.width, image.height))) + 1
		levels = 11
	} else {
		levels = mip_levels
	}

	desired_channels: u32 = 4
	image_size := cast(vk.DeviceSize)(image.width * image.height * desired_channels)

	sc := _cmd_single_begin(g)

	// Staging Buffer
	staging_buffer := _create_buffer(g, image_size, {.TRANSFER_SRC}, .AUTO, {.HOST_ACCESS_SEQUENTIAL_WRITE})
	_fill_buffer(g, &staging_buffer, image_size, image.data)
	_cmd_buffer_barrier(sc.command_buffer, staging_buffer, {.HOST_WRITE}, {.TRANSFER_READ}, {.HOST}, {.TRANSFER})
	defer destroy_buffer(g, &staging_buffer)

	format: vk.Format = .R8G8B8A8_SRGB

	// Image
	vk_image, allocation, allocation_info := _create_image(
		g,
		image.width,
		image.height,
		cast(u32)levels,
		{._1},
		format,
		.OPTIMAL,
		{.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED},
		vma.MemoryUsage.AUTO_PREFER_DEVICE,
		vma.AllocationCreateFlags{},
	)

	_transition_image_layout(
		sc.command_buffer,
		vk_image,
		{.COLOR},
		format,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		cast(u32)levels,
	)
	_copy_buffer_to_image(sc.command_buffer, staging_buffer.buffer, vk_image, image.width, image.height)

	_generate_mipmaps(
		g,
		sc.command_buffer,
		vk_image,
		.R8G8B8A8_SRGB,
		cast(i32)image.width,
		cast(i32)image.height,
		cast(u32)levels,
	)

	_cmd_single_end(sc)

	// Image View
	image_view := _create_image_view(g.device, vk_image, format, {.COLOR}, cast(u32)levels)

	// Sampler
	sampler_info := vk.SamplerCreateInfo {
		sType                   = .SAMPLER_CREATE_INFO,
		magFilter               = .LINEAR,
		minFilter               = .LINEAR,
		addressModeU            = .REPEAT,
		addressModeV            = .REPEAT,
		addressModeW            = .REPEAT,
		anisotropyEnable        = true,
		maxAnisotropy           = g.physical_device_property.limits.maxSamplerAnisotropy,
		borderColor             = .INT_OPAQUE_BLACK,
		unnormalizedCoordinates = false,
		compareEnable           = false,
		compareOp               = .ALWAYS,
		mipmapMode              = .LINEAR,
		mipLodBias              = 0.0,
		minLod                  = 0.0,
		maxLod                  = cast(f32)levels,
	}

	sampler: vk.Sampler
	must(vk.CreateSampler(g.device, &sampler_info, nil, &sampler))

	return Texture {
		name = name,
		image = vk_image,
		view = image_view,
		sampler = sampler,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}

destroy_texture :: proc(g: ^Graphics, texture: ^Texture) {
	_destroy_texture_from_device(g.device, g.allocator, texture)
}

@(private)
_destroy_texture_from_device :: proc(device: vk.Device, allocator: vma.Allocator, texture: ^Texture) {
	vk.DestroySampler(device, texture.sampler, nil)
	vk.DestroyImageView(device, texture.view, nil)
	vma.DestroyImage(allocator, texture.image, texture.allocation)

	texture.sampler = 0
	texture.view = 0
	texture.image = 0
	texture.allocation_info = {}
}

@(private)
_transition_image_layout :: proc {
	_transition_image_layout_from_default,
	_transition_image_layout_from_cmd,
}

@(private)
_transition_image_layout_from_default :: proc(
	g: ^Graphics,
	image: vk.Image,
	aspect: vk.ImageAspectFlags,
	format: vk.Format,
	old_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
	mip_levels: u32,
) {
	sc := _cmd_single_begin(g)
	_transition_image_layout_from_cmd(sc.command_buffer, image, aspect, format, old_layout, new_layout, mip_levels)
	_cmd_single_end(sc)
}

@(private)
_transition_image_layout_from_cmd :: proc(
	command_buffer: vk.CommandBuffer,
	image: vk.Image,
	aspect: vk.ImageAspectFlags,
	format: vk.Format,
	old_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
	mip_levels: u32,
) {
	source_stage: vk.PipelineStageFlags
	destination_stage: vk.PipelineStageFlags

	barrier_src_access_mask: vk.AccessFlags
	barrier_dst_access_mask: vk.AccessFlags

	if old_layout == .UNDEFINED && new_layout == .TRANSFER_DST_OPTIMAL {
		barrier_src_access_mask = {}
		barrier_dst_access_mask = {.TRANSFER_WRITE}

		source_stage = {.TOP_OF_PIPE}
		destination_stage = {.TRANSFER}
	} else if old_layout == .TRANSFER_DST_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
		barrier_src_access_mask = {.TRANSFER_WRITE}
		barrier_dst_access_mask = {.SHADER_READ}

		source_stage = {.TRANSFER}
		destination_stage = {.FRAGMENT_SHADER}
	} else if old_layout == .UNDEFINED && new_layout == .DEPTH_STENCIL_ATTACHMENT_OPTIMAL {
		barrier_src_access_mask = {}
		barrier_dst_access_mask = {.DEPTH_STENCIL_ATTACHMENT_READ, .DEPTH_STENCIL_ATTACHMENT_WRITE}

		source_stage = {.TOP_OF_PIPE}
		destination_stage = {.EARLY_FRAGMENT_TESTS}
	} else {
		panic("unsuported layout transition!")
	}

	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		oldLayout = old_layout,
		newLayout = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask = aspect,
			baseMipLevel = 0,
			levelCount = mip_levels,
			baseArrayLayer = 0,
			layerCount = 1,
		},
		srcAccessMask = barrier_src_access_mask,
		dstAccessMask = barrier_dst_access_mask,
	}

	vk.CmdPipelineBarrier(command_buffer, source_stage, destination_stage, {}, {}, nil, 0, nil, 1, &barrier)
}

@(private)
_create_image :: proc {
	_create_image_from_graphics,
	_create_image_from_device,
}

@(private)
_create_image_from_graphics :: proc(
	g: ^Graphics,
	width, height, mip_levels: u32,
	num_samples: vk.SampleCountFlags,
	format: vk.Format,
	tiling: vk.ImageTiling,
	usage: vk.ImageUsageFlags,
	memory_usage: vma.MemoryUsage,
	memory_flags: vma.AllocationCreateFlags,
) -> (
	vk.Image,
	vma.Allocation,
	vma.AllocationInfo,
) {
	return _create_image_from_device(
		g.device,
		g.physical_device,
		g.allocator,
		width,
		height,
		mip_levels,
		num_samples,
		format,
		tiling,
		usage,
		memory_usage,
		memory_flags,
	)
}

@(private)
_create_image_from_device :: proc(
	device: vk.Device,
	physical_device: vk.PhysicalDevice,
	allocator: vma.Allocator,
	width, height, mip_levels: u32,
	num_samples: vk.SampleCountFlags,
	format: vk.Format,
	tiling: vk.ImageTiling,
	usage: vk.ImageUsageFlags,
	memory_usage: vma.MemoryUsage,
	memory_flags: vma.AllocationCreateFlags,
) -> (
	vk.Image,
	vma.Allocation,
	vma.AllocationInfo,
) {
	image_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		extent = vk.Extent3D{width = width, height = height, depth = 1},
		mipLevels = mip_levels,
		arrayLayers = 1,
		format = format,
		tiling = tiling,
		initialLayout = .UNDEFINED,
		usage = usage,
		sharingMode = .EXCLUSIVE,
		samples = num_samples,
		flags = {},
	}

	image: vk.Image

	allocation_create_info := vma.AllocationCreateInfo {
		usage = memory_usage,
		flags = memory_flags,
	}

	allocation: vma.Allocation
	allocation_info: vma.AllocationInfo

	must(vma.CreateImage(allocator, &image_info, &allocation_create_info, &image, &allocation, &allocation_info))

	return image, allocation, allocation_info
}

@(private)
_create_image_view :: proc(
	device: vk.Device,
	image: vk.Image,
	format: vk.Format,
	aspect: vk.ImageAspectFlags,
	mip_levels: u32,
) -> vk.ImageView {
	create_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = image,
		viewType = .D2,
		format = format,
		subresourceRange = {aspectMask = aspect, levelCount = mip_levels, layerCount = 1},
	}

	image_view: vk.ImageView

	must(vk.CreateImageView(device, &create_info, nil, &image_view), "failed to create texture image view!")

	return image_view
}

@(private = "file")
_copy_buffer_to_image :: proc(cmd: vk.CommandBuffer, buffer: vk.Buffer, image: vk.Image, width: u32, height: u32) {
	region := vk.BufferImageCopy {
		bufferOffset = 0,
		bufferRowLength = 0,
		bufferImageHeight = 0,
		imageSubresource = vk.ImageSubresourceLayers {
			aspectMask = {.COLOR},
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = 1,
		},
		imageOffset = vk.Offset3D{0, 0, 0},
		imageExtent = vk.Extent3D{width, height, 1},
	}

	vk.CmdCopyBufferToImage(cmd, buffer, image, .TRANSFER_DST_OPTIMAL, 1, &region)
}

@(private = "file")
_generate_mipmaps :: proc(
	g: ^Graphics,
	cmd: vk.CommandBuffer,
	image: vk.Image,
	format: vk.Format,
	tex_width: i32,
	tex_height: i32,
	mip_levels: u32,
) {
	format_properties := vk.FormatProperties{}
	vk.GetPhysicalDeviceFormatProperties(g.physical_device, format, &format_properties)
	if .SAMPLED_IMAGE_FILTER_LINEAR not_in format_properties.optimalTilingFeatures {
		log.error("texture image format does not support linear blitting!")
		return
	}

	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		image = image,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		subresourceRange = {aspectMask = {.COLOR}, baseArrayLayer = 0, layerCount = 1, levelCount = 1},
	}

	mip_width := tex_width
	mip_height := tex_height

	for i in 1 ..< mip_levels {
		barrier.subresourceRange.baseMipLevel = i - 1
		barrier.oldLayout = .TRANSFER_DST_OPTIMAL
		barrier.newLayout = .TRANSFER_SRC_OPTIMAL
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.TRANSFER_READ}

		vk.CmdPipelineBarrier(cmd, {.TRANSFER}, {.TRANSFER}, {}, 0, nil, 0, nil, 1, &barrier)

		blit := vk.ImageBlit {
			srcOffsets = {{0, 0, 0}, {mip_width, mip_height, 1}},
			srcSubresource = {aspectMask = {.COLOR}, mipLevel = i - 1, baseArrayLayer = 0, layerCount = 1},
			dstOffsets = {
				{0, 0, 0},
				{mip_width / 2 if mip_width > 1 else 1, mip_height / 2 if mip_height > 1 else 1, 1},
			},
			dstSubresource = {aspectMask = {.COLOR}, mipLevel = i, baseArrayLayer = 0, layerCount = 1},
		}

		vk.CmdBlitImage(cmd, image, .TRANSFER_SRC_OPTIMAL, image, .TRANSFER_DST_OPTIMAL, 1, &blit, .LINEAR)

		barrier.oldLayout = .TRANSFER_SRC_OPTIMAL
		barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
		barrier.srcAccessMask = {.TRANSFER_READ}
		barrier.dstAccessMask = {.SHADER_READ}

		vk.CmdPipelineBarrier(cmd, {.TRANSFER}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &barrier)

		if mip_width > 1 {
			mip_width /= 2
		}
		if mip_height > 1 {
			mip_height /= 2
		}
	}

	barrier.subresourceRange.baseMipLevel = mip_levels - 1
	barrier.oldLayout = .TRANSFER_DST_OPTIMAL
	barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
	barrier.srcAccessMask = {.TRANSFER_READ}
	barrier.dstAccessMask = {.SHADER_READ}

	vk.CmdPipelineBarrier(cmd, {.TRANSFER}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &barrier)
}
