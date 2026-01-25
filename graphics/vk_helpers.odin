package graphics

import vk "vendor:vulkan"

@(private)
_find_memory_type :: proc(
	physical_device: vk.PhysicalDevice,
	type_filter: u32,
	properties: vk.MemoryPropertyFlags,
) -> (
	memory_type: u32,
	ok: bool,
) {
	mem_property: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(physical_device, &mem_property)

	for i: u32 = 0; i < mem_property.memoryTypeCount; i += 1 {
		if (type_filter & (1 << i) != 0) && (mem_property.memoryTypes[i].propertyFlags >= properties) {
			return i, true
		}
	}

	return 0, false
}

@(private)
_find_supported_format :: proc(
	physical_device: vk.PhysicalDevice,
	candidates: []vk.Format,
	tiling: vk.ImageTiling,
	features: vk.FormatFeatureFlags,
) -> vk.Format {
	for format in candidates {
		props: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(physical_device, format, &props)

		if (tiling == .OPTIMAL && (props.optimalTilingFeatures & features) == features) {
			return format
		} else if (tiling == .LINEAR && (props.optimalTilingFeatures & features) == features) {
			return format
		}
	}

	panic("failed to find supported format!")
}

@(private)
QueueFamilyIndices :: struct {
	graphics: Maybe(u32),
	present:  Maybe(u32),
}

@(private)
_find_queue_families :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> (ids: QueueFamilyIndices) {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, nil)

	families := make([]vk.QueueFamilyProperties, count, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, raw_data(families))

	for family, i in families {
		if .GRAPHICS in family.queueFlags && .COMPUTE in family.queueFlags {
			ids.graphics = cast(u32)i
		}

		supported: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), surface, &supported)
		if supported {
			ids.present = cast(u32)i
		}

		_, has_graphics := ids.graphics.?
		_, has_present := ids.present.?

		if has_graphics && has_present {
			break
		}
	}

	return
}

@(private)
Swapchain_Support :: struct {
	capabilities: vk.SurfaceCapabilitiesKHR,
	formats:      []vk.SurfaceFormatKHR,
	presentModes: []vk.PresentModeKHR,
}

@(private)
_query_swapchain_support :: proc(
	device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	allocator := context.temp_allocator,
) -> (
	support: Swapchain_Support,
	result: vk.Result,
) {
	// NOTE: looks like a wrong binding with the third arg being a multipointer.
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &support.capabilities) or_return

	{
		count: u32
		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &count, nil) or_return

		support.formats = make([]vk.SurfaceFormatKHR, count, allocator)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &count, raw_data(support.formats)) or_return
	}

	{
		count: u32
		vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &count, nil) or_return

		support.presentModes = make([]vk.PresentModeKHR, count, allocator)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &count, raw_data(support.presentModes)) or_return
	}

	return
}
