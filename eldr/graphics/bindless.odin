package graphics

import hm "../handle_map"
import sm "core:container/small_array"
import "core:log"
import vk "vendor:vulkan"

@(private = "file")
UNIFORM_BINDING :: 0
@(private = "file")
STORAGE_BINDING :: 1
@(private = "file")
TEXTURE_BINDING :: 2

@(require_results)
bindless_store_texture :: proc(texture: Texture, loc := #caller_location) -> Texture_Handle {
	assert_gfx_ctx(loc)

	return _bindless_store_texture(ctx.bindless, texture, loc)
}

bindless_update_texture :: proc(texture_h: Texture_Handle, new_texture: Texture, loc := #caller_location) {
	_bindless_update_texture(ctx.bindless, texture_h, new_texture, loc)
}

bindless_destroy_texture :: proc(texture_h: Texture_Handle, loc := #caller_location) -> bool {
	assert_gfx_ctx(loc)

	texture, has_texture := _bindless_remove_texture(ctx.bindless, texture_h)
	if has_texture {
		destroy_texture(&texture)
		return true
	}

	return false
}

@(require_results)
bindless_store_buffer :: proc(buffer: Buffer, loc := #caller_location) -> Buffer_Handle {
	assert_gfx_ctx(loc)

	return _bindless_store_buffer(ctx.bindless, buffer, loc)
}

bindless_destroy_buffer :: proc(buffer_h: Buffer_Handle, loc := #caller_location) {
	assert_gfx_ctx(loc)

	buffer, has_buffer := _bindless_remove_buffer(ctx.bindless, buffer_h)
	if has_buffer {
		destroy_buffer(&buffer)
	}
}

@(require_results)
bindless_get_buffer :: proc(buffer_h: Buffer_Handle, loc := #caller_location) -> ^Buffer {
	assert_gfx_ctx(loc)

	result, ok := hm.get(&ctx.bindless.buffers, buffer_h)
	if !ok {
		log.error("couln't get buffer by handle ", buffer_h, loc)
		return nil
	}

	return result
}

@(require_results)
create_bindless_pipeline_set_info :: proc() -> Pipeline_Set_Layout_Info {
	binding_infos := Pipeline_Set_Binding_Infos{}
	sm.push(
		&binding_infos,
		Pipeline_Set_Binding_Info {
			binding = UNIFORM_BINDING,
			descriptor_type = .UNIFORM_BUFFER,
			descriptor_count = MAX_DESCRIPTOR_BINDLESS_COUNT,
			stage_flags = vk.ShaderStageFlags_ALL_GRAPHICS,
			flags = vk.DescriptorBindingFlags{.UPDATE_AFTER_BIND, .PARTIALLY_BOUND},
		},
		Pipeline_Set_Binding_Info {
			binding = STORAGE_BINDING,
			descriptor_type = .STORAGE_BUFFER,
			descriptor_count = MAX_DESCRIPTOR_BINDLESS_COUNT,
			stage_flags = vk.ShaderStageFlags_ALL_GRAPHICS,
			flags = vk.DescriptorBindingFlags{.UPDATE_AFTER_BIND, .PARTIALLY_BOUND},
		},
		Pipeline_Set_Binding_Info {
			binding = TEXTURE_BINDING,
			descriptor_type = .COMBINED_IMAGE_SAMPLER,
			descriptor_count = MAX_DESCRIPTOR_BINDLESS_COUNT,
			stage_flags = vk.ShaderStageFlags_ALL_GRAPHICS,
			flags = vk.DescriptorBindingFlags{.UPDATE_AFTER_BIND, .PARTIALLY_BOUND},
		},
	)

	return Pipeline_Set_Layout_Info{binding_infos = binding_infos}
}

@(require_results)
bindless_get_texture :: proc(texture_h: Texture_Handle, loc := #caller_location) -> (^Texture, bool) {
	assert_gfx_ctx(loc)

	return hm.get(&ctx.bindless.textures, texture_h)
}

@(require_results)
bindless_has_texture :: proc(texture_h: Texture_Handle, loc := #caller_location) -> bool {
	assert_gfx_ctx(loc)

	return hm.has_handle(&ctx.bindless.textures, texture_h)
}

@(require_results)
get_descriptor_set_bindless :: proc() -> Descriptor_Set {
	return ctx.bindless.set
}

@(private)
_init_bindless :: proc(loc := #caller_location) {
	assert(ctx.bindless == nil, "Bindless already initialized", loc)

	ctx.bindless = new(Bindless)
	_bindless_init(ctx.bindless)
}

@(private)
_destroy_bindless :: proc(loc := #caller_location) {
	assert(ctx.bindless != nil, "Bindless already uninitialized", loc)

	_bindless_destroy(ctx.bindless)
	free(ctx.bindless)
}

