package ve

import "base:runtime"
import sm "core:container/small_array"
import "core:fmt"
import "core:log"
import "core:slice"
import "lib/vma"
import vk "vendor:vulkan"

Render_Target_Color_Attachment :: struct {
	info:         vk.RenderingAttachmentInfo,
	msaa_texture: Maybe(Texture_Data),
	texture_h:    Texture,
	sampler_info: Sampler_Info,
}

Render_Target_Color_Attachments :: sm.Small_Array(MAX_COLOR_ATTACHMENTS, Render_Target_Color_Attachment)

Render_Target_Depth_Attachment :: union {
	Render_Target_Unreadable_Depth_Attachment,
	Render_Target_Readable_Depth_Attachment,
}

Stencil_Info :: struct {
	clear_value: u32,
}

Render_Target_Unreadable_Depth_Attachment :: struct {
	resource: Texture_Data,
	info:     vk.RenderingAttachmentInfo,
}

Render_Target_Readable_Depth_Attachment :: struct {
	msaa_texture: Maybe(Texture_Data),
	texture_h:    Texture,
	info:         vk.RenderingAttachmentInfo,
	sampler_info: Sampler_Info,
}

Render_Target :: struct {
	width, height:     int,
	transform:         Transform,
	color_attachments: Render_Target_Color_Attachments,
	depth_attachment:  Maybe(Render_Target_Depth_Attachment),
	sample_count:      Sample_Count_Flag,
}

init_render_target :: proc(
	render_target: ^Render_Target,
	width, height: int,
	sample_count: Sample_Count_Flag,
	allocator := context.allocator,
	loc := #caller_location,
) {
	assert_not_nil(render_target, loc)
	assert(width > 0 && height > 0, loc = loc)

	render_target.width = width
	render_target.height = height

	init_trf(&render_target.transform)

	render_target.sample_count = sample_count
}

destroy_render_target :: proc(render_target: ^Render_Target, loc := #caller_location) {
	assert_not_nil(render_target, loc)

	depth_attachment, has_depth_attachment := render_target.depth_attachment.?

	for ca in sm.slice(&render_target.color_attachments) {
		t := _acquire_texture_h(ca.texture_h, loc)
		_destroy_texture(&t, loc)
		msaa, has_msaa := ca.msaa_texture.?
		if has_msaa do _destroy_texture(&msaa, loc)
	}

	if has_depth_attachment {
		switch &attachment in depth_attachment {
		case Render_Target_Unreadable_Depth_Attachment:
			_destroy_texture(&attachment.resource, loc)
		case Render_Target_Readable_Depth_Attachment:
			t := _acquire_texture_h(attachment.texture_h, loc)
			_destroy_texture(&t, loc)

			msaa, has_msaa := attachment.msaa_texture.?
			if has_msaa do _destroy_texture(&msaa, loc)
		}
	}
}

@(require_results)
render_target_add_color_attachment :: proc(
	rt: ^Render_Target,
	format: Format = .RGBA_norm_u8,
	sampler_info: Sampler_Info = DEFAULT_RENDER_TARGET_SAMPLER_INFO,
	loc := #caller_location,
) -> Texture {
	assert_not_nil(rt, loc)

	w, h := cast(u32)rt.width, cast(u32)rt.height

	color_attachment := Render_Target_Color_Attachment{}
	if rt.sample_count == ._1 {
		color_res := _create_render_target_color_resolve_resource(w, h, format, sampler_info, loc)

		color_attachment.texture_h = _store_texture(color_res, loc)

		color_attachment.info = {
			sType       = .RENDERING_ATTACHMENT_INFO,
			pNext       = nil,
			imageView   = color_res.view,
			imageLayout = .ATTACHMENT_OPTIMAL,
			resolveMode = {},
		}
	} else {
		msaa := _create_render_target_color_resource(w, h, format, rt.sample_count, loc)
		resolve := _create_render_target_color_resolve_resource(w, h, format, sampler_info, loc)

		color_attachment.texture_h = _store_texture(resolve)
		color_attachment.msaa_texture = msaa

		color_attachment.info = {
			sType              = .RENDERING_ATTACHMENT_INFO,
			pNext              = nil,
			imageView          = msaa.view,
			imageLayout        = .ATTACHMENT_OPTIMAL,
			resolveMode        = {.AVERAGE_KHR},
			resolveImageView   = resolve.view,
			resolveImageLayout = .GENERAL,
		}
	}
	color_attachment.sampler_info = sampler_info

	sm.append_elem(&rt.color_attachments, color_attachment)

	return color_attachment.texture_h
}

