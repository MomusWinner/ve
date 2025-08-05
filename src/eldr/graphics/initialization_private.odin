#+private
package graphics

import "base:runtime"

import "core:log"
import "core:slice"
import "core:strings"

import "core:os"
import "vendor:glfw"
import vk "vendor:vulkan"

_create_instance :: proc(g: ^Graphics) {
	vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))
	assert(vk.CreateInstance != nil, "vulkan function pointers not loaded")

	create_info := vk.InstanceCreateInfo {
		sType            = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &vk.ApplicationInfo {
			sType = .APPLICATION_INFO,
			pApplicationName = "Hello Triangle",
			applicationVersion = vk.MAKE_VERSION(1, 0, 0),
			pEngineName = "No Engine",
			engineVersion = vk.MAKE_VERSION(1, 0, 0),
			apiVersion = vk.API_VERSION_1_0,
		},
	}
	g.instance_info = create_info

	extensions := slice.clone_to_dynamic(glfw.GetRequiredInstanceExtensions(), context.temp_allocator)

	// MacOS is a special snowflake ;)
	when ODIN_OS == .Darwin {
		create_info.flags |= {.ENUMERATE_PORTABILITY_KHR}
		append(&extensions, vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
	}

	when ENABLE_VALIDATION_LAYERS {
		create_info.ppEnabledLayerNames = raw_data([]cstring{"VK_LAYER_KHRONOS_validation"})
		create_info.enabledLayerCount = 1

		append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

		// Severity based on logger level.
		severity: vk.DebugUtilsMessageSeverityFlagsEXT
		if context.logger.lowest_level <= .Error {
			severity |= {.ERROR}
		}
		if context.logger.lowest_level <= .Warning {
			severity |= {.WARNING}
		}
		if context.logger.lowest_level <= .Info {
			severity |= {.INFO}
		}
		if context.logger.lowest_level <= .Debug {
			severity |= {.VERBOSE}
		}

		dbg_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = severity,
			messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE}, // all of them.
			pfnUserCallback = vk_messenger_callback,
		}
		create_info.pNext = &dbg_create_info
	}

	create_info.enabledExtensionCount = u32(len(extensions))
	create_info.ppEnabledExtensionNames = raw_data(extensions)

	must(vk.CreateInstance(&create_info, nil, &g.instance))

	vk.load_proc_addresses_instance(g.instance)

	when ENABLE_VALIDATION_LAYERS {
		must(vk.CreateDebugUtilsMessengerEXT(g.instance, &dbg_create_info, nil, &g.dbg_messenger))
	}
}

_destroy_instance :: proc(g: ^Graphics) {
	when ENABLE_VALIDATION_LAYERS {
		vk.DestroyDebugUtilsMessengerEXT(g.instance, g.dbg_messenger, nil)
	}
	vk.DestroyInstance(g.instance, nil)
}

_create_surface :: proc(g: ^Graphics) {
	must(glfw.CreateWindowSurface(g.instance, g.window, nil, &g.surface))
}

_destroy_surface :: proc(g: ^Graphics) {
	vk.DestroySurfaceKHR(g.instance, g.surface, nil)
}

