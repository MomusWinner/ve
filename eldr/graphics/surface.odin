package graphics

import hm "../handle_map/"
import "base:runtime"
import sm "core:container/small_array"
import "core:log"
import "core:mem"
import "core:time"
import vk "vendor:vulkan"
import "vma"

create_surface_fit_screen :: proc(
	sample_count: Sample_Count_Flag = ._1,
	anisotropy: f32 = 1,
	allocator := context.allocator,
	loc := #caller_location,
) -> Surface_Handle {
	assert_gfx_ctx(loc)
	surface := Surface{}
	_surface_init_fit_screen(&surface, sample_count, anisotropy)

	return _surface_manager_add_surface(ctx.surface_manager, surface)
}

create_surface_with_size :: proc(
	width, height: u32,
	sample_count: Sample_Count_Flag = ._1,
	anisotropy: f32 = 1,
	allocator := context.allocator,
	loc := #caller_location,
) -> Surface_Handle {
	assert_gfx_ctx(loc)
	assert(width > 0 && height > 0, "Surface dimensions must be greater than zero", loc)
	surface := Surface{}
	_surface_init_with_size(&surface, width, height, sample_count, anisotropy)

	return _surface_manager_add_surface(ctx.surface_manager, surface)
}

destroy_surface :: proc(surface_h: Surface_Handle, loc := #caller_location) {
	assert_gfx_ctx(loc)

	_surface_manager_destroy_surface(ctx.surface_manager, surface_h, loc)
}

@(require_results)
get_surface :: proc(surface_h: Surface_Handle, loc := #caller_location) -> (^Surface, bool) {
	assert_gfx_ctx(loc)

	return _surface_manager_get_surface(ctx.surface_manager, surface_h, loc)
}

surface_add_color_attachment :: proc(
	surface: ^Surface,
	clear_value: color = {0.01, 0.01, 0.01, 1.0},
	loc := #caller_location,
) -> Texture_Handle {
	assert_gfx_ctx(loc)
	assert_not_nil(surface, loc)
	_, has_color_attachment := surface.color_attachment.?
	assert(has_color_attachment == false, "Surface already has a color attachment.", loc)

	w, h := surface.width, surface.height

	color_attachment := Surface_Color_Attachment{}
	if surface.sample_count == ._1 {
		color_res := _create_surface_color_resolve_resource(w, h, surface.anisotropy, ctx.swapchain.format.format)

		color_attachment.texture_h = bindless_store_texture(color_res, loc)

		color_attachment.info = {
			sType = .RENDERING_ATTACHMENT_INFO,
			pNext = nil,
			imageView = color_res.view,
			imageLayout = .ATTACHMENT_OPTIMAL,
			resolveMode = {},
			loadOp = .CLEAR,
			storeOp = .STORE,
			clearValue = vk.ClearValue{color = {float32 = clear_value}},
		}
	} else {
		msaa := _create_surface_color_resource(w, h, ctx.swapchain.format.format, surface.sample_count)
		resolve := _create_surface_color_resolve_resource(w, h, surface.anisotropy, ctx.swapchain.format.format)

		color_attachment.texture_h = bindless_store_texture(resolve)
		color_attachment.msaa_texture = msaa

		color_attachment.info = {
			sType = .RENDERING_ATTACHMENT_INFO,
			pNext = nil,
			imageView = msaa.view,
			imageLayout = .ATTACHMENT_OPTIMAL,
			resolveMode = {.AVERAGE_KHR},
			resolveImageView = resolve.view,
			resolveImageLayout = .GENERAL,
			loadOp = .CLEAR,
			storeOp = .STORE,
			clearValue = vk.ClearValue{color = {float32 = clear_value}},
		}
	}

	surface.color_attachment = color_attachment

	return color_attachment.texture_h
}

