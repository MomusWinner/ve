package graphics

import hm "../handle_map/"
import "base:runtime"
import "core:log"
import "core:mem"
import "core:time"
import vk "vendor:vulkan"
import "vma"

@(require_results)
create_surface :: proc(g: ^Graphics, width, height: u32, allocator := context.allocator) -> Surface_Handle {
	return _surface_manager_create_surface(g.surface_manager, g, width, height, allocator)
}

destroy_surface :: proc(g: ^Graphics, surface_h: Surface_Handle) {
	_surface_manager_destroy_surface(g.surface_manager, g, surface_h)
}

@(require_results)
get_surface :: proc(g: ^Graphics, surface_h: Surface_Handle) -> (^Surface, bool) {
	return _surface_manager_get_surface(g.surface_manager, surface_h)
}

surface_add_color_attachment :: proc(surface: ^Surface, g: ^Graphics) {
	color_resource := _create_surface_color_resource(g, g.swapchain.format.format, g.msaa_samples)
	color_resolve_resource := _create_surface_color_resolve_resource(g, g.swapchain.format.format)

	color_attachment := Surface_Color_Attachment {
		resource = color_resource,
		resolve_resource = color_resolve_resource,
		info = {
			sType = .RENDERING_ATTACHMENT_INFO,
			pNext = nil,
			imageView = color_resource.view,
			imageLayout = .ATTACHMENT_OPTIMAL,
			resolveMode = {.AVERAGE_KHR},
			// resolveImageView = g.swapchain.image_views[g.swapchain.image_index],
			resolveImageView = color_resolve_resource.view,
			resolveImageLayout = .GENERAL,
			loadOp = .CLEAR,
			storeOp = .STORE,
			clearValue = vk.ClearValue{color = {float32 = {0.0, 0.0, 0.0, 1.0}}},
		},
	}
	surface.color_attachment = color_attachment

	color_attachment.handle = bindless_store_texture(g, color_resource)
	color_attachment.resolve_handle = bindless_store_texture(g, color_resolve_resource)
	surface.color_attachment = color_attachment
}

surface_add_depth_attachment :: proc(surface: ^Surface, g: ^Graphics) {
	sc := _cmd_single_begin(g)
	depth_resource := _create_surface_depth_resource(g, sc.command_buffer)
	_cmd_single_end(sc)

	depth_attachment := Surface_Attachment {
		resource = depth_resource,
		info = {
			sType = .RENDERING_ATTACHMENT_INFO,
			pNext = nil,
			imageView = depth_resource.view,
			imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
			loadOp = .CLEAR,
			storeOp = .DONT_CARE,
			clearValue = vk.ClearValue{depthStencil = {1, 0}},
		},
	}
	surface.depth_attachment = depth_attachment
}

