package graphics

import sm "core:container/small_array"
import vk "vendor:vulkan"
// Inpute_Attachment_Drawer :: struct {
// }
//
// init_inpute_attachment_drawer :: proc(inpute: ^Inpute_Attachment_Drawer) {
// }

// draw_inpute_attachment_draw(inpute: ^Inpute_Attachment)

draw_inpute_attachment_draw :: proc() {

}

create_inpute_attachment_pipeline_set_info :: proc(allocator := context.allocator) -> Pipeline_Set_Layout_Info {
	binding_infos := Pipeline_Set_Binding_Infos{}

	sm.push(
		&binding_infos,
		Pipeline_Set_Binding_Info {
			binding = 0,
			descriptor_type = .INPUT_ATTACHMENT,
			descriptor_count = 1,
			stage_flags = {.FRAGMENT},
		},
	)

	return Pipeline_Set_Layout_Info{binding_infos = binding_infos}
}

surface_create_descriptor_set_layout :: proc(set: u32) -> vk.DescriptorSetLayout {
	descriptor_binding := vk.DescriptorSetLayoutBinding{}
	descriptor_binding.binding = 0
	descriptor_binding.descriptorType = .INPUT_ATTACHMENT
	descriptor_binding.descriptorCount = 1
	descriptor_binding.stageFlags = {.FRAGMENT}

	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings    = &descriptor_binding,
		flags        = {.UPDATE_AFTER_BIND_POOL},
	}

	layout: vk.DescriptorSetLayout

	must(vk.CreateDescriptorSetLayout(ctx.vulkan_state.device, &create_info, nil, &layout))


	return layout
}


// init_inpute_
