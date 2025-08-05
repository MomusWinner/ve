package graphics

import "core:log"
import "core:math"
import "core:os"
import vk "vendor:vulkan"

TextureImage :: struct {
	image:  vk.Image,
	view:   vk.ImageView,
	memory: vk.DeviceMemory,
}

Texture :: struct {
	image:   TextureImage,
	sampler: vk.Sampler,
}

create_image_view :: proc(
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

_transition_image_layout :: proc {
	_transition_image_layout_from_graphics,
	_transition_image_layout_from_command_buffer,
}

_transition_image_layout_from_graphics :: proc(
	g: ^Graphics,
	image: vk.Image,
	aspect: vk.ImageAspectFlags,
	format: vk.Format,
	old_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
	mip_levels: u32,
) {
	sc := _begin_single_command(g)
	_transition_image_layout_from_command_buffer(
		sc.command_buffer,
		image,
		aspect,
		format,
		old_layout,
		new_layout,
		mip_levels,
	)
	_end_single_command(sc)
}

_transition_image_layout_from_command_buffer :: proc(
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

copy_buffer_to_image :: proc(g: ^Graphics, buffer: vk.Buffer, image: vk.Image, width: u32, height: u32) {
	sc := _begin_single_command(g)
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

	vk.CmdCopyBufferToImage(sc.command_buffer, buffer, image, .TRANSFER_DST_OPTIMAL, 1, &region)

	_end_single_command(sc)
}

_create_image :: proc {
	_create_image_from_graphics,
	_create_image_from_device,
}

_create_image_from_graphics :: proc(
	g: ^Graphics,
	width, height, mip_levels: u32,
	num_samples: vk.SampleCountFlags,
	format: vk.Format,
	tiling: vk.ImageTiling,
	usage: vk.ImageUsageFlags,
	memory_properties: vk.MemoryPropertyFlags,
) -> (
	vk.Image,
	vk.DeviceMemory,
) {
	return _create_image_from_device(
		g.device,
		g.physical_device,
		width,
		height,
		mip_levels,
		num_samples,
		format,
		tiling,
		usage,
		memory_properties,
	)
}

_create_image_from_device :: proc(
	device: vk.Device,
	physical_device: vk.PhysicalDevice,
	width, height, mip_levels: u32,
	num_samples: vk.SampleCountFlags,
	format: vk.Format,
	tiling: vk.ImageTiling,
	usage: vk.ImageUsageFlags,
	memory_properties: vk.MemoryPropertyFlags,
) -> (
	vk.Image,
	vk.DeviceMemory,
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

	must(vk.CreateImage(device, &image_info, nil, &image))

	// Allocating memory
	memory_requirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(device, image, &memory_requirements)

	memory_type, ok := find_memory_type(physical_device, memory_requirements.memoryTypeBits, memory_properties)

	if !ok {
		log.error("Couln't fine memory for image creationg")
		return 0, 0
	}

	allocate_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = memory_requirements.size,
		memoryTypeIndex = memory_type,
	}

	image_memory: vk.DeviceMemory

	must(vk.AllocateMemory(device, &allocate_info, nil, &image_memory))

	vk.BindImageMemory(device, image, image_memory, 0)

	return image, image_memory
}

generate_mipmaps :: proc(
	g: ^Graphics,
	image: vk.Image,
	format: vk.Format,
	tex_width: i32,
	tex_height: i32,
	mip_levels: u32,
) {
	format_properties := vk.FormatProperties{}
	vk.GetPhysicalDeviceFormatProperties(g.physical_device, format, &format_properties) // TODO: get cashed data
	if .SAMPLED_IMAGE_FILTER_LINEAR not_in format_properties.optimalTilingFeatures {
		log.error("texture image format does not support linear blitting!")
		return
	}

	sc := _begin_single_command(g)

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

		vk.CmdPipelineBarrier(sc.command_buffer, {.TRANSFER}, {.TRANSFER}, {}, 0, nil, 0, nil, 1, &barrier)

		blit := vk.ImageBlit {
			srcOffsets = {{0, 0, 0}, {mip_width, mip_height, 1}},
			srcSubresource = {aspectMask = {.COLOR}, mipLevel = i - 1, baseArrayLayer = 0, layerCount = 1},
			dstOffsets = {
				{0, 0, 0},
				{mip_width / 2 if mip_width > 1 else 1, mip_height / 2 if mip_height > 1 else 1, 1},
			},
			dstSubresource = {aspectMask = {.COLOR}, mipLevel = i, baseArrayLayer = 0, layerCount = 1},
		}

		vk.CmdBlitImage(
			sc.command_buffer,
			image,
			.TRANSFER_SRC_OPTIMAL,
			image,
			.TRANSFER_DST_OPTIMAL,
			1,
			&blit,
			.LINEAR,
		)


		barrier.oldLayout = .TRANSFER_SRC_OPTIMAL
		barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
		barrier.srcAccessMask = {.TRANSFER_READ}
		barrier.dstAccessMask = {.SHADER_READ}

		vk.CmdPipelineBarrier(sc.command_buffer, {.TRANSFER}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &barrier)

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

	vk.CmdPipelineBarrier(sc.command_buffer, {.TRANSFER}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &barrier)

	_end_single_command(sc)
}

create_texture_image :: proc(g: ^Graphics, image: Image, mip_levels: u32 = 1) -> TextureImage {
	desired_channels: u32 = 4
	image_size := cast(vk.DeviceSize)(image.width * image.height * desired_channels)

	staging_buffer := create_buffer(g, cast(vk.DeviceSize)image_size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT})
	defer destroy_buffer(g, &staging_buffer)

	fill_buffer(g, staging_buffer, image_size, image.data)

	format: vk.Format = .R8G8B8A8_SRGB

	// Create Vulkan Image
	vk_image, vk_memory := _create_image(
		g,
		image.width,
		image.height,
		mip_levels,
		{._1},
		format,
		.OPTIMAL,
		{.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED},
		{.DEVICE_LOCAL},
	)

	_transition_image_layout(g, vk_image, {.COLOR}, format, .UNDEFINED, .TRANSFER_DST_OPTIMAL, mip_levels)
	copy_buffer_to_image(g, staging_buffer.buffer, vk_image, image.width, image.height)

	generate_mipmaps(g, vk_image, .R8G8B8A8_SRGB, cast(i32)image.width, cast(i32)image.height, mip_levels)

	image_view := create_image_view(g.device, vk_image, format, {.COLOR}, mip_levels)

	return TextureImage{image = vk_image, memory = vk_memory, view = image_view}
}

destroy_texture_image :: proc(device: vk.Device, image: ^TextureImage) {
	vk.DestroyImageView(device, image.view, nil)
	vk.DestroyImage(device, image.image, nil)
	vk.FreeMemory(device, image.memory, nil)
	image.view = 0
	image.image = 0
	image.memory = 0
}

create_texture :: proc(g: ^Graphics, image: Image, mip_levels: f32 = 0) -> Texture {
	levels: f32 = 0
	if mip_levels <= 0 {
		// levels = math.floor_f32(math.log2(cast(f32)max(image.width, image.height))) + 1
		levels = 1
	} else {
		levels = mip_levels
	}

	image := create_texture_image(g, image, cast(u32)levels)

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

	return Texture{image = image, sampler = sampler}
}

destroy_texture :: proc(g: ^Graphics, texture: ^Texture) {
	vk.DestroySampler(g.device, texture.sampler, nil)
	texture.sampler = 0
	destroy_texture_image(g.device, &texture.image)
}