_pick_physical_device :: proc(g: ^Graphics) {
	score_physical_device :: proc(g: ^Graphics, device: vk.PhysicalDevice) -> (score: int) {
		props: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(device, &props)

		name := byte_arr_str(&props.deviceName)
		log.infof("-- %q", name)
		defer log.infof(" * device %q scored %v", name, score)

		features: vk.PhysicalDeviceFeatures
		vk.GetPhysicalDeviceFeatures(device, &features)

		if !features.samplerAnisotropy {
			log.info(" ! device does not support anisotropy")
			return 0
		}
		if !features.geometryShader {
			log.info(" ! device does not support geometry shaders")
			return 0
		}

		// Need certain extensions supported.
		{
			extensions, result := physical_device_extensions(device, context.temp_allocator)
			if result != .SUCCESS {
				log.infof(" ! enumerate device extension properties failed: %v", result)
				return 0
			}

			required_loop: for required in DEVICE_EXTENSIONS {
				for &extension in extensions {
					extension_name := byte_arr_str(&extension.extensionName)
					if extension_name == string(required) {
						continue required_loop
					}
				}

				log.infof(" ! device does not support required extension %q", required)
				return 0
			}
		}

		// Check if swapchain is adequately supported.
		{
			support, result := query_swapchain_support(device, g.surface, context.temp_allocator)
			if result != .SUCCESS {
				log.infof(" ! query swapchain support failure: %v", result)
				return 0
			}

			// Need at least a format and present mode.
			if len(support.formats) == 0 || len(support.presentModes) == 0 {
				log.info(" ! device does not support swapchain")
				return 0
			}
		}

		families := find_queue_families(device, g.surface)
		if _, has_graphics := families.graphics.?; !has_graphics {
			log.info(" ! device does not have a graphics queue")
			return 0
		}
		if _, has_present := families.present.?; !has_present {
			log.info(" ! device does not have a presentation queue")
			return 0
		}

		// Favor GPUs.
		switch props.deviceType {
		case .DISCRETE_GPU:
			score += 300_000
		case .INTEGRATED_GPU:
			score += 200_000
		case .VIRTUAL_GPU:
			score += 100_000
		case .CPU, .OTHER:
		}
		log.infof(" * scored %i based on device type %v", score, props.deviceType)

		// Maximum texture size.
		score += int(props.limits.maxImageDimension2D)
		log.infof(
			" * added the max 2D image dimensions (texture size) of %v to the score",
			props.limits.maxImageDimension2D,
		)
		return
	}

	count: u32
	must(vk.EnumeratePhysicalDevices(g.instance, &count, nil))
	if count == 0 {log.panic("vulkan: no GPU found")}

	devices := make([]vk.PhysicalDevice, count, context.temp_allocator)
	must(vk.EnumeratePhysicalDevices(g.instance, &count, raw_data(devices)))


	log.info("////////////////////////////////////////")
	log.info("// START EVALUATING DEVICES")
	log.info("////////////////////////////////////////")
	best_device_score := -1
	for device in devices {
		if score := score_physical_device(g, device); score > best_device_score {
			g.physical_device = device
			best_device_score = score
		}
	}

	if best_device_score <= 0 {
		log.panic("vulkan: no suitable GPU found")
	}

	vk.GetPhysicalDeviceProperties(g.physical_device, &g.physical_device_property)
	g.msaa_samples = {get_sample_count(g.physical_device_property)}
}

_create_logical_device :: proc(g: ^Graphics) {
	indices := find_queue_families(g.physical_device, g.surface)
	// TODO: this is kinda messy.
	indices_set := make(map[u32]struct {
		}, allocator = context.temp_allocator)
	indices_set[indices.graphics.?] = {}
	indices_set[indices.present.?] = {}

	queue_create_infos := make([dynamic]vk.DeviceQueueCreateInfo, 0, len(indices_set), context.temp_allocator)
	for _ in indices_set {
		append(
			&queue_create_infos,
			vk.DeviceQueueCreateInfo {
				sType = .DEVICE_QUEUE_CREATE_INFO,
				queueFamilyIndex = indices.graphics.?,
				queueCount = 1,
				pQueuePriorities = raw_data([]f32{1}),
			}, // Scheduling priority between 0 and 1.
		)
	}

	deviceFeatrues := vk.PhysicalDeviceFeatures {
		samplerAnisotropy = true,
	}

	device_create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		pQueueCreateInfos       = raw_data(queue_create_infos),
		queueCreateInfoCount    = u32(len(queue_create_infos)),
		enabledLayerCount       = g.instance_info.enabledLayerCount,
		ppEnabledLayerNames     = g.instance_info.ppEnabledLayerNames,
		ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS),
		pEnabledFeatures        = &deviceFeatrues,
		enabledExtensionCount   = u32(len(DEVICE_EXTENSIONS)),
	}

	must(vk.CreateDevice(g.physical_device, &device_create_info, nil, &g.device))

	vk.GetDeviceQueue(g.device, indices.graphics.?, 0, &g.graphics_queue)
	vk.GetDeviceQueue(g.device, indices.present.?, 0, &g.present_queue)
}
