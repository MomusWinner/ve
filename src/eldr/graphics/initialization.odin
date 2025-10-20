package graphics

import "../common"
import "base:runtime"
import "core:log"
import "core:os"
import "core:slice"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"
import "vma"

when ODIN_OS == .Darwin {
	// NOTE: just a bogus import of the system library,
	// needed so we can add a linker flag to point to /usr/local/lib (where vulkan is installed by default)
	// when trying to load vulkan.
	@(require, extra_linker_flags = "-rpath /usr/local/lib")
	foreign import __ "system:System.framework"
}

@(private)
g_ctx: runtime.Context // used for system procedures

set_logger :: proc(logger: log.Logger) {
	context.logger = logger
	g_ctx = context
}

init_graphic :: proc(g: ^Graphics, window: glfw.WindowHandle) {
	g.window = window

	g.pipeline_manager = new(Pipeline_Manager)
	_pipeline_manager_init(g.pipeline_manager, ODIN_DEBUG)
	g.surface_manager = new(Surface_Manager)
	_surface_manager_init(g.surface_manager)
	_create_instance(g)
	_create_surface(g)
	_pick_physical_device(g)
	_create_logical_device(g)
	_create_vma_allocator(g)
	g.swapchain = _swapchain_new(g.window, g.allocator, g.physical_device, g.device, g.surface, g.msaa_samples)
	_create_descriptor_pool(g)
	_create_command_pool(g)

	_create_draw_command_buffers(g)
	_create_sync_obj(g)

	sc := _cmd_single_begin(g)
	_swapchain_setup(g.swapchain, sc.command_buffer)
	_cmd_single_end(sc)

	g.deffered_destructor = new(Deferred_Destructor)

	g.bindless = new(Bindless)
	_bindless_init(g.bindless, g.device, g.descriptor_pool)

	g.temp_material_pool = new(Temp_Material_Pool)
	_init_temp_material_pool(g, g.temp_material_pool, 100)
	g.temp_transform_pool = new(Temp_Transform_Pool)
	_init_temp_transform_pool(g, g.temp_transform_pool, 100)

	g.buildin = new(Buildin_Resource)
	init_buildin_resources(g, g.buildin)
}

destroy_graphic :: proc(g: ^Graphics) {
	destroy_buildin(g, g.buildin)
	free(g.buildin)

	_destroy_temp_material_pool(g, g.temp_material_pool)
	free(g.temp_material_pool)
	_destroy_temp_transform_pool(g, g.temp_transform_pool)
	free(g.temp_transform_pool)

	// destroy_shape_collection(g, g.buildin.sq)
	// free(g.shapes)

	_bindless_destroy(g.bindless, g.device, g.allocator)
	free(g.bindless)

	destroy_deffered_destructor(g)
	free(g.deffered_destructor)

	_destroy_sync_obj(g)
	_destroy_command_pool(g)
	_destroy_descriptor_pool(g)
	_swapchain_destroy(g.swapchain)
	vma.DestroyAllocator(g.allocator)
	_pipeline_manager_destroy(g.pipeline_manager, g.device)
	free(g.pipeline_manager)
	_surface_manager_destroy(g.surface_manager, g)
	free(g.surface_manager)
	_destroy_logical_device(g)
	_destroy_surface(g)
	_destroy_instance(g)

	free(g)
}

@(private = "file")
_vk_messenger_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = g_ctx

	level: log.Level
	if .ERROR in messageSeverity {
		level = .Error
	} else if .WARNING in messageSeverity {
		level = .Warning
	} else if .INFO in messageSeverity {
		level = .Info
	} else {
		level = .Debug
	}

	log.logf(level, "VULKAN: %s", pCallbackData.pMessage)
	return false
}

@(private = "file")
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
			apiVersion = VULKAN_API_VERSION,
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
			pfnUserCallback = _vk_messenger_callback,
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

@(private = "file")
_destroy_instance :: proc(g: ^Graphics) {
	when ENABLE_VALIDATION_LAYERS {
		vk.DestroyDebugUtilsMessengerEXT(g.instance, g.dbg_messenger, nil)
	}
	vk.DestroyInstance(g.instance, nil)
}

@(private = "file")
_create_surface :: proc(g: ^Graphics) {
	must(glfw.CreateWindowSurface(g.instance, g.window, nil, &g.surface))
}

@(private = "file")
_destroy_surface :: proc(g: ^Graphics) {
	vk.DestroySurfaceKHR(g.instance, g.surface, nil)
}

