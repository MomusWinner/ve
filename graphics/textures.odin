package graphics

import "core:log"
import "core:math"
import "core:os"
import vk "vendor:vulkan"
import "vma"

create_texture :: proc(
	image: Image,
	name: string = "empty",
	mip_levels: u32 = 0,
	anisotropy: f32 = 1,
	encoding: TextureEncoding = .sRGB,
	sampler_info: Sampler_Info = DEFAULT_SAMPLER_INFO,
	loc := #caller_location,
) -> Texture {
	assert_gfx_ctx(loc)

	desired_channels: u32 = image.channels
	image_size := cast(vk.DeviceSize)(image.width * image.height * desired_channels)

	sc := begin_single_cmd()

	// Staging Buffer
	staging_buffer := _create_buffer(image_size, {.TRANSFER_SRC}, .AUTO, {.HOST_ACCESS_SEQUENTIAL_WRITE})
	fill_buffer(&staging_buffer, image_size, image.data)
	_cmd_buffer_barrier(sc.cmd, staging_buffer, {.HOST_WRITE}, {.TRANSFER_READ}, {.HOST}, {.TRANSFER})
	defer destroy_buffer(&staging_buffer)

	format: vk.Format

	switch image.pixel {
	case .R8:
		switch encoding {
		case .Linear:
			format = .R8_UNORM
		case .sRGB:
			format = .R8_SRGB
		}
	case .RG8:
		switch encoding {
		case .Linear:
			format = .R8G8_UNORM
		case .sRGB:
			format = .R8G8_SRGB
		}
	case .RGB8:
		switch encoding {
		case .Linear:
			format = .R8G8B8_UNORM
		case .sRGB:
			format = .R8G8B8_SRGB
		}
	case .RGBA8:
		switch encoding {
		case .Linear:
			format = .R8G8B8A8_UNORM
		case .sRGB:
			format = .R8G8B8A8_SRGB
		}
	}

	// Image
	vk_image, allocation, allocation_info := _create_image(
		image.width,
		image.height,
		mip_levels,
		._1,
		format,
		.OPTIMAL,
		{.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED},
		vma.MemoryUsage.AUTO_PREFER_DEVICE,
		vma.AllocationCreateFlags{},
	)

	_transition_image_layout(sc.cmd, vk_image, {.COLOR}, format, .UNDEFINED, .TRANSFER_DST_OPTIMAL, mip_levels)
	_copy_buffer_to_image(sc.cmd, staging_buffer.buffer, vk_image, image.width, image.height)

	if mip_levels > 1 {
		_generate_mipmaps(sc.cmd, vk_image, format, cast(i32)image.width, cast(i32)image.height, mip_levels)
	}

	end_single_cmd(sc)

	image_view := _create_image_view(vk_image, format, {.COLOR}, mip_levels)
	sampler: vk.Sampler = create_sampler(sampler_info)

	return Texture {
		name = name,
		image = vk_image,
		view = image_view,
		format = format,
		sampler = sampler,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}

destroy_texture :: proc(texture: ^Texture, loc := #caller_location) {
	assert_not_nil(texture, loc)

	destroy_sampler(texture.sampler)
	vk.DestroyImageView(ctx.vulkan_state.device, texture.view, nil)
	vma.DestroyImage(ctx.vulkan_state.allocator, texture.image, texture.allocation)

	texture.sampler = 0
	texture.view = 0
	texture.image = 0
	texture.allocation_info = {}
}

create_sampler :: proc(info: Sampler_Info, loc := #caller_location) -> Sampler {
	max_anisotropy: f32 = ---
	if info.anisotropy_enable && info.max_anisotropy == 0 {
		max_anisotropy = ctx.limits.max_sampler_anisotropy
	} else {
		max_anisotropy = math.clamp(info.max_anisotropy, 0, ctx.limits.max_sampler_anisotropy)
	}

	sampler_info := vk.SamplerCreateInfo {
		sType                   = .SAMPLER_CREATE_INFO,
		magFilter               = _sampler_filter_to_vk(info.mag_filter),
		minFilter               = _sampler_filter_to_vk(info.min_filter),
		addressModeU            = _sampler_address_mode_to_vk(info.address_mode_u),
		addressModeV            = _sampler_address_mode_to_vk(info.address_mode_v),
		addressModeW            = _sampler_address_mode_to_vk(info.address_mode_w),
		anisotropyEnable        = cast(b32)info.anisotropy_enable,
		maxAnisotropy           = max_anisotropy,
		borderColor             = _sampler_border_color_to_vk(info.border_color),
		unnormalizedCoordinates = false,
		compareEnable           = false,
		compareOp               = .ALWAYS,
		mipmapMode              = _sampler_filter_to_vk_mipmap_mode(info.mipmap_mode),
		mipLodBias              = 0.0,
		minLod                  = info.lod_clamp.min,
		maxLod                  = info.lod_clamp.max,
	}

	sampler: Sampler
	must(vk.CreateSampler(ctx.vulkan_state.device, &sampler_info, nil, &sampler))

	return sampler
}

destroy_sampler :: proc(sampler: Sampler) {
	vk.DestroySampler(ctx.vulkan_state.device, sampler, nil)
}

@(private)
_sampler_filter_to_vk :: proc(f: Sampler_Filter) -> vk.Filter {
	switch f {
	case .Nearest:
		return .NEAREST
	case .Linear:
		return .LINEAR
	}

	return .NEAREST
}

@(private)
_sampler_filter_to_vk_mipmap_mode :: proc(f: Sampler_Filter) -> vk.SamplerMipmapMode {
	switch f {
	case .Nearest:
		return .NEAREST
	case .Linear:
		return .LINEAR
	}

	return .NEAREST
}

@(private)
_sampler_address_mode_to_vk :: proc(a: Sampler_Address_Mode) -> vk.SamplerAddressMode {
	switch a {
	case .Repeat:
		return .REPEAT
	case .Mirrored_Repeat:
		return .MIRRORED_REPEAT
	case .Clamp_To_Edge:
		return .CLAMP_TO_EDGE
	case .Clamp_To_Border:
		return .CLAMP_TO_BORDER
	case .Mirror_Clamp_To_Edge:
		return .MIRROR_CLAMP_TO_EDGE
	}

	return .REPEAT
}

@(private)
_sampler_border_color_to_vk :: proc(b: Sampler_Border_Color) -> vk.BorderColor {
	switch b {
	case .Transparent_Black:
		return .FLOAT_TRANSPARENT_BLACK
	case .Opaque_Black:
		return .FLOAT_OPAQUE_BLACK
	case .Opaque_White:
		return .FLOAT_OPAQUE_WHITE
	}

	return .FLOAT_TRANSPARENT_BLACK
}

@(private)
_transition_image_layout :: proc(
	command_buffer: vk.CommandBuffer,
	image: vk.Image,
	aspect: vk.ImageAspectFlags,
	format: vk.Format,
	old_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
	mip_levels: u32,
) {
	source_stage: vk.PipelineStageFlags2
	destination_stage: vk.PipelineStageFlags2

	barrier_src_access_mask: vk.AccessFlags2
	barrier_dst_access_mask: vk.AccessFlags2

	if old_layout == .UNDEFINED && new_layout == .TRANSFER_DST_OPTIMAL {
		barrier_src_access_mask = {}
		barrier_dst_access_mask = {.TRANSFER_WRITE}

		source_stage = {}
		destination_stage = {.TRANSFER}
	} else if old_layout == .TRANSFER_DST_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
		barrier_src_access_mask = {.TRANSFER_WRITE}
		barrier_dst_access_mask = {.SHADER_READ}

		source_stage = {.TRANSFER}
		destination_stage = {.FRAGMENT_SHADER}
	} else if old_layout == .UNDEFINED && new_layout == .DEPTH_STENCIL_ATTACHMENT_OPTIMAL {
		barrier_src_access_mask = {}
		barrier_dst_access_mask = {.DEPTH_STENCIL_ATTACHMENT_READ, .DEPTH_STENCIL_ATTACHMENT_WRITE}

		source_stage = {}
		destination_stage = {.EARLY_FRAGMENT_TESTS}
	} else if old_layout == .DEPTH_STENCIL_ATTACHMENT_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
		barrier_src_access_mask = {.DEPTH_STENCIL_ATTACHMENT_WRITE}
		barrier_dst_access_mask = {.SHADER_READ}

		source_stage = {.LATE_FRAGMENT_TESTS}
		destination_stage = {.FRAGMENT_SHADER}
	} else if old_layout == .SHADER_READ_ONLY_OPTIMAL && new_layout == .DEPTH_STENCIL_ATTACHMENT_OPTIMAL {
		barrier_src_access_mask = {.SHADER_READ}
		barrier_dst_access_mask = {.DEPTH_STENCIL_ATTACHMENT_WRITE}

		source_stage = {.FRAGMENT_SHADER}
		destination_stage = {.LATE_FRAGMENT_TESTS}
	} else if old_layout == .UNDEFINED && new_layout == .COLOR_ATTACHMENT_OPTIMAL {
		barrier_src_access_mask = {}
		barrier_dst_access_mask = {.COLOR_ATTACHMENT_WRITE}

		source_stage = {.TOP_OF_PIPE}
		destination_stage = {.COLOR_ATTACHMENT_OUTPUT}
	} else if old_layout == .COLOR_ATTACHMENT_OPTIMAL && new_layout == .PRESENT_SRC_KHR {
		barrier_src_access_mask = {.COLOR_ATTACHMENT_WRITE}
		barrier_dst_access_mask = {.MEMORY_READ}

		source_stage = {.COLOR_ATTACHMENT_OUTPUT}
		destination_stage = {.BOTTOM_OF_PIPE}
	} else if old_layout == .COLOR_ATTACHMENT_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
		barrier_src_access_mask = {.COLOR_ATTACHMENT_WRITE}
		barrier_dst_access_mask = {.MEMORY_READ}

		source_stage = {.COLOR_ATTACHMENT_OUTPUT}
		destination_stage = {.FRAGMENT_SHADER}
	} else if old_layout == .SHADER_READ_ONLY_OPTIMAL && new_layout == .COLOR_ATTACHMENT_OPTIMAL {
		barrier_src_access_mask = {.MEMORY_READ}
		barrier_dst_access_mask = {.COLOR_ATTACHMENT_WRITE}

		source_stage = {.FRAGMENT_SHADER}
		destination_stage = {.COLOR_ATTACHMENT_OUTPUT}
	} else {
		log.panicf("unsuported layout transition!\nold_layout %v \nnew_layout: %v", old_layout, new_layout)
	}

	barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
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
		srcStageMask = source_stage,
		srcAccessMask = barrier_src_access_mask,
		dstAccessMask = barrier_dst_access_mask,
		dstStageMask = destination_stage,
	}

	dependency_info := vk.DependencyInfo {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &barrier,
		dependencyFlags         = {},
	}

	vk.CmdPipelineBarrier2(command_buffer, &dependency_info)
}

@(private)
_create_image :: proc(
	width, height, mip_levels: u32,
	sample_count: Sample_Count_Flag,
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
		samples = {sample_count},
		flags = {},
	}

	image: vk.Image

	allocation_create_info := vma.AllocationCreateInfo {
		usage = memory_usage,
		flags = memory_flags,
	}

	allocation: vma.Allocation
	allocation_info: vma.AllocationInfo

	must(
		vma.CreateImage(
			ctx.vulkan_state.allocator,
			&image_info,
			&allocation_create_info,
			&image,
			&allocation,
			&allocation_info,
		),
	)

	return image, allocation, allocation_info
}

@(private)
_create_image_view :: proc(
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

	must(
		vk.CreateImageView(ctx.vulkan_state.device, &create_info, nil, &image_view),
		"failed to create texture image view!",
	)

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
	cmd: vk.CommandBuffer,
	image: vk.Image,
	format: vk.Format,
	tex_width: i32,
	tex_height: i32,
	mip_levels: u32,
	loc := #caller_location,
) {
	assert_gfx_ctx(loc)

	format_properties := vk.FormatProperties{}
	vk.GetPhysicalDeviceFormatProperties(ctx.vulkan_state.physical_device, format, &format_properties)
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