surface_add_depth_attachment :: proc(surface: ^Surface, clear_value: f32 = 1, loc := #caller_location) {
	assert_not_nil(surface, loc)
	_, has_depth_attachment := surface.depth_attachment.?
	assert(has_depth_attachment == false, "Surface already has a depth attachment.", loc)

	width, height := surface.width, surface.height

	sc := begin_single_cmd()
	depth_resource := _create_surface_depth_resource(width, height, sc.cmd, surface.sample_count)
	end_single_cmd(sc)

	depth_attachment := Surface_Common_Depth_Attachment {
		resource = depth_resource,
		info = {
			sType = .RENDERING_ATTACHMENT_INFO,
			pNext = nil,
			imageView = depth_resource.view,
			imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
			loadOp = .CLEAR,
			storeOp = .DONT_CARE,
			clearValue = vk.ClearValue{depthStencil = {clear_value, 0}},
		},
	}
	surface.depth_attachment = depth_attachment
}

surface_add_readable_depth_attachment :: proc(
	surface: ^Surface,
	clear_value: f32 = 1,
	loc := #caller_location,
) -> Texture_Handle {
	assert_not_nil(surface, loc)
	_, has_depth_attachment := surface.depth_attachment.?
	assert(has_depth_attachment == false, "Surface already has a depth attachment.", loc)

	w, h := surface.width, surface.height

	depth_attachment := Surface_Readable_Depth_Attachment{}

	sc := begin_single_cmd()
	depth_resource := _create_surface_depth_resource_sampled(w, h, sc.cmd)
	depth_attachment.texture_h = bindless_store_texture(depth_resource)

	if surface.sample_count == ._1 {
		depth_attachment.info = {
			sType = .RENDERING_ATTACHMENT_INFO,
			pNext = nil,
			imageView = depth_resource.view,
			imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
			loadOp = .CLEAR,
			storeOp = .STORE,
			clearValue = vk.ClearValue{depthStencil = {clear_value, 0}},
		}
	} else {
		msaa := _create_surface_depth_resource(w, h, sc.cmd, surface.sample_count)
		depth_attachment.msaa_texture = msaa
		depth_attachment.info = {
			sType = .RENDERING_ATTACHMENT_INFO,
			pNext = nil,
			imageView = msaa.view,
			imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
			resolveMode = {.AVERAGE_KHR},
			resolveImageView = depth_resource.view,
			resolveImageLayout = .GENERAL,
			loadOp = .CLEAR,
			storeOp = .STORE,
			clearValue = vk.ClearValue{depthStencil = {clear_value, 0}},
		}
	}
	end_single_cmd(sc)

	surface.depth_attachment = depth_attachment

	return depth_attachment.texture_h
}

@(require_results)
begin_surface :: proc(surface: ^Surface, frame_data: Frame_Data, loc := #caller_location) -> Frame_Data {
	assert_not_nil(surface, loc)

	cmd := frame_data.cmd

	color_attachment, has_color_attachment := surface.color_attachment.?
	depth_attachment, has_depth_attachment := surface.depth_attachment.?
	assert(has_color_attachment || has_depth_attachment, "Couldn't begin_surface() without attachments")

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}

	p_color_attachment: ^vk.RenderingAttachmentInfo = nil
	p_depth_attachment: ^vk.RenderingAttachmentInfo = nil

	if has_color_attachment {
		msaa, has_msaa := color_attachment.msaa_texture.?

		if has_msaa {
			_transition_image_layout(cmd, msaa.image, {.COLOR}, msaa.format, .UNDEFINED, .COLOR_ATTACHMENT_OPTIMAL, 1)
		} else {
			texture, ok := bindless_get_texture(color_attachment.texture_h, loc)
			assert(ok)
			_transition_image_layout(
				cmd,
				texture.image,
				{.COLOR},
				texture.format,
				.UNDEFINED,
				.COLOR_ATTACHMENT_OPTIMAL,
				1,
			)
		}

		p_color_attachment = &color_attachment.info
	}

	depth_format: vk.Format
	if has_depth_attachment {
		switch &attachment in depth_attachment {
		case Surface_Common_Depth_Attachment:
			p_depth_attachment = &attachment.info
			depth_format = attachment.resource.format
		case Surface_Readable_Depth_Attachment:
			p_depth_attachment = &attachment.info
			msaa, has_msaa := attachment.msaa_texture.?

			texture, ok := bindless_get_texture(attachment.texture_h)
			assert(ok)
			depth_format = texture.format
			target: ^Texture = &msaa if has_msaa else texture

			_transition_image_layout(
				frame_data.cmd,
				target.image,
				{.DEPTH},
				target.format,
				.SHADER_READ_ONLY_OPTIMAL,
				.DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
				1,
			)
		}
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = {width = surface.width, height = surface.height}},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = p_color_attachment,
		pDepthAttachment = p_depth_attachment,
	}

	vk.CmdBeginRendering(cmd, &rendering_info)

	frame_data := frame_data
	frame_data.surface_info = Surface_Info {
		type         = .Surface,
		sample_count = surface.sample_count,
		depth_format = depth_format if has_depth_attachment else .UNDEFINED,
	}

	if (has_color_attachment) {
		texture, ok := bindless_get_texture(color_attachment.texture_h)
		assert(ok)
		sm.push(&frame_data.surface_info.color_formats, texture.format)
	}

	return frame_data
}