@(private = "file")
_get_sample_count :: proc(properties: vk.PhysicalDeviceProperties) -> vk.SampleCountFlag {
	counts := properties.limits.framebufferColorSampleCounts
	if ._64 in counts {
		return ._64
	} else if ._32 in counts {
		return ._32
	} else if ._16 in counts {
		return ._16
	} else if ._8 in counts {
		return ._8
	} else if ._4 in counts {
		return ._4
	} else if ._2 in counts {
		return ._2
	}

	return ._1
}

@(private = "file")
_physical_device_extensions :: proc(
	device: vk.PhysicalDevice,
	allocator := context.temp_allocator,
) -> (
	exts: []vk.ExtensionProperties,
	res: vk.Result,
) {
	count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, nil) or_return

	exts = make([]vk.ExtensionProperties, count, allocator)
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, raw_data(exts)) or_return

	return
}

@(private = "file")
_pick_physical_device :: proc(g: ^Graphics) {
	score_physical_device :: proc(g: ^Graphics, device: vk.PhysicalDevice) -> (score: int) {
		features: Physical_Device_Features
		_get_physical_device_features(device, &features)
		success, msg := _validate_physical_device_features(features)
		if !success {
			log.info(" !", msg)
			return 0
		}

		props: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(device, &props)

		name := byte_arr_str(&props.deviceName)
		log.infof("-- %q", name)
		defer log.infof(" * device %q scored %v", name, score)

		// Need certain extensions supported.
		{
			extensions, result := _physical_device_extensions(device, context.temp_allocator)
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
			support, result := _query_swapchain_support(device, g.surface, context.temp_allocator)
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

		families := _find_queue_families(device, g.surface)
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
	g.msaa_samples = {_get_sample_count(g.physical_device_property)}
}

@(private = "file")
_create_logical_device :: proc(g: ^Graphics) {
	indices := _find_queue_families(g.physical_device, g.surface)
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

	features: Physical_Device_Features

	get_required_physical_device_features(&features)

	device_create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &features.features,
		pQueueCreateInfos       = raw_data(queue_create_infos),
		queueCreateInfoCount    = u32(len(queue_create_infos)),
		enabledLayerCount       = g.instance_info.enabledLayerCount,
		ppEnabledLayerNames     = g.instance_info.ppEnabledLayerNames,
		ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS),
		enabledExtensionCount   = u32(len(DEVICE_EXTENSIONS)),
	}

	must(vk.CreateDevice(g.physical_device, &device_create_info, nil, &g.device))

	vk.GetDeviceQueue(g.device, indices.graphics.?, 0, &g.graphics_queue)
	vk.GetDeviceQueue(g.device, indices.present.?, 0, &g.present_queue)
}

@(private)
_create_vma_allocator :: proc(g: ^Graphics) {
	vulkan_functions := vma.create_vulkan_functions()
	create_info := vma.AllocatorCreateInfo {
		vulkanApiVersion = VULKAN_API_VERSION,
		physicalDevice   = g.physical_device,
		device           = g.device,
		instance         = g.instance,
		pVulkanFunctions = &vulkan_functions,
	}

	must(vma.CreateAllocator(&create_info, &g.allocator), "failed to create vma.Allocator")
}

@(private = "file")
_destroy_logical_device :: proc(g: ^Graphics) {
	vk.DestroyDevice(g.device, nil)
}

@(private = "file")
_create_command_pool :: proc(g: ^Graphics) {
	indices := _find_queue_families(g.physical_device, g.surface)
	pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = indices.graphics.?,
	}
	must(vk.CreateCommandPool(g.device, &pool_info, nil, &g.command_pool))
}

@(private = "file")
_destroy_command_pool :: proc(g: ^Graphics) {
	vk.DestroyCommandPool(g.device, g.command_pool, nil)
}

@(private = "file")
_create_draw_command_buffers :: proc(g: ^Graphics) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = g.command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	must(vk.AllocateCommandBuffers(g.device, &alloc_info, &g.cmd))
}

@(private = "file")
_create_sync_obj :: proc(g: ^Graphics) {
	sem_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	must(vk.CreateFence(g.device, &fence_info, nil, &g.fence))
	must(vk.CreateSemaphore(g.device, &sem_info, nil, &g.image_available_semaphore))
}

@(private = "file")
_destroy_sync_obj :: proc(g: ^Graphics) {
	vk.DestroySemaphore(g.device, g.image_available_semaphore, nil)
	vk.DestroyFence(g.device, g.fence, nil)
}

@(private = "file")
byte_arr_str :: proc(arr: ^[$N]byte) -> string {
	return strings.truncate_to_byte(string(arr[:]), 0)
}

