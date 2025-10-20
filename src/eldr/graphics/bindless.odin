package graphics

import hm "../handle_map"
import "base:intrinsics"
import "base:runtime"
import "core:log"
import "core:math"
import "core:slice"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"
import "vma"

DESCRIPTOR_COUNT :: 1000

UNIFORM_BINDING :: 0
STORAGE_BINDING :: 1
TEXTURE_BINDING :: 2

Texture_Handle :: distinct hm.Handle
Buffer_Handle :: distinct hm.Handle

Bindless :: struct {
	set:        vk.DescriptorSet,
	set_layout: vk.DescriptorSetLayout,
	textures:   hm.Handle_Map(Texture, Texture_Handle),
	buffers:    hm.Handle_Map(Buffer, Buffer_Handle),
}

bindless_store_texture :: proc(g: ^Graphics, texture: Texture) -> Texture_Handle {
	return _bindless_store_texture(g.bindless, g.device, texture)
}

bindless_destroy_texture :: proc(g: ^Graphics, texture_h: Texture_Handle) -> bool {
	texture, has_texture := _bindless_remove_texture(g.bindless, texture_h)
	if has_texture {
		destroy_texture(g, &texture)
		return true
	}

	return false
}

bindless_store_buffer :: proc(g: ^Graphics, buffer: Buffer) -> Buffer_Handle {
	return _bindless_store_buffer(g.bindless, g.device, buffer)
}

bindless_destroy_buffer :: proc(g: ^Graphics, buffer_h: Buffer_Handle) {
	buffer, has_buffer := _bindless_remove_buffer(g.bindless, buffer_h)
	if has_buffer {
		destroy_buffer(g, &buffer)
	}
}

bindless_get_buffer :: proc(g: ^Graphics, buffer_h: Buffer_Handle) -> ^Buffer {
	result, ok := hm.get(&g.bindless.buffers, buffer_h)
	if !ok {
		log.error("couln't get buffer by handle ", buffer_h)
		return nil
	}

	return result
}

create_bindless_pipeline_set_info :: proc(allocator := context.allocator) -> Pipeline_Set_Info {
	binding_infos := make([]Pipeline_Set_Binding_Info, 3, allocator)
	binding_infos[0].binding = UNIFORM_BINDING
	binding_infos[0].descriptor_type = .UNIFORM_BUFFER
	binding_infos[0].descriptor_count = DESCRIPTOR_COUNT
	binding_infos[0].stage_flags = vk.ShaderStageFlags_ALL_GRAPHICS

	binding_infos[1].binding = STORAGE_BINDING
	binding_infos[1].descriptor_type = .STORAGE_BUFFER
	binding_infos[1].descriptor_count = DESCRIPTOR_COUNT
	binding_infos[1].stage_flags = vk.ShaderStageFlags_ALL_GRAPHICS

	binding_infos[2].binding = TEXTURE_BINDING
	binding_infos[2].descriptor_type = .COMBINED_IMAGE_SAMPLER
	binding_infos[2].descriptor_count = DESCRIPTOR_COUNT
	binding_infos[2].stage_flags = vk.ShaderStageFlags_ALL_GRAPHICS

	flags := make([]vk.DescriptorBindingFlags, 3)
	flags[0] = {.UPDATE_AFTER_BIND, .PARTIALLY_BOUND}
	flags[1] = {.UPDATE_AFTER_BIND, .PARTIALLY_BOUND}
	flags[2] = {.UPDATE_AFTER_BIND, .PARTIALLY_BOUND}

	return Pipeline_Set_Info{set = 0, binding_infos = binding_infos, flags = flags}
}

bindless_get_texture :: proc(g: ^Graphics, texture_h: Texture_Handle) -> (^Texture, bool) {
	return hm.get(&g.bindless.textures, texture_h)
}

bindless_bind :: proc(g: ^Graphics, cmd: vk.CommandBuffer, pipeline_layout: vk.PipelineLayout) {
	vk.CmdBindDescriptorSets(cmd, .GRAPHICS, pipeline_layout, 0, 1, &g.bindless.set, 0, nil)
}

_bindless_init :: proc(bindless: ^Bindless, device: vk.Device, descriptor_pool: vk.DescriptorPool) {
	descriptor_types := [3]vk.DescriptorType{.UNIFORM_BUFFER, .STORAGE_BUFFER, .COMBINED_IMAGE_SAMPLER}
	descriptor_bindings: [3]vk.DescriptorSetLayoutBinding
	descriptor_binding_flags: [3]vk.DescriptorBindingFlags

	for i in 0 ..< 3 {
		descriptor_bindings[i].binding = cast(u32)i
		descriptor_bindings[i].descriptorType = descriptor_types[i]
		descriptor_bindings[i].descriptorCount = DESCRIPTOR_COUNT
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

	must(vk.CreateDescriptorSetLayout(device, &create_info, nil, &bindless.set_layout))

	allocate_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		pNext              = nil,
		descriptorPool     = descriptor_pool,
		pSetLayouts        = &bindless.set_layout,
		descriptorSetCount = 1,
	}

	must(vk.AllocateDescriptorSets(device, &allocate_info, &bindless.set))
}

_bindless_destroy :: proc(bindless: ^Bindless, device: vk.Device, allocator: vma.Allocator) {
	vk.DestroyDescriptorSetLayout(device, bindless.set_layout, nil)

	for &texture in bindless.textures.values {
		_destroy_texture_from_device(device, allocator, &texture)
	}
	hm.destroy(&bindless.textures)

	for &buffer in bindless.buffers.values {
		_destroy_buffer_from_allocator(allocator, &buffer)
	}
	hm.destroy(&bindless.buffers)
}

_bindless_bind :: proc(bindless: ^Bindless, cmd: vk.CommandBuffer, pipeline_layout: vk.PipelineLayout) {
	vk.CmdBindDescriptorSets(cmd, .GRAPHICS, pipeline_layout, 0, 1, &bindless.set, 0, nil)
}

_bindless_store_texture :: proc(bindless: ^Bindless, device: vk.Device, texture: Texture) -> Texture_Handle {
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
	vk.UpdateDescriptorSets(device, 1, &write, 0, nil)

	return handle
}

_bindless_remove_texture :: proc(bindless: ^Bindless, texture_h: Texture_Handle) -> (Texture, bool) {
	return hm.remove(&bindless.textures, texture_h)
}

_bindless_store_buffer :: proc(bindless: ^Bindless, device: vk.Device, buffer: Buffer) -> Buffer_Handle {
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

	vk.UpdateDescriptorSets(device, i, raw_data(&writes), 0, nil)

	return handle
}

_bindless_remove_buffer :: proc(bindless: ^Bindless, buffer_h: Buffer_Handle) -> (Buffer, bool) {
	return hm.remove(&bindless.buffers, buffer_h)
}