render_target_add_depth_attachment :: proc(
	rt: ^Render_Target,
	clear_value: f32 = 1,
	stencil_info: Maybe(Stencil_Info) = nil,
	loc := #caller_location,
) {
	assert_not_nil(rt, loc)
	_, has_depth_attachment := rt.depth_attachment.?
	assert(has_depth_attachment == false, "Render target already has a depth attachment.", loc)

	stencil, has_stencil := stencil_info.?
	w, h := cast(u32)rt.width, cast(u32)rt.height

	sc := begin_single_cmd()
	depth_resource := _create_render_target_depth_resource(w, h, sc.cmd, rt.sample_count, has_stencil, loc)
	end_single_cmd(sc)

	depth_attachment := Render_Target_Unreadable_Depth_Attachment {
		resource = depth_resource,
		info = {
			sType = .RENDERING_ATTACHMENT_INFO,
			pNext = nil,
			imageView = depth_resource.view,
			imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
			clearValue = vk.ClearValue{depthStencil = {clear_value, stencil.clear_value}},
		},
	}

	rt.depth_attachment = depth_attachment
}

render_target_add_readable_depth_attachment :: proc(
	rt: ^Render_Target,
	clear_value: f32 = 1,
	sampler_info: Sampler_Info = DEFAULT_SAMPLER_INFO,
	loc := #caller_location,
) -> Texture {
	assert_not_nil(rt, loc)
	_, has_depth_attachment := rt.depth_attachment.?
	assert(has_depth_attachment == false, "Render Target already has a depth attachment.", loc)

	w, h := cast(u32)rt.width, cast(u32)rt.height

	depth_attachment := Render_Target_Readable_Depth_Attachment{}

	sc := begin_single_cmd()
	depth_resource := _create_render_target_depth_resource_sampled(w, h, sc.cmd, sampler_info, loc)
	depth_attachment.texture_h = _store_texture(depth_resource)

	if rt.sample_count == ._1 {
		depth_attachment.info = {
			sType = .RENDERING_ATTACHMENT_INFO,
			pNext = nil,
			imageView = depth_resource.view,
			imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
			clearValue = vk.ClearValue{depthStencil = {clear_value, 0}},
		}
	} else {
		msaa := _create_render_target_depth_resource(w, h, sc.cmd, rt.sample_count, false, loc)
		depth_attachment.msaa_texture = msaa
		depth_attachment.info = {
			sType = .RENDERING_ATTACHMENT_INFO,
			pNext = nil,
			imageView = msaa.view,
			imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
			resolveMode = {.AVERAGE_KHR},
			resolveImageView = depth_resource.view,
			resolveImageLayout = .GENERAL,
			clearValue = vk.ClearValue{depthStencil = {clear_value, 0}},
		}
	}
	end_single_cmd(sc)

	depth_attachment.sampler_info = sampler_info
	rt.depth_attachment = depth_attachment

	return depth_attachment.texture_h
}

