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
ctx: Graphics
@(private)
g_ctx: runtime.Context // used for system callback procedures

init :: proc(init_info: Graphics_Init_Info, window: ^glfw.WindowHandle) {
	g_ctx = context

	ctx.initialized = true
	ctx.window = window

	_init_vulkan_state()
	ctx.cmd = _create_draw_command_buffers(ctx.vulkan_state) // TODO:
	_init_limits()

	_init_pipeline_manager(ODIN_DEBUG)
	_init_surface_manager()
	_init_sync_obj()
	_init_swapchain(init_info.swapchain_sample_count)
	_init_deffered_destructor()
	_init_bindless()
	_init_temp_pools()
	_init_buildin_resources()
}

destroy :: proc() {
	_destroy_buildin()
	_destroy_temp_pools()
	_destroy_bindless()
	_destroy_deffered_destructor()
	_destroy_descriptor_layout_manager()
	_destroy_sync_obj()
	_destroy_swapchain()
	_destroy_pipeline_manager()
	_destroy_surface_manager()
	_destroy_vulkan_state()

	ctx = Graphics{}
}

@(private = "file")
_init_vulkan_state :: proc() {
	_create_instance()
	_create_surface()
	_pick_physical_device()
	_create_logical_device()
	_create_vma_allocator()
	_create_descriptor_pool()
	_create_command_pool()
}

@(private = "file")
_destroy_vulkan_state :: proc() {
	vma.DestroyAllocator(ctx.vulkan_state.allocator)
	_destroy_command_pool()
	_destroy_descriptor_pool()

	_destroy_logical_device()
	_destroy_surface()
	_destroy_instance()
	delete(ctx.vulkan_state.enabled_layer_names)
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
_create_instance :: proc() {
	vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))
	assert(vk.CreateInstance != nil, "vulkan function pointers not loaded")

	instance_info := vk.InstanceCreateInfo {
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

	extensions := slice.clone_to_dynamic(glfw.GetRequiredInstanceExtensions(), context.temp_allocator)

	// MacOS is a special snowflake ;)
	when ODIN_OS == .Darwin {
		create_info.flags |= {.ENUMERATE_PORTABILITY_KHR}
		append(&extensions, vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
	}

	when ENABLE_VALIDATION_LAYERS {
		ctx.vulkan_state.enabled_layer_names = make([]cstring, 1)
		ctx.vulkan_state.enabled_layer_names[0] = "VK_LAYER_KHRONOS_validation"
		instance_info.ppEnabledLayerNames = raw_data(ctx.vulkan_state.enabled_layer_names)
		instance_info.enabledLayerCount = 1

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
		instance_info.pNext = &dbg_create_info
	}

	instance_info.enabledExtensionCount = u32(len(extensions))
	instance_info.ppEnabledExtensionNames = raw_data(extensions)

	must(vk.CreateInstance(&instance_info, nil, &ctx.vulkan_state.instance))

	vk.load_proc_addresses_instance(ctx.vulkan_state.instance)

	when ENABLE_VALIDATION_LAYERS {
		dbg_messenger: vk.DebugUtilsMessengerEXT
		must(vk.CreateDebugUtilsMessengerEXT(ctx.vulkan_state.instance, &dbg_create_info, nil, &dbg_messenger))
		ctx.vulkan_state.dbg_messenger = dbg_messenger
	}
}

@(private = "file")
_destroy_instance :: proc() {
	when ENABLE_VALIDATION_LAYERS {
		dbg_messenger, ok := ctx.vulkan_state.dbg_messenger.?
		assert(ok)
		vk.DestroyDebugUtilsMessengerEXT(ctx.vulkan_state.instance, dbg_messenger, nil)
	}
	vk.DestroyInstance(ctx.vulkan_state.instance, nil)
}

@(private = "file")
_create_surface :: proc() {
	must(glfw.CreateWindowSurface(ctx.vulkan_state.instance, ctx.window^, nil, &ctx.vulkan_state.surface))
}

@(private = "file")
_destroy_surface :: proc() {
	vk.DestroySurfaceKHR(ctx.vulkan_state.instance, ctx.vulkan_state.surface, nil)
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
_pick_physical_device :: proc() {
	score_physical_device :: proc(device: vk.PhysicalDevice) -> (score: int) {
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
			support, result := _query_swapchain_support(device, ctx.vulkan_state.surface, context.temp_allocator)
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

		families := _find_queue_families(device, ctx.vulkan_state.surface)
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
	must(vk.EnumeratePhysicalDevices(ctx.vulkan_state.instance, &count, nil))
	if count == 0 {log.panic("vulkan: no GPU found")}

	devices := make([]vk.PhysicalDevice, count, context.temp_allocator)
	must(vk.EnumeratePhysicalDevices(ctx.vulkan_state.instance, &count, raw_data(devices)))


	log.info("////////////////////////////////////////")
	log.info("// START EVALUATING DEVICES")
	log.info("////////////////////////////////////////")
	best_device_score := -1
	for device in devices {
		if score := score_physical_device(device); score > best_device_score {
			ctx.vulkan_state.physical_device = device
			best_device_score = score
		}
	}

	if best_device_score <= 0 {
		log.panic("vulkan: no suitable GPU found")
	}

	vk.GetPhysicalDeviceProperties(ctx.vulkan_state.physical_device, &ctx.vulkan_state.physical_device_property)
}

@(private = "file")
_create_logical_device :: proc() {
	indices := _find_queue_families(ctx.vulkan_state.physical_device, ctx.vulkan_state.surface)
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
		queueCreateInfoCount    = cast(u32)(len(queue_create_infos)),
		enabledLayerCount       = cast(u32)len(ctx.vulkan_state.enabled_layer_names),
		ppEnabledLayerNames     = raw_data(ctx.vulkan_state.enabled_layer_names),
		ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS),
		enabledExtensionCount   = cast(u32)(len(DEVICE_EXTENSIONS)),
	}

	must(vk.CreateDevice(ctx.vulkan_state.physical_device, &device_create_info, nil, &ctx.vulkan_state.device))

	vk.GetDeviceQueue(ctx.vulkan_state.device, indices.graphics.?, 0, &ctx.vulkan_state.graphics_queue)
	vk.GetDeviceQueue(ctx.vulkan_state.device, indices.present.?, 0, &ctx.vulkan_state.present_queue)
}

@(private)
_create_vma_allocator :: proc() {
	vulkan_functions := vma.create_vulkan_functions()
	create_info := vma.AllocatorCreateInfo {
		vulkanApiVersion = VULKAN_API_VERSION,
		physicalDevice   = ctx.vulkan_state.physical_device,
		device           = ctx.vulkan_state.device,
		instance         = ctx.vulkan_state.instance,
		pVulkanFunctions = &vulkan_functions,
	}

	must(vma.CreateAllocator(&create_info, &ctx.vulkan_state.allocator), "failed to create vma.Allocator")
}

@(private = "file")
_destroy_logical_device :: proc() {
	vk.DestroyDevice(ctx.vulkan_state.device, nil)
}

@(private = "file")
_create_command_pool :: proc() {
	indices := _find_queue_families(ctx.vulkan_state.physical_device, ctx.vulkan_state.surface)
	pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = indices.graphics.?,
	}
	must(vk.CreateCommandPool(ctx.vulkan_state.device, &pool_info, nil, &ctx.vulkan_state.command_pool))
}