@(require_results)
surface_begin :: proc(surface: ^Surface, g: ^Graphics) -> Frame_Data {
	cmd := g.cmd

	color_attachment, has_color_attachment := surface.color_attachment.?
	depth_attachment, has_depth_attachment := surface.depth_attachment.?
	assert(has_color_attachment || has_depth_attachment, "Couldn't begin_surface() without attachments")

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}

	p_color_attachment: ^vk.RenderingAttachmentInfo = nil
	p_depth_attachment: ^vk.RenderingAttachmentInfo = nil

	if has_color_attachment {
		_transition_image_layout_from_cmd(
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

	return Frame_Data{cmd = cmd}
}

surface_end :: proc(surface: ^Surface, frame_data: Frame_Data) {
	vk.CmdEndRendering(frame_data.cmd)

	color_attachment, has_color_attachment := surface.color_attachment.?
	if has_color_attachment {
		_transition_image_layout_from_cmd(
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

surface_draw :: proc(surface: ^Surface, g: ^Graphics, frame: Frame_Data, pipeline_h: Pipeline_Handle) {
	camera := Camera{}
	color_attachment, has_color := surface.color_attachment.?
	assert(has_color)

	surface.model.materials[0].pipeline_h = pipeline_h
	surface.model.materials[0].texture_h = color_attachment.resolve_handle
	material_update(&surface.model.materials[0], g)
	draw_model(g, surface.model, camera, {}, frame.cmd)
}


@(private)
_surface_manager_init :: proc(sm: ^Surface_Manager) {
}

@(private)
_surface_manager_destroy :: proc(sm: ^Surface_Manager, g: ^Graphics) {
	for &surface in sm.surfaces.values {
		_surface_destroy(&surface, g)
	}

	hm.destroy(&sm.surfaces)
}

@(private)
@(require_results)
_surface_manager_create_surface :: proc(
	sm: ^Surface_Manager,
	g: ^Graphics,
	width, height: u32,
	allocator := context.allocator,
) -> Surface_Handle {
	surface := Surface{}
	_surface_init(&surface, g, width, height)

	return hm.insert(&sm.surfaces, surface)
}

@(private)
@(require_results)
_surface_manager_get_surface :: proc(sm: ^Surface_Manager, surface_h: Surface_Handle) -> (^Surface, bool) {
	return hm.get(&sm.surfaces, surface_h)
}

@(private)
_surface_manager_destroy_surface :: proc(sm: ^Surface_Manager, g: ^Graphics, surface_h: Surface_Handle) {
	surface, ok := hm.remove(&sm.surfaces, surface_h)

	if ok {
		_surface_destroy(&surface, g)
	}
}

@(private)
_surface_manager_recreate_surfaces :: proc(sm: ^Surface_Manager, g: ^Graphics) {
	for &surface in sm.surfaces.values {
		surface_recreate(&surface, g)
	}
}

@(private)
_surface_init :: proc(surface: ^Surface, g: ^Graphics, width, height: u32, allocator := context.allocator) {
	surface.extent = {
		width  = width,
		height = height,
	}

	material: Material
	material_init(&material, g, {})

	vertices := make([]Vertex, 6, allocator) // TODO: move to manager
	vertices[0] = {{1.0, 1.0, 0.0}, {1.0, 1.0}, {0.0, 0.0, 1.0}}
	vertices[1] = {{1.0, -1.0, 0.0}, {1.0, 0.0}, {0.0, 1.0, 0.0}}
	vertices[2] = {{-1.0, -1.0, 0.0}, {0.0, 0.0}, {1.0, 0.0, 0.0}}

	vertices[3] = {{1.0, 1.0, 0.0}, {1.0, 1.0}, {0.0, 0.0, 1.0}}
	vertices[4] = {{-1.0, 1.0, 0.0}, {0.0, 1.0}, {1.0, 1.0, 1.0}}
	vertices[5] = {{-1.0, -1.0, 0}, {0.0, 0.0}, {0.0, 1.0, 0.0}}

	mesh := create_mesh(g, vertices, {})

	meshes := make([]Mesh, 1)
	meshes[0] = mesh

	materials := make([dynamic]Material, 1, allocator)
	materials[0] = material

	mesh_material := make([dynamic]int, 1, allocator)
	mesh_material[0] = 0

	surface.model = create_model(meshes, materials, mesh_material)
}

@(private)
_surface_destroy :: proc(surface: ^Surface, g: ^Graphics) {
	destroy_model(g, &surface.model)
	color_attachment, has_color_attachment := surface.color_attachment.?
	depth_attachment, has_depth_attachment := surface.depth_attachment.?

	if has_color_attachment {
		bindless_destroy_texture(g, color_attachment.handle)
	}

	if has_depth_attachment {
		destroy_texture(g, &depth_attachment.resource)
	}
}

surface_recreate :: proc(surface: ^Surface, g: ^Graphics) {
	must(vk.QueueWaitIdle(g.graphics_queue))

	surface.extent.width = get_screen_width(g)
	surface.extent.height = get_screen_height(g)

	color_attachment, has_color_attachment := surface.color_attachment.?
	depth_attachment, has_depth_attachment := surface.depth_attachment.?

	if has_color_attachment {
		bindless_destroy_texture(g, color_attachment.handle)
		bindless_destroy_texture(g, color_attachment.resolve_handle)
		surface_add_color_attachment(surface, g)
	}

	if has_depth_attachment {
		destroy_texture(g, &depth_attachment.resource)
		surface_add_depth_attachment(surface, g)
	}
}

@(private = "file")
@(require_results)
_create_surface_color_resource :: proc(g: ^Graphics, format: vk.Format, samples: vk.SampleCountFlags) -> Texture {

	image, allocation, allocation_info := _create_image(
		g,
		get_screen_width(g),
		get_screen_height(g),
		1,
		samples,
		format,
		vk.ImageTiling.OPTIMAL,
		vk.ImageUsageFlags{.COLOR_ATTACHMENT, .SAMPLED},
		vma.MemoryUsage.AUTO_PREFER_DEVICE,
		vma.AllocationCreateFlags{},
	)

	view := _create_image_view(g.device, image, format, {.COLOR}, 1)

	return Texture {
		name = "surface color resource",
		image = image,
		view = view,
		format = format,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}

@(private = "file")
@(require_results)
_create_surface_color_resolve_resource :: proc(g: ^Graphics, format: vk.Format) -> Texture {
	image, allocation, allocation_info := _create_image(
		g,
		get_screen_width(g),
		get_screen_height(g),
		1,
		vk.SampleCountFlags{._1},
		format,
		vk.ImageTiling.OPTIMAL,
		vk.ImageUsageFlags{.COLOR_ATTACHMENT, .SAMPLED},
		vma.MemoryUsage.AUTO_PREFER_DEVICE,
		vma.AllocationCreateFlags{},
	)

	view := _create_image_view(g.device, image, format, {.COLOR}, 1)

	return Texture {
		name = "surface color resource",
		image = image,
		view = view,
		format = format,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}

@(private = "file")
@(require_results)
_create_surface_depth_resource :: proc(g: ^Graphics, cmd: Command_Buffer) -> Texture {
	format := _find_depth_format(g.physical_device)
	image, allocation, allocation_info := _create_image(
		g,
		get_screen_width(g),
		get_screen_height(g),
		1,
		g.msaa_samples,
		format,
		vk.ImageTiling.OPTIMAL,
		vk.ImageUsageFlags{.DEPTH_STENCIL_ATTACHMENT},
		vma.MemoryUsage.AUTO_PREFER_DEVICE,
		vma.AllocationCreateFlags{},
	)

	_transition_image_layout(cmd, image, {.DEPTH}, format, .UNDEFINED, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL, 1)

	view := _create_image_view(g.device, image, format, {.DEPTH}, 1)
	return Texture {
		image = image,
		view = view,
		format = format,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}