begin_render_target :: proc(
	rt: ^Render_Target,
	color_actions: []Color_Attachment_Action = nil,
	depth_stencil_action: Maybe(Depth_Stencil_Attachment_Action) = nil,
	loc := #caller_location,
) {
	assert_not_nil(rt, loc)

	cmd_set_viewport(rt.width, rt.height)
	cmd_set_scissor(rt.width, rt.height)

	cmd := _get_cmd()
	depth_attachment, has_depth_attachment := rt.depth_attachment.?
	has_color_attachments := sm.len(rt.color_attachments) > 0

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}

	p_color_attachments: sm.Small_Array(MAX_COLOR_ATTACHMENTS, vk.RenderingAttachmentInfo)
	src_color_attachments: Render_Target_Color_Attachments

	active_color_attachments: sm.Small_Array(MAX_COLOR_ATTACHMENTS, int)

	if color_actions != nil {
		assert(has_color_attachments, "color_actions specified but render target has no color attachments.", loc)
		for a, i in color_actions {
			assert(a.index < rt.color_attachments.len && a.index >= 0, loc = loc)
			for _, j in color_actions {
				if i == j do continue
				assert(
					color_actions[i].index != color_actions[j].index,
					fmt.tprintf(
						"Duplicate index %d found in color_actions at positions %d and %d.",
						color_actions[i].index,
						i,
						j,
					),
					loc = loc,
				)
			}

			attachment := sm.get(rt.color_attachments, a.index)
			attachment.info.clearValue.color.float32 = a.clear_value
			attachment.info.loadOp = cast(vk.AttachmentLoadOp)a.load_op
			attachment.info.storeOp = cast(vk.AttachmentStoreOp)a.store_op

			sm.append(&src_color_attachments, attachment)
			sm.append(&active_color_attachments, a.index)
		}
	} else {
		for _, i in sm.slice(&rt.color_attachments) {
			attachment := sm.get(rt.color_attachments, i)
			attachment.info.clearValue.color.float32 = {0, 0, 0, 0}
			attachment.info.loadOp = .CLEAR
			attachment.info.storeOp = .STORE
			sm.append(&src_color_attachments, attachment)
			sm.append(&active_color_attachments, i)
		}
	}

	assert(
		sm.len(src_color_attachments) > 0 || has_depth_attachment,
		"Couldn't begin_render_target() without color attachments.",
	)

	for ca, i in sm.slice(&src_color_attachments) {
		msaa, has_msaa := ca.msaa_texture.?
		texture := _get_texture_h(ca.texture_h, loc)

		target := &msaa if has_msaa else texture
		_cmd_image_transition_layout(cmd, target.id, .UNDEFINED, .COLOR_ATTACHMENT_OPTIMAL)

		sm.append(&p_color_attachments, ca.info)
	}

	depth_stencil_action, has_depth_stencil_action := depth_stencil_action.?
	depth_stencil_info: vk.RenderingAttachmentInfo
	depth_format: Format

	if has_depth_attachment {
		switch &attachment in depth_attachment {
		case Render_Target_Unreadable_Depth_Attachment:
			depth_stencil_info = attachment.info
			depth_format = attachment.resource.format
		case Render_Target_Readable_Depth_Attachment:
			depth_stencil_info = attachment.info
			msaa, has_msaa := attachment.msaa_texture.?

			texture := _get_texture_h(attachment.texture_h)
			depth_format = texture.format
			target: ^Texture_Data = &msaa if has_msaa else texture

			_cmd_image_transition_layout(
				cmd,
				target.id,
				.SHADER_READ_ONLY_OPTIMAL,
				.DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
				vk.ImageSubresourceRange{aspectMask = {.DEPTH}, layerCount = 1, levelCount = 1},
			)
		}

		if has_depth_stencil_action {
			depth_stencil_info.clearValue.depthStencil = {
				depth   = depth_stencil_action.depth_clear_value,
				stencil = depth_stencil_action.stencil_clear_value,
			}
			depth_stencil_info.loadOp = cast(vk.AttachmentLoadOp)depth_stencil_action.load_op
			depth_stencil_info.storeOp = cast(vk.AttachmentStoreOp)depth_stencil_action.load_op
		} else {
			depth_stencil_info.clearValue.depthStencil = {
				depth   = 1,
				stencil = 0,
			}
			depth_stencil_info.loadOp = .CLEAR
			depth_stencil_info.storeOp = .DONT_CARE
		}
	} else {
		assert(
			has_depth_stencil_action,
			"depth_stencil_action specified but render target has no depth stencil attachment.",
			loc = loc,
		)
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = {width = cast(u32)rt.width, height = cast(u32)rt.height}},
		layerCount = 1,
		colorAttachmentCount = cast(u32)src_color_attachments.len,
		pColorAttachments = raw_data(sm.slice(&p_color_attachments)),
		pDepthAttachment = &depth_stencil_info if has_depth_attachment else nil,
		pStencilAttachment = &depth_stencil_info if has_depth_attachment && _has_stencil_component(depth_format) else nil,
	}

	vk.CmdBeginRendering(cmd, &rendering_info)

	surface_info := Surface_Info {
		type                            = .Surface,
		sample_count                    = rt.sample_count,
		depth_format                    = depth_format if has_depth_attachment else .None,
		width                           = rt.width,
		height                          = rt.height,
		active_color_attachment_indices = active_color_attachments,
	}

	if (has_color_attachments) {
		for ca in sm.slice(&src_color_attachments) {
			texture := _get_texture_h(ca.texture_h)
			sm.push(&surface_info.color_formats, texture.format)
		}
	}

	ctx.gfx.frame.surface_info = surface_info
}

