package graphics

import "core:strings"
import vk "vendor:vulkan"

@(private)
_set_debug_object_name :: #force_inline proc(handle: u64, type: vk.ObjectType, name: string) {
	when ENABLE_VALIDATION_LAYERS {
		name_info := vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectType   = type,
			objectHandle = handle,
			pObjectName  = strings.clone_to_cstring(name, context.temp_allocator),
		}
		vk.SetDebugUtilsObjectNameEXT(ctx.vulkan_state.device, &name_info)
	}
}