@(private = "file")
_destroy_command_pool :: proc() {
	vk.DestroyCommandPool(ctx.vulkan_state.device, ctx.vulkan_state.command_pool, nil)
}

@(private = "file")
_create_draw_command_buffers :: proc(vks: Vulkan_State) -> Command_Buffer {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = vks.command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	cmd: Command_Buffer
	must(vk.AllocateCommandBuffers(vks.device, &alloc_info, &cmd))

	return cmd
}

@(private = "file")
_get_sample_count :: proc(limits: vk.PhysicalDeviceLimits) -> vk.SampleCountFlag {
	counts := limits.framebufferColorSampleCounts
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

_init_limits :: proc() {
	vk_limits := ctx.vulkan_state.physical_device_property.limits

	ctx.limits = Graphics_Limits {
		max_sampler_anisotropy = vk_limits.maxSamplerAnisotropy,
		max_sample_count       = _get_sample_count(vk_limits),
	}
}

@(private = "file")
_init_sync_obj :: proc() {
	sem_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	must(vk.CreateFence(ctx.vulkan_state.device, &fence_info, nil, &ctx.fence))
	must(vk.CreateSemaphore(ctx.vulkan_state.device, &sem_info, nil, &ctx.image_available_semaphore))
}

@(private = "file")
_destroy_sync_obj :: proc() {
	vk.DestroySemaphore(ctx.vulkan_state.device, ctx.image_available_semaphore, nil)
	vk.DestroyFence(ctx.vulkan_state.device, ctx.fence, nil)
}

@(private = "file")
byte_arr_str :: proc(arr: ^[$N]byte) -> string {
	return strings.truncate_to_byte(string(arr[:]), 0)
}

@(private = "file")
_get_physical_device_features :: proc(device: vk.PhysicalDevice, features: ^Physical_Device_Features) {
	features.dynamic_rendering_local_read.sType = .PHYSICAL_DEVICE_DYNAMIC_RENDERING_LOCAL_READ_FEATURES
	features.dynamic_rendering_local_read.dynamicRenderingLocalRead = true

	features.dynamic_rendering.sType = .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES
	features.dynamic_rendering.dynamicRendering = true
	features.dynamic_rendering.pNext = &features.dynamic_rendering_local_read

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
	// DYNAMIC RENDERING LOCAL READ 
	if !features.dynamic_rendering_local_read.dynamicRenderingLocalRead {
		return false, "device does not support dynamic rendering local read"
	}

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
	features.dynamic_rendering_local_read.sType = .PHYSICAL_DEVICE_DYNAMIC_RENDERING_LOCAL_READ_FEATURES
	features.dynamic_rendering_local_read.pNext = nil
	features.dynamic_rendering_local_read.dynamicRenderingLocalRead = true

	// DYNAMIC RENDERING 
	features.dynamic_rendering.sType = .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES
	features.dynamic_rendering.pNext = &features.dynamic_rendering_local_read
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

@(private = "file")
_init_buildin_resources :: proc() {
	ctx.buildin = new(Buildin_Resource)
	ctx.buildin.square = create_square_model()
	ctx.buildin.unit_square = create_square_mesh(1)
	ctx.buildin.text_pipeline_h = _text_default_pipeline()
	ctx.buildin.primitive_pipeline_h = create_primitive_pipeline()
}

@(private = "file")
_destroy_buildin :: proc() {
	delete(ctx.buildin.square.materials)
	ctx.buildin.square.materials = {}
	destroy_model(&ctx.buildin.square)
	destroy_mesh(&ctx.buildin.unit_square)
	free(ctx.buildin)
}