@(private = "file")
_bindless_init :: proc(bindless: ^Bindless, loc := #caller_location) {
	assert_not_nil(bindless, loc)

	descriptor_types := [3]vk.DescriptorType{.UNIFORM_BUFFER, .STORAGE_BUFFER, .COMBINED_IMAGE_SAMPLER}
	descriptor_bindings: [3]vk.DescriptorSetLayoutBinding
	descriptor_binding_flags: [3]vk.DescriptorBindingFlags

	for i in 0 ..< 3 {
		descriptor_bindings[i].binding = cast(u32)i
		descriptor_bindings[i].descriptorType = descriptor_types[i]
		descriptor_bindings[i].descriptorCount = MAX_DESCRIPTOR_BINDLESS_COUNT
		descriptor_bindings[i].stageFlags = vk.ShaderStageFlags_ALL_GRAPHICS
		descriptor_binding_flags[i] = {.PARTIALLY_BOUND, .UPDATE_AFTER_BIND}
	}

	binding_flags := vk.DescriptorSetLayoutBindingFlagsCreateInfo {
		sType         = .DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
		pNext         = nil,
		pBindingFlags = raw_data(&descriptor_binding_flags),
		bindingCount  = 3,
	}

	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 3,
		pBindings    = raw_data(&descriptor_bindings),
		flags        = {.UPDATE_AFTER_BIND_POOL},
		pNext        = &binding_flags,
	}

	must(vk.CreateDescriptorSetLayout(ctx.vulkan_state.device, &create_info, nil, &bindless.set_layout))

	allocate_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		pNext              = nil,
		descriptorPool     = ctx.vulkan_state.descriptor_pool,
		pSetLayouts        = &bindless.set_layout,
		descriptorSetCount = 1,
	}

	must(vk.AllocateDescriptorSets(ctx.vulkan_state.device, &allocate_info, &bindless.set))
}

@(private = "file")
_bindless_destroy :: proc(bindless: ^Bindless, loc := #caller_location) {
	assert_not_nil(bindless, loc)

	vk.DestroyDescriptorSetLayout(ctx.vulkan_state.device, bindless.set_layout, nil)

	for &texture in bindless.textures.values {
		destroy_texture(&texture)
	}
	hm.destroy(&bindless.textures)

	for &buffer in bindless.buffers.values {
		destroy_buffer(&buffer)
	}
	hm.destroy(&bindless.buffers)
}

@(private = "file")
_bindless_bind :: proc(
	bindless: ^Bindless,
	cmd: vk.CommandBuffer,
	pipeline_layout: vk.PipelineLayout,
	loc := #caller_location,
) {
	assert_not_nil(bindless, loc)

	vk.CmdBindDescriptorSets(cmd, .GRAPHICS, pipeline_layout, 0, 1, &bindless.set, 0, nil)
}

@(private = "file")
_bindless_store_texture :: proc(bindless: ^Bindless, texture: Texture, loc := #caller_location) -> Texture_Handle {
	assert_not_nil(bindless, loc)

	handle := hm.insert(&bindless.textures, texture)

	image_info := vk.DescriptorImageInfo {
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
		imageView   = texture.view,
		sampler     = texture.sampler,
	}

	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		dstBinding      = TEXTURE_BINDING,
		dstSet          = bindless.set,
		descriptorCount = 1,
		dstArrayElement = handle.index,
		pImageInfo      = &image_info,
	}
	vk.UpdateDescriptorSets(ctx.vulkan_state.device, 1, &write, 0, nil)

	return handle
}

@(private = "file")
_bindless_update_texture :: proc(
	bindless: ^Bindless,
	texture_h: Texture_Handle,
	new_texture: Texture,
	loc := #caller_location,
) {
	assert_not_nil(bindless, loc)

	texture, ok := hm.get(&bindless.textures, texture_h)
	destroy_texture(texture)
	assert(ok, loc = loc)
	texture^ = new_texture

	image_info := vk.DescriptorImageInfo {
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
		imageView   = new_texture.view,
		sampler     = new_texture.sampler,
	}

	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		dstBinding      = TEXTURE_BINDING,
		dstSet          = bindless.set,
		descriptorCount = 1,
		dstArrayElement = texture_h.index,
		pImageInfo      = &image_info,
	}
	vk.UpdateDescriptorSets(ctx.vulkan_state.device, 1, &write, 0, nil)
}

@(private = "file")
_bindless_remove_texture :: proc(
	bindless: ^Bindless,
	texture_h: Texture_Handle,
	loc := #caller_location,
) -> (
	Texture,
	bool,
) {
	assert_not_nil(bindless, loc)

	return hm.remove(&bindless.textures, texture_h)
}

@(private = "file")
_bindless_store_buffer :: proc(bindless: ^Bindless, buffer: Buffer, loc := #caller_location) -> Buffer_Handle {
	assert_not_nil(bindless, loc)

	handle := hm.insert(&bindless.buffers, buffer)

	writes: [2]vk.WriteDescriptorSet

	for &write in writes {
		buffer_info := vk.DescriptorBufferInfo {
			buffer = buffer.buffer,
			offset = 0,
			range  = cast(vk.DeviceSize)vk.WHOLE_SIZE,
		}

		write.sType = .WRITE_DESCRIPTOR_SET
		write.dstSet = bindless.set
		write.descriptorCount = 1
		write.dstArrayElement = handle.index
		write.pBufferInfo = &buffer_info
	}

	i: u32 = 0
	if vk.BufferUsageFlag.UNIFORM_BUFFER in buffer.usage {
		writes[i].dstBinding = UNIFORM_BINDING
		writes[i].descriptorType = .UNIFORM_BUFFER
		i += 1
	}

	if vk.BufferUsageFlag.STORAGE_BUFFER in buffer.usage {writes[i].dstBinding = STORAGE_BINDING
		writes[i].descriptorType = .STORAGE_BUFFER
	}

	vk.UpdateDescriptorSets(ctx.vulkan_state.device, i, raw_data(&writes), 0, nil)

	return handle
}

@(private = "file")
_bindless_remove_buffer :: proc(
	bindless: ^Bindless,
	buffer_h: Buffer_Handle,
	loc := #caller_location,
) -> (
	Buffer,
	bool,
) {
	assert_not_nil(bindless, loc)

	return hm.remove(&bindless.buffers, buffer_h)
}
