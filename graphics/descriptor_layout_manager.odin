package graphics

import sm "core:container/small_array"
import "core:hash"
import "core:log"
import vk "vendor:vulkan"

Pipeline_Layout_Info :: struct {
	layout_infos:  Pipeline_Set_Layout_Infos,
	push_constant: Maybe(Push_Constant_Range),
}

Descriptor_Layout_Manager :: struct {
	layouts:           map[Pipeline_Set_Layout_Info]vk.DescriptorSetLayout,
	pipeline_layoutes: map[Pipeline_Layout_Info]vk.PipelineLayout,
}

_destroy_descriptor_layout_manager :: proc() {
	for k, layout in ctx.descriptor_layout_manager.layouts {
		vk.DestroyDescriptorSetLayout(ctx.vulkan_state.device, layout, nil)
	}

	for k, pipeline_layout in ctx.descriptor_layout_manager.pipeline_layoutes {
		vk.DestroyPipelineLayout(ctx.vulkan_state.device, pipeline_layout, nil)
	}

	delete(ctx.descriptor_layout_manager.layouts)
	delete(ctx.descriptor_layout_manager.pipeline_layoutes)
}

@(require_results)
get_descriptor_set_layouts :: proc(infos: Pipeline_Set_Layout_Infos) -> (layouts: Descriptor_Set_Layouts) {
	for i in 0 ..< infos.len {
		sm.push(&layouts, get_descriptor_set_layout(infos.data[i]))
	}

	return
}

@(require_results)
get_descriptor_set_layout :: proc(info: Pipeline_Set_Layout_Info) -> vk.DescriptorSetLayout {
	layout, ok := ctx.descriptor_layout_manager.layouts[info]
	if ok do return layout

	layout = _set_info_to_descriptor_set_layout(info)
	ctx.descriptor_layout_manager.layouts[info] = layout

	return layout
}

@(require_results)
get_pipeline_layout :: proc(info: Pipeline_Layout_Info) -> vk.PipelineLayout {
	pipeline_layout, ok := ctx.descriptor_layout_manager.pipeline_layoutes[info]
	if ok do return pipeline_layout
	layouts := get_descriptor_set_layouts(info.layout_infos)

	pipeline_layout = _create_pipeline_layout(layouts, info.push_constant)
	ctx.descriptor_layout_manager.pipeline_layoutes[info] = pipeline_layout

	return pipeline_layout
}

@(private = "file")
@(require_results)
_set_info_to_descriptor_set_layout :: proc(set_info: Pipeline_Set_Layout_Info) -> vk.DescriptorSetLayout {
	descriptor_bindings: sm.Small_Array(MAX_PIPELINE_BINDING_COUNT, vk.DescriptorSetLayoutBinding)
	flags_array: sm.Small_Array(MAX_PIPELINE_BINDING_COUNT, vk.DescriptorBindingFlags)

	use_binding_flags := false

	for i in 0 ..< set_info.binding_infos.len {
		binding := set_info.binding_infos.data[i]
		sm.push(
			&descriptor_bindings,
			vk.DescriptorSetLayoutBinding {
				binding = binding.binding,
				descriptorType = binding.descriptor_type,
				descriptorCount = binding.descriptor_count,
				stageFlags = binding.stage_flags,
				pImmutableSamplers = nil,
			},
		)

		flags, has_flags := binding.flags.?
		if has_flags {
			use_binding_flags = true
			sm.push(&flags_array, flags)
		} else {
			sm.push(&flags_array, vk.DescriptorBindingFlags{})
		}
	}

	p_binding_flags: ^vk.DescriptorSetLayoutBindingFlagsCreateInfo = nil

	if use_binding_flags {
		binding_flags := vk.DescriptorSetLayoutBindingFlagsCreateInfo {
			sType         = .DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
			pNext         = nil,
			pBindingFlags = raw_data(sm.slice(&flags_array)),
			bindingCount  = cast(u32)flags_array.len,
		}
		p_binding_flags = &binding_flags
	}

	descriptor_set_layout := vk.DescriptorSetLayout{}

	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		pNext        = p_binding_flags,
		bindingCount = cast(u32)descriptor_bindings.len,
		pBindings    = raw_data(sm.slice(&descriptor_bindings)),
		flags        = {.UPDATE_AFTER_BIND_POOL},
	}

	must(
		vk.CreateDescriptorSetLayout(ctx.vulkan_state.device, &layout_info, nil, &descriptor_set_layout),
		"failed to create descriptor set layout!",
	)

	return descriptor_set_layout
}

@(private = "file")
@(require_results)
_create_pipeline_layout :: proc(
	descriptor_set_layouts: Descriptor_Set_Layouts,
	push_constant: Maybe(vk.PushConstantRange) = nil,
) -> vk.PipelineLayout {
	descriptor_set_layouts := descriptor_set_layouts
	push, has_push := push_constant.?

	pipeline_layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = cast(u32)descriptor_set_layouts.len,
		pSetLayouts            = raw_data(sm.slice(&descriptor_set_layouts)),
		pushConstantRangeCount = 1 if has_push else 0,
		pPushConstantRanges    = &push,
	}
	layout := vk.PipelineLayout{}
	must(vk.CreatePipelineLayout(ctx.vulkan_state.device, &pipeline_layout_info, nil, &layout))

	return layout
}

@(private = "file")
_destroy_descriptor_set_layout :: proc(descriptor_set_layout: vk.DescriptorSetLayout) {
	vk.DestroyDescriptorSetLayout(ctx.vulkan_state.device, descriptor_set_layout, nil)
}
