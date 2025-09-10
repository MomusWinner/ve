package graphics

import "base:runtime"
import "core:log"
import "core:mem"
import vk "vendor:vulkan"
import "vma"

surface_init :: proc(surface: ^Surface, g: ^Graphics, width, height: u32, allocator := context.allocator) {
	surface.extent = {
		width  = width,
		height = height,
	}

	material: Material
	material_init(&material, g, {})

	vertices := make([]Vertex, 6, allocator)
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

surface_destroy :: proc(surface: ^Surface, g: ^Graphics) {
	destroy_model(g, &surface.model)
	color_attachment, has_color_attachment := surface.color_attachment.?
	depth_attachment, has_depth_attachment := surface.depth_attachment.?
	log.info("Has Depth")
	log.info(has_depth_attachment)

	if has_color_attachment {
		bindless_destroy_texture(g, color_attachment.handle)
	}

	if has_depth_attachment {
		destroy_texture(g, &depth_attachment.resource)
	}
}

surface_add_color_attachment :: proc(surface: ^Surface, g: ^Graphics) {
	color_resource := _create_surface_color_resource(g, g.swapchain.format.format, g.msaa_samples)

	color_attachment := Surface_Attachment {
		resource = color_resource,
		info = {
			sType = .RENDERING_ATTACHMENT_INFO,
			pNext = nil,
			imageView = color_resource.view,
			imageLayout = .ATTACHMENT_OPTIMAL,
			loadOp = .CLEAR,
			storeOp = .STORE,
			clearValue = vk.ClearValue{color = {float32 = {0.0, 0.0, 0.0, 1.0}}},
		},
	}
	surface.color_attachment = color_attachment

	color_attachment.handle = bindless_store_texture(g, color_resource)
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
	surface.model.materials[0].texture_h = color_attachment.handle
	material_update(&surface.model.materials[0], g)
	draw_model(g, surface.model, camera, {}, frame.cmd)
}

@(private = "file")
_create_surface_color_resource :: proc(g: ^Graphics, format: vk.Format, samples: vk.SampleCountFlags) -> Texture {
	image, allocation, allocation_info := _create_image(
		g,
		get_width(g),
		get_height(g),
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
_create_surface_depth_resource :: proc(g: ^Graphics, cmd: Command_Buffer) -> Texture {
	format := _find_depth_format(g.physical_device)
	image, allocation, allocation_info := _create_image(
		g,
		get_width(g),
		get_height(g),
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