end_render_target :: proc(rt: ^Render_Target, loc := #caller_location) {
	assert_not_nil(rt, loc)

	vk.CmdEndRendering(_get_cmd())

	has_color_attachments := sm.len(rt.color_attachments) > 0
	depth_attachment, has_depth_attachment := rt.depth_attachment.?

	for ca, i in sm.slice(&rt.color_attachments) {
		if !slice.contains(sm.slice(&ctx.gfx.frame.surface_info.active_color_attachment_indices), i) {
			continue
		}
		msaa, has_msaa := ca.msaa_texture.?
		texture := _get_texture_h(ca.texture_h, loc)

		target := &msaa if has_msaa else texture
		_cmd_image_transition_layout(_get_cmd(), target.id, .COLOR_ATTACHMENT_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
	}

	if has_depth_attachment {
		switch attachment in depth_attachment {
		case Render_Target_Unreadable_Depth_Attachment:
		case Render_Target_Readable_Depth_Attachment:
			texture := _get_texture_h(attachment.texture_h)
			msaa, has_msaa := attachment.msaa_texture.?

			sc := begin_single_cmd()
			target := &msaa if has_msaa else texture

			_cmd_image_transition_layout(
				sc.cmd,
				target.id,
				.DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
				.SHADER_READ_ONLY_OPTIMAL,
				vk.ImageSubresourceRange{aspectMask = {.DEPTH}, layerCount = 1, levelCount = 1},
			)
			end_single_cmd(sc)
		}
	}
}

render_target_resize :: proc(rt: ^Render_Target, width, height: int, loc := #caller_location) {
	_render_target_resize(rt, width, height, loc)
}

@(private = "file")
_render_target_resize :: proc(rt: ^Render_Target, width, height: int, loc := #caller_location) {
	assert(width > 0 && height > 0, loc = loc)
	rt.width, rt.height = width, height

	_render_target_resize_color_attachments(width, height, rt)

	depth_attachment, has_depth_attachment := rt.depth_attachment.?
	if has_depth_attachment {
		switch &attachment in depth_attachment {
		case Render_Target_Unreadable_Depth_Attachment:
			has_stencil := _has_stencil_component(attachment.resource.format)

			_destroy_texture(&attachment.resource, loc)
			rt.depth_attachment = nil

			if has_stencil {
				render_target_add_depth_attachment(
					rt,
					clear_value = attachment.info.clearValue.depthStencil.depth,
					stencil_info = Stencil_Info{clear_value = attachment.info.clearValue.depthStencil.stencil},
				)
			} else {
				render_target_add_depth_attachment(rt, clear_value = attachment.info.clearValue.depthStencil.depth)
			}
		case Render_Target_Readable_Depth_Attachment:
			_render_target_resize_readable_depth_attachment(width, height, rt)
		}
	}
}

@(private = "file")
@(require_results)
_create_render_target_color_resource :: proc(
	width, height: u32,
	format: Format,
	sample_count: Sample_Count_Flag,
	loc := #caller_location,
) -> Texture_Data {
	image, allocation, allocation_info := _create_vk_image(
		width,
		height,
		1,
		sample_count,
		_format_to_vk(format),
		.OPTIMAL,
		{.COLOR_ATTACHMENT, .SAMPLED},
		.AUTO_PREFER_DEVICE,
		{},
	)

	view := _create_vk_image_view(image, _format_to_vk(format), {.COLOR}, 1)

	texture := Texture_Data {
		id              = image,
		view            = view,
		format          = format,
		allocation      = allocation,
		allocation_info = allocation_info,
	}

	_vk_set_debug_texture_name(texture, fmt.tprintf("render target color msaa %s", _location_to_string(loc)))

	return texture
}

@(private = "file")
@(require_results)
_create_render_target_color_resolve_resource :: proc(
	width, height: u32,
	format: Format,
	sampler_info: Sampler_Info = DEFAULT_SAMPLER_INFO,
	loc := #caller_location,
) -> Texture_Data {
	image, allocation, allocation_info := _create_vk_image(
		width,
		height,
		1,
		._1,
		_format_to_vk(format),
		.OPTIMAL,
		{.COLOR_ATTACHMENT, .SAMPLED},
		.AUTO_PREFER_DEVICE,
		{},
	)

	view := _create_vk_image_view(image, _format_to_vk(format), {.COLOR}, 1)
	sampler: Sampler = _create_sampler(sampler_info)

	texture := Texture_Data {
		id              = image,
		sampler         = sampler,
		view            = view,
		format          = format,
		allocation      = allocation,
		allocation_info = allocation_info,
	}

	_vk_set_debug_texture_name(texture, fmt.tprintf("render resolve color msaa %s", _location_to_string(loc)))

	return texture
}

@(private = "file")
@(require_results)
_create_render_target_depth_resource :: proc(
	width: u32,
	height: u32,
	cmd: Command_Buffer,
	sample_count: Sample_Count_Flag,
	stencil: bool,
	loc := #caller_location,
) -> Texture_Data {
	format: Format = ctx.gfx.swapchain_cfg.depth_stencil_format if stencil else ctx.gfx.swapchain_cfg.depth_format
	aspect: vk.ImageAspectFlags = {.DEPTH, .STENCIL} if stencil else {.DEPTH}

	image, allocation, allocation_info := _create_vk_image(
		width,
		height,
		1,
		sample_count,
		_format_to_vk(format),
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT},
		.AUTO_PREFER_DEVICE,
		{},
	)

	_cmd_image_transition_layout(
		cmd,
		image,
		.UNDEFINED,
		.DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		vk.ImageSubresourceRange{aspectMask = aspect, levelCount = 1, layerCount = 1},
	)
	view := _create_vk_image_view(image, _format_to_vk(format), aspect, 1)

	texture := Texture_Data {
		id              = image,
		view            = view,
		format          = format,
		allocation      = allocation,
		allocation_info = allocation_info,
	}

	_vk_set_debug_texture_name(texture, fmt.tprintf("render target depth msaa %s", _location_to_string(loc)))

	return texture
}

