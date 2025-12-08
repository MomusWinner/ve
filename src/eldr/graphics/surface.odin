package graphics

import hm "../handle_map/"
import "base:runtime"
import "core:log"
import "core:mem"
import "core:time"
import vk "vendor:vulkan"
import "vma"

// TODO: ! Make surface more flexible

@(require_results)
create_surface :: proc(
	sample_count: Sample_Count_Flag = ._1,
	anisotropy: f32 = 1,
	allocator := context.allocator,
	loc := #caller_location,
) -> Surface_Handle {
	return _surface_manager_create_surface(ctx.surface_manager, sample_count, anisotropy, allocator)
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
) {
	assert_gfx_ctx(loc)
	assert_not_nil(surface, loc)

	width, height := get_screen_width(), get_screen_height()

	color_resource := _create_surface_color_resource(width, height, ctx.swapchain.format.format, surface.sample_count)
	color_resolve_resource := _create_surface_color_resolve_resource(
		width,
		height,
		surface.anisotropy,
		ctx.swapchain.format.format,
	)

	color_attachment := Surface_Color_Attachment {
		info = {
			sType = .RENDERING_ATTACHMENT_INFO,
			pNext = nil,
			imageView = color_resource.view,
			imageLayout = .ATTACHMENT_OPTIMAL,
			resolveMode = {.AVERAGE_KHR},
			resolveImageView = color_resolve_resource.view,
			resolveImageLayout = .GENERAL,
			loadOp = .CLEAR,
			storeOp = .STORE,
			clearValue = vk.ClearValue{color = {float32 = clear_value}},
		},
	}
	surface.color_attachment = color_attachment

	color_attachment.resource = color_resource
	color_attachment.resolve_handle = bindless_store_texture(color_resolve_resource)
	surface.color_attachment = color_attachment
}

surface_add_depth_attachment :: proc(surface: ^Surface, clear_value: f32 = 1, loc := #caller_location) {
	assert_not_nil(surface, loc)

	sc := _cmd_single_begin()
	width, height := get_screen_width(), get_screen_height()
	depth_resource := _create_surface_depth_resource(width, height, sc.command_buffer, surface.sample_count)
	_cmd_single_end(sc)

	depth_attachment := Surface_Depth_Attachment {
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
		_transition_image_layout(
			cmd,
			color_attachment.resource.image,
			{.COLOR},
			color_attachment.resource.format,
			.UNDEFINED,
			.COLOR_ATTACHMENT_OPTIMAL,
			1,
		)

		p_color_attachment = &color_attachment.info
	}

	if has_depth_attachment {
		p_depth_attachment = &depth_attachment.info
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = surface.extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = p_color_attachment,
		pDepthAttachment = p_depth_attachment,
	}

	vk.CmdBeginRendering(cmd, &rendering_info)

	frame_data := frame_data
	frame_data.surface_info = {
		type         = .Surface,
		sample_count = surface.sample_count,
	}

	return frame_data
}

end_surface :: proc(surface: ^Surface, frame_data: Frame_Data, loc := #caller_location) {
	assert_not_nil(surface, loc)

	vk.CmdEndRendering(frame_data.cmd)

	color_attachment, has_color_attachment := surface.color_attachment.?

	if has_color_attachment {
		_transition_image_layout(
			frame_data.cmd,
			color_attachment.resource.image,
			{.COLOR},
			color_attachment.resource.format,
			.COLOR_ATTACHMENT_OPTIMAL,
			.SHADER_READ_ONLY_OPTIMAL,
			1,
		)
	}
}

draw_surface :: proc(
	surface: ^Surface,
	camera: ^Camera,
	frame_data: Frame_Data,
	pipeline_h: Pipeline_Handle,
	loc := #caller_location,
) {
	assert_gfx_ctx(loc)
	assert_not_nil(surface, loc)

	color_attachment, has_color := surface.color_attachment.?
	assert(has_color, loc = loc)

	surface.model.materials[0].pipeline_h = pipeline_h
	mtrl_base_set_texture_h(&surface.model.materials[0], color_attachment.resolve_handle)
	draw_model(frame_data, surface.model, camera, &surface.transform, loc)
}