@(private = "file")
_get_physical_device_features :: proc(device: vk.PhysicalDevice, features: ^Physical_Device_Features) {
	features.dynamic_rendering.sType = .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES
	features.dynamic_rendering.dynamicRendering = true

	features.descriptor_indexing.sType = .PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES
	features.descriptor_indexing.pNext = &features.dynamic_rendering

	features.synchronization.sType = .PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES
	features.synchronization.pNext = &features.descriptor_indexing

	features.features.sType = .PHYSICAL_DEVICE_FEATURES_2
	features.features.pNext = &features.synchronization

	vk.GetPhysicalDeviceFeatures2(device, &features.features)
}

@(private = "file")
_validate_physical_device_features :: proc(features: Physical_Device_Features) -> (bool, string) {
	// DYNAMIC RENDERING 
	if !features.dynamic_rendering.dynamicRendering {
		return false, "device does not support dynamic rendering"
	}

	// DESCRIPTOR INDEXING
	if !features.descriptor_indexing.shaderSampledImageArrayNonUniformIndexing {
		return false, "device does not support descriptor indexing shaderSampledImageArrayNonUniformIndexing"
	}
	if !features.descriptor_indexing.descriptorBindingSampledImageUpdateAfterBind {
		return false, "device does not support descriptor indexing descriptorBindingSampledImageUpdateAfterBind"
	}
	if !features.descriptor_indexing.shaderUniformBufferArrayNonUniformIndexing {
		return false, "device does not support descriptor indexing shaderUniformBufferArrayNonUniformIndexing"
	}
	if !features.descriptor_indexing.descriptorBindingUniformBufferUpdateAfterBind {
		return false, "device does not support descriptor indexing descriptorBindingUniformBufferUpdateAfterBind"
	}
	if !features.descriptor_indexing.shaderStorageBufferArrayNonUniformIndexing {
		return false, "device does not support descriptor indexing  shaderStorageBufferArrayNonUniformIndexing"
	}
	if !features.descriptor_indexing.descriptorBindingStorageBufferUpdateAfterBind {
		return false, "device does not support descriptor indexing descriptorBindingStorageBufferUpdateAfterBind"
	}
	if !features.descriptor_indexing.runtimeDescriptorArray {
		return false, "device does not support descriptor indexing runtimeDescriptorArray"
	}
	if !features.descriptor_indexing.descriptorBindingPartiallyBound {
		return false, "device does not support descriptor indexing descriptorBindingPartiallyBound"
	}

	// SYNCHRONIZATION 2
	if !features.synchronization.synchronization2 {
		return false, "device does not support synchronization2"
	}

	// FEATURES
	if !features.features.features.samplerAnisotropy {
		return false, "device does not support anisotropy"
	}
	if !features.features.features.geometryShader {
		return false, "device does not support geometry shaders"
	}

	return true, ""
}

get_required_physical_device_features :: proc(features: ^Physical_Device_Features) {
	// DYNAMIC RENDERING 
	features.dynamic_rendering.sType = .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES
	features.dynamic_rendering.pNext = nil
	features.dynamic_rendering.dynamicRendering = true

	// DESCRIPTOR INDEXING
	features.descriptor_indexing.sType = .PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES
	features.descriptor_indexing.pNext = &features.dynamic_rendering
	features.descriptor_indexing.shaderSampledImageArrayNonUniformIndexing = true
	features.descriptor_indexing.descriptorBindingSampledImageUpdateAfterBind = true
	features.descriptor_indexing.shaderUniformBufferArrayNonUniformIndexing = true
	features.descriptor_indexing.descriptorBindingUniformBufferUpdateAfterBind = true
	features.descriptor_indexing.shaderStorageBufferArrayNonUniformIndexing = true
	features.descriptor_indexing.descriptorBindingStorageBufferUpdateAfterBind = true
	features.descriptor_indexing.runtimeDescriptorArray = true
	features.descriptor_indexing.descriptorBindingPartiallyBound = true

	// SYNCHRONIZATION2
	features.synchronization.sType = .PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES
	features.synchronization.pNext = &features.descriptor_indexing
	features.synchronization.synchronization2 = true

	// FEATURES
	features.features.sType = .PHYSICAL_DEVICE_FEATURES_2
	features.features.pNext = &features.synchronization
	features.features.features.geometryShader = true
	features.features.features.samplerAnisotropy = true
}

init_buildin_resources :: proc(g: ^Graphics, buildin: ^Buildin_Resource) {
	buildin.square = create_square(g)
	buildin.text_pipeline_h = _text_default_pipeline(g)
	buildin.primitive_pipeline_h = create_primitive_pipeline(g)
}

destroy_buildin :: proc(g: ^Graphics, buildin: ^Buildin_Resource) {
	destroy_model(g, &buildin.square)
}