@(private = "file")
@(require_results)
_create_render_target_depth_resource_sampled :: proc(
	width: u32,
	height: u32,
	cmd: Command_Buffer,
	sampler_info: Sampler_Info,
	loc := #caller_location,
) -> Texture_Data {
	format := ctx.gfx.swapchain_cfg.depth_format
	image, allocation, allocation_info := _create_vk_image(
		width,
		height,
		1,
		._1,
		_format_to_vk(format),
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT, .SAMPLED},
		.AUTO_PREFER_DEVICE,
		{},
	)

	_cmd_image_transition_layout(
		cmd,
		image,
		.UNDEFINED,
		.DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		vk.ImageSubresourceRange{aspectMask = {.DEPTH}, levelCount = 1, layerCount = 1},
	)

	view := _create_vk_image_view(image, _format_to_vk(format), {.DEPTH}, 1)
	sampler: Sampler = _create_sampler(sampler_info)

	texture := Texture_Data {
		id              = image,
		view            = view,
		sampler         = sampler,
		format          = format,
		allocation      = allocation,
		allocation_info = allocation_info,
	}

	_vk_set_debug_texture_name(texture, fmt.tprintf("render target depth msaa %s", _location_to_string(loc)))

	return texture
}

@(private = "file")
_render_target_resize_color_attachments :: proc(width: int, height: int, rt: ^Render_Target, loc := #caller_location) {
	assert_not_nil(rt, loc)

	for &ca in sm.slice(&rt.color_attachments) {
		msaa, has_msaa := ca.msaa_texture.?
		w, h := cast(u32)width, cast(u32)height

		resolve := _create_render_target_color_resolve_resource(
			w,
			h,
			texture_get_format(ca.texture_h),
			ca.sampler_info,
			loc,
		)
		_replace_texture_h(ca.texture_h, resolve, loc)
		ca.info.imageView = resolve.view

		if has_msaa {
			_destroy_texture(&msaa, loc)
			new_msaa := _create_render_target_color_resource(w, h, texture_get_format(ca.texture_h), rt.sample_count)
			ca.msaa_texture = new_msaa
			ca.info.imageView = new_msaa.view
			ca.info.resolveImageView = resolve.view
		}
	}
}

@(private = "file")
_render_target_resize_readable_depth_attachment :: proc(
	width: int,
	height: int,
	rt: ^Render_Target,
	loc := #caller_location,
) {
	assert_not_nil(rt, loc)

	depth_attachment, has_depth_attachment := rt.depth_attachment.?
	assert(has_depth_attachment)
	attachment, ok := depth_attachment.(Render_Target_Readable_Depth_Attachment)
	assert(ok)

	w, h := cast(u32)width, cast(u32)height

	msaa, has_msaa := attachment.msaa_texture.?
	sc := begin_single_cmd()

	resolve := _create_render_target_depth_resource_sampled(w, h, sc.cmd, attachment.sampler_info, loc)
	_replace_texture_h(attachment.texture_h, resolve, loc)
	attachment.info.imageView = resolve.view

	if has_msaa {
		_destroy_texture(&msaa, loc)
		new_msaa := _create_render_target_depth_resource(w, h, sc.cmd, rt.sample_count, false)
		attachment.msaa_texture = new_msaa
		attachment.info.imageView = new_msaa.view
		attachment.info.resolveImageView = resolve.view
	}
	end_single_cmd(sc)

	rt.depth_attachment = attachment
}