_init_surface_manager :: proc() {
	assert(ctx.surface_manager == nil)
	ctx.surface_manager = new(Surface_Manager)
	_surface_manager_init(ctx.surface_manager)
}

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
_surface_manager_create_surface :: proc(
	sm: ^Surface_Manager,
	sample_count: Sample_Count_Flag,
	anisotropy: f32,
	allocator := context.allocator,
	loc := #caller_location,
) -> Surface_Handle {
	assert_gfx_ctx(loc)
	assert_not_nil(sm, loc)

	surface := Surface{}
	_surface_init(&surface, sample_count, anisotropy)

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
_surface_manager_recreate_surfaces :: proc(sm: ^Surface_Manager, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(sm, loc)

	must(vk.QueueWaitIdle(ctx.vulkan_state.graphics_queue))
	for &surface in sm.surfaces.values {
		_surface_recreate(&surface)
	}
}

@(private)
_surface_init :: proc(
	surface: ^Surface,
	sample_count: Sample_Count_Flag,
	anisotropy: f32,
	allocator := context.allocator,
	loc := #caller_location,
) {
	assert_not_nil(surface, loc)
	assert_gfx_ctx(loc)

	surface.extent = {
		width  = get_device_width(),
		height = get_device_height(),
	}

	material: Material
	init_mtrl_base(&material, {})

	mesh := create_square_mesh(1)

	meshes := make([]Mesh, 1)
	meshes[0] = mesh

	materials := make([dynamic]Material, 1, allocator)
	materials[0] = material

	mesh_material := make([dynamic]int, 1, allocator)
	mesh_material[0] = 0

	init_gfx_trf(&surface.transform)

	surface.model = create_model(meshes, materials, mesh_material)
	surface.sample_count = sample_count
	surface.anisotropy = anisotropy
}

@(private)
_surface_destroy :: proc(surface: ^Surface, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(surface, loc)

	destroy_model(&surface.model)
	color_attachment, has_color_attachment := surface.color_attachment.?
	depth_attachment, has_depth_attachment := surface.depth_attachment.?

	if has_color_attachment {
		destroy_texture(&color_attachment.resource)
	}

	if has_depth_attachment {
		destroy_texture(&depth_attachment.resource)
	}
}

@(private = "file")
_surface_recreate :: proc(surface: ^Surface, loc := #caller_location) {
	surface.extent.width = get_screen_width()
	surface.extent.height = get_screen_height()

	color_attachment, has_color_attachment := surface.color_attachment.?
	depth_attachment, has_depth_attachment := surface.depth_attachment.?

	if has_color_attachment {
		destroy_texture(&color_attachment.resource)
		bindless_destroy_texture(color_attachment.resolve_handle)
		surface_add_color_attachment(surface)
	}

	if has_depth_attachment {
		destroy_texture(&depth_attachment.resource)
		surface_add_depth_attachment(surface)
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
		vk.ImageTiling.OPTIMAL,
		vk.ImageUsageFlags{.COLOR_ATTACHMENT, .SAMPLED},
		vma.MemoryUsage.AUTO_PREFER_DEVICE,
		vma.AllocationCreateFlags{},
	)

	view := _create_image_view(image, format, {.COLOR}, 1)

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
		Sample_Count_Flag._1,
		format,
		vk.ImageTiling.OPTIMAL,
		vk.ImageUsageFlags{.COLOR_ATTACHMENT, .SAMPLED},
		vma.MemoryUsage.AUTO_PREFER_DEVICE,
		vma.AllocationCreateFlags{},
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
		vk.ImageTiling.OPTIMAL,
		vk.ImageUsageFlags{.DEPTH_STENCIL_ATTACHMENT},
		vma.MemoryUsage.AUTO_PREFER_DEVICE,
		vma.AllocationCreateFlags{},
	)

	_transition_image_layout(cmd, image, {.DEPTH}, format, .UNDEFINED, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL, 1)
	view := _create_image_view(image, format, {.DEPTH}, 1)

	return Texture {
		name = "surface depth attachment",
		image = image,
		view = view,
		format = format,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}