end_surface :: proc(surface: ^Surface, frame_data: Frame_Data, loc := #caller_location) {
	assert_not_nil(surface, loc)

	vk.CmdEndRendering(frame_data.cmd)

	color_attachment, has_color_attachment := surface.color_attachment.?
	depth_attachment, has_depth_attachment := surface.depth_attachment.?

	if has_color_attachment {
		msaa, has_msaa := color_attachment.msaa_texture.?
		texture, ok := bindless_get_texture(color_attachment.texture_h, loc)
		assert(ok)

		target := &msaa if has_msaa else texture
		_transition_image_layout(
			frame_data.cmd,
			target.image,
			{.COLOR},
			target.format,
			.COLOR_ATTACHMENT_OPTIMAL,
			.SHADER_READ_ONLY_OPTIMAL,
			1,
		)
	}

	if has_depth_attachment {
		switch attachment in depth_attachment {
		case Surface_Common_Depth_Attachment:
		case Surface_Readable_Depth_Attachment:
			texture, ok := bindless_get_texture(attachment.texture_h)
			msaa, has_msaa := attachment.msaa_texture.?
			assert(ok)

			sc := begin_single_cmd()
			target := &msaa if has_msaa else texture

			_transition_image_layout(
				sc.cmd,
				target.image,
				{.DEPTH},
				target.format,
				.DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
				.SHADER_READ_ONLY_OPTIMAL,
				1,
			)
			end_single_cmd(sc)
		}
	}
}

draw_surface_on_unit_square :: proc(
	surface: ^Surface,
	camera: ^Camera,
	frame_data: Frame_Data,
	material: ^Material,
	loc := #caller_location,
) {
	assert_gfx_ctx(loc)
	assert_not_nil(surface, loc)

	draw_surface(surface, camera, frame_data, material, &ctx.buildin.unit_square, loc)
}

draw_surface :: proc(
	surface: ^Surface,
	camera: ^Camera,
	frame_data: Frame_Data,
	material: ^Material,
	mesh: ^Mesh,
	loc := #caller_location,
) {
	assert_gfx_ctx(loc)
	assert_not_nil(surface, loc)

	color_attachment, has_color := surface.color_attachment.?
	assert(has_color, loc = loc)

	draw_mesh(frame_data, mesh, material, camera, &surface.transform, {}, true, loc)
}

surface_resize :: proc(surface: ^Surface, width, height: u32, loc := #caller_location) {
	assert(surface.fit_screen == false, "Manual resize not allowed on fit_screen surfaces.")
	_surface_resize(surface, width, height, loc)
}


@(private)
_init_surface_manager :: proc() {
	assert(ctx.surface_manager == nil)
	ctx.surface_manager = new(Surface_Manager)
	_surface_manager_init(ctx.surface_manager)
}

