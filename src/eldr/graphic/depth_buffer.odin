package graphic

import "base:intrinsics"
import "base:runtime"

import "core:log"
import "core:slice"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

find_depth_format :: proc(physical_device: vk.PhysicalDevice) -> vk.Format {
	return find_supported_format(
		physical_device,
		{.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT},
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT},
	)
}

has_stancil_component :: proc(format: vk.Format) -> bool {
	return format == .D32_SFLOAT_S8_UINT || format == .D24_UNORM_S8_UINT
}

create_depth_resources :: proc(g: ^Graphic) -> TextureImage {
	format := find_depth_format(g.physical_device)
	image, memory := create_image(
		g,
		g.swapchain.extent.width,
		g.swapchain.extent.height,
		1,
		g.msaa_samples,
		format,
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT},
		{.DEVICE_LOCAL},
	)

	transition_image_layout(g, image, {.DEPTH}, format, .UNDEFINED, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL, 1)

	view := create_image_view(g.device, image, format, {.DEPTH}, 1)

	return TextureImage{image, view, memory}
}
