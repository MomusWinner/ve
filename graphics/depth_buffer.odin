#+private
package graphics

import vk "vendor:vulkan"

_find_depth_format :: proc(physical_device: vk.PhysicalDevice) -> vk.Format {
	return _find_supported_format(
		physical_device,
		{.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT},
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT},
	)
}

_has_stancil_component :: proc(format: vk.Format) -> bool {
	return format == .D32_SFLOAT_S8_UINT || format == .D24_UNORM_S8_UINT
}