@(private)
_destroy_surface_manager :: proc(loc := #caller_location) {
	_surface_manager_destroy(ctx.surface_manager, loc)
	free(ctx.surface_manager)
}

@(private = "file")
_surface_manager_init :: proc(sm: ^Surface_Manager, loc := #caller_location) {
	assert_not_nil(sm, loc)
}

@(private = "file")
_surface_manager_destroy :: proc(sm: ^Surface_Manager, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(sm, loc)

	for &surface in sm.surfaces.values {
		_surface_destroy(&surface)
	}

	hm.destroy(&sm.surfaces)
}

@(private)
@(require_results)
_surface_manager_add_surface :: proc(
	sm: ^Surface_Manager,
	surface: Surface,
	loc := #caller_location,
) -> Surface_Handle {
	assert_gfx_ctx(loc)
	assert_not_nil(sm, loc)

	return hm.insert(&sm.surfaces, surface)
}

@(private)
@(require_results)
_surface_manager_get_surface :: proc(
	sm: ^Surface_Manager,
	surface_h: Surface_Handle,
	loc := #caller_location,
) -> (
	^Surface,
	bool,
) {
	assert_not_nil(sm, loc)

	return hm.get(&sm.surfaces, surface_h)
}

@(private)
_surface_manager_destroy_surface :: proc(sm: ^Surface_Manager, surface_h: Surface_Handle, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(sm, loc)

	surface, ok := hm.remove(&sm.surfaces, surface_h)

	if ok {
		_surface_destroy(&surface)
	}
}

@(private)
_surface_manager_resize_fit_screen_surfaces :: proc(sm: ^Surface_Manager, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(sm, loc)

	must(vk.QueueWaitIdle(ctx.vulkan_state.graphics_queue))
	w, h := get_screen_width(), get_screen_height()
	for &surface in sm.surfaces.values {
		if surface.fit_screen {
			_surface_resize(&surface, w, h)
		}
	}
}

@(private)
_surface_init_fit_screen :: proc(
	surface: ^Surface,
	sample_count: Sample_Count_Flag,
	anisotropy: f32,
	allocator := context.allocator,
	loc := #caller_location,
) {
	assert_not_nil(surface, loc)
	assert_gfx_ctx(loc)

	surface.fit_screen = true
	surface.width = get_device_width()
	surface.height = get_device_height()

	init_gfx_trf(&surface.transform)

	surface.sample_count = sample_count
	surface.anisotropy = anisotropy
}

@(private)
_surface_init_with_size :: proc(
	surface: ^Surface,
	width, height: u32,
	sample_count: Sample_Count_Flag,
	anisotropy: f32,
	allocator := context.allocator,
	loc := #caller_location,
) {
	assert_not_nil(surface, loc)
	assert_gfx_ctx(loc)

	surface.width = width
	surface.height = height

	init_gfx_trf(&surface.transform)

	surface.sample_count = sample_count
	surface.anisotropy = anisotropy
}

@(private)
_surface_destroy :: proc(surface: ^Surface, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(surface, loc)

	color_attachment, has_color_attachment := surface.color_attachment.?
	depth_attachment, has_depth_attachment := surface.depth_attachment.?

	if has_color_attachment {
		bindless_destroy_texture(color_attachment.texture_h)
		msaa, has_msaa := color_attachment.msaa_texture.?
		if has_msaa {
			destroy_texture(&msaa)
		}
	}

	if has_depth_attachment {
		switch &attachment in depth_attachment {
		case Surface_Common_Depth_Attachment:
			destroy_texture(&attachment.resource)
		case Surface_Readable_Depth_Attachment:
			bindless_destroy_texture(attachment.texture_h)
			msaa, has_msaa := attachment.msaa_texture.?
			if has_msaa {
				destroy_texture(&msaa)
			}
		}
	}
}

@(private = "file")
_surface_resize :: proc(surface: ^Surface, width, height: u32, loc := #caller_location) {
	surface.width = width
	surface.height = height

	color_attachment, has_color_attachment := surface.color_attachment.?
	depth_attachment, has_depth_attachment := surface.depth_attachment.?

	if has_color_attachment {
		_surface_resize_color_attachment(width, height, surface)
	}

	if has_depth_attachment {
		switch &attachment in depth_attachment {
		case Surface_Common_Depth_Attachment:
			destroy_texture(&attachment.resource)
			surface_add_depth_attachment(surface)
		case Surface_Readable_Depth_Attachment:
			_surface_resize_readable_depth_attachment(width, height, surface)
		}
	}
}

@(private = "file")
@(require_results)
_create_surface_color_resource :: proc(
	width, height: u32,
	format: vk.Format,
	sample_count: Sample_Count_Flag,
	loc := #caller_location,
) -> Texture {
	image, allocation, allocation_info := _create_image(
		width,
		height,
		1,
		sample_count,
		format,
		.OPTIMAL,
		{.COLOR_ATTACHMENT, .SAMPLED},
		.AUTO_PREFER_DEVICE,
		{},
	)

	view := _create_image_view(image, format, {.COLOR}, 1)

	_set_debug_object_name(cast(u64)image, .IMAGE, "surface msaa image")
	_set_debug_object_name(cast(u64)view, .IMAGE_VIEW, "surface msaa view")

	return Texture {
		name = "surface color attachment",
		image = image,
		view = view,
		format = format,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}

@(private = "file")
@(require_results)
_create_surface_color_resolve_resource :: proc(
	width, height: u32,
	sampler_anisotropy: f32,
	format: vk.Format,
	loc := #caller_location,
) -> Texture {
	image, allocation, allocation_info := _create_image(
		width,
		height,
		1,
		._1,
		format,
		.OPTIMAL,
		{.COLOR_ATTACHMENT, .SAMPLED},
		.AUTO_PREFER_DEVICE,
		{},
	)

	view := _create_image_view(image, format, {.COLOR}, 1)

	sampler_info := vk.SamplerCreateInfo {
		sType                   = .SAMPLER_CREATE_INFO,
		magFilter               = .LINEAR,
		minFilter               = .LINEAR,
		addressModeU            = .REPEAT,
		addressModeV            = .REPEAT,
		addressModeW            = .REPEAT,
		anisotropyEnable        = true,
		maxAnisotropy           = sampler_anisotropy,
		borderColor             = .INT_OPAQUE_BLACK,
		unnormalizedCoordinates = false,
		compareEnable           = false,
		compareOp               = .ALWAYS,
		mipmapMode              = .LINEAR,
		mipLodBias              = 0.0,
		minLod                  = 0.0,
		maxLod                  = cast(f32)1,
	}

	sampler: vk.Sampler
	must(vk.CreateSampler(ctx.vulkan_state.device, &sampler_info, nil, &sampler))

	_set_debug_object_name(cast(u64)image, .IMAGE, "surface resolve image")
	_set_debug_object_name(cast(u64)sampler, .SAMPLER, "surface resolve sampler")
	_set_debug_object_name(cast(u64)view, .IMAGE_VIEW, "surface resolve view")

	return Texture {
		name = "surface resolve color attachment",
		image = image,
		sampler = sampler,
		view = view,
		format = format,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}

@(private = "file")
@(require_results)
_create_surface_depth_resource :: proc(
	width: u32,
	height: u32,
	cmd: Command_Buffer,
	sample_count: Sample_Count_Flag,
	loc := #caller_location,
) -> Texture {
	format := _find_depth_format(ctx.vulkan_state.physical_device)
	image, allocation, allocation_info := _create_image(
		width,
		height,
		1,
		sample_count,
		format,
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT, .SAMPLED},
		.AUTO_PREFER_DEVICE,
		{},
	)

	_transition_image_layout(cmd, image, {.DEPTH}, format, .UNDEFINED, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL, 1)
	view := _create_image_view(image, format, {.DEPTH}, 1)

	_set_debug_object_name(cast(u64)image, .IMAGE, "surface depth image")
	_set_debug_object_name(cast(u64)view, .IMAGE_VIEW, "surface depth view")

	return Texture {
		name = "surface depth attachment",
		image = image,
		view = view,
		format = format,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}

@(private = "file")
@(require_results)
_create_surface_depth_resource_sampled :: proc(
	width: u32,
	height: u32,
	cmd: Command_Buffer,
	loc := #caller_location,
) -> Texture {
	format := _find_depth_format(ctx.vulkan_state.physical_device)
	image, allocation, allocation_info := _create_image(
		width,
		height,
		1,
		._1,
		format,
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT, .SAMPLED},
		.AUTO_PREFER_DEVICE,
		{},
	)

	_transition_image_layout(cmd, image, {.DEPTH}, format, .UNDEFINED, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL, 1)
	view := _create_image_view(image, format, {.DEPTH}, 1)

	depth_sampler_info := vk.SamplerCreateInfo {
		sType        = .SAMPLER_CREATE_INFO,
		magFilter    = .LINEAR,
		minFilter    = .LINEAR,
		mipmapMode   = .LINEAR,
		addressModeU = .REPEAT,
		addressModeV = .REPEAT,
		addressModeW = .REPEAT,
		// compareEnable = true, // TODO:
		// compareOp     = .LESS_OR_EQUAL,
	}

	sampler: vk.Sampler
	vk.CreateSampler(ctx.vulkan_state.device, &depth_sampler_info, nil, &sampler)

	_set_debug_object_name(cast(u64)image, .IMAGE, "surface depth msaa image")
	_set_debug_object_name(cast(u64)view, .IMAGE_VIEW, "surface depth msaa view")
	_set_debug_object_name(cast(u64)sampler, .SAMPLER, "surface depth msaa sampler")

	return Texture {
		name = "surface depth msaa attachment",
		image = image,
		view = view,
		sampler = sampler,
		format = format,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}

@(private = "file")
_surface_resize_color_attachment :: proc(width: u32, height: u32, surface: ^Surface, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(surface, loc)

	color_attachment, has_color_attachment := surface.color_attachment.?
	assert(has_color_attachment)

	msaa, has_msaa := color_attachment.msaa_texture.?

	resolve := _create_surface_color_resolve_resource(width, height, surface.anisotropy, ctx.swapchain.format.format)
	bindless_update_texture(color_attachment.texture_h, resolve)
	color_attachment.info.imageView = resolve.view

	if has_msaa {
		destroy_texture(&msaa)
		new_msaa := _create_surface_color_resource(width, height, ctx.swapchain.format.format, surface.sample_count)
		color_attachment.msaa_texture = new_msaa
		color_attachment.info.imageView = new_msaa.view
		color_attachment.info.resolveImageView = resolve.view
	}

	surface.color_attachment = color_attachment
}

@(private = "file")
_surface_resize_readable_depth_attachment :: proc(width: u32, height: u32, surface: ^Surface, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(surface, loc)

	depth_attachment, has_depth_attachment := surface.depth_attachment.?
	assert(has_depth_attachment)
	attachment, ok := depth_attachment.(Surface_Readable_Depth_Attachment)
	assert(ok)

	msaa, has_msaa := attachment.msaa_texture.?

	sc := begin_single_cmd()

	resolve := _create_surface_depth_resource_sampled(width, height, sc.cmd)
	bindless_update_texture(attachment.texture_h, resolve)
	attachment.info.imageView = resolve.view

	if has_msaa {
		destroy_texture(&msaa)
		new_msaa := _create_surface_depth_resource(width, height, sc.cmd, surface.sample_count)
		attachment.msaa_texture = new_msaa
		attachment.info.imageView = new_msaa.view
		attachment.info.resolveImageView = resolve.view
	}
	end_single_cmd(sc)

	surface.depth_attachment = attachment
}
