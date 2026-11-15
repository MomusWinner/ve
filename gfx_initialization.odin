package ve

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:strings"
import "lib/vma"
import "vendor:glfw"
import vk "vendor:vulkan"


when ODIN_OS == .Darwin {
	// NOTE: just a bogus import of the system library,
	// needed so we can add a linker flag to point to /usr/local/lib (where vulkan is installed by default)
	// when trying to load vulkan.
	@(require, extra_linker_flags = "-rpath /usr/local/lib")
	foreign import __ "system:System.framework"
}

@(private)
callback_ctx: runtime.Context // FIXME: used for system callback procedures

@(private)
_init_gfx :: proc(init_info: Graphics_Init_Info) {
	callback_ctx = context

	_init_vulkan_state()
	ctx.gfx.cmd = _create_draw_command_buffer(ctx.gfx.vk_state)
	_init_limits()

	_init_swapchaint_cfg()

	_init_pipeline_manager()
	_init_sync_obj()
	_init_swapchain(init_info.swapchain.sample_count)
	_init_deferred_destructor()
	_init_buffer_manager()
	_init_bindless()
}

@(private)
_destroy_gfx :: proc() {
	wait_render_completion()
	_destroy_deferred_destructor()
	_destroy_bindless()
	_destroy_buffer_manager()
	_destroy_descriptor_layout_manager()
	_destroy_sync_obj()
	_destroy_swapchain()
	_destroy_pipeline_manager()
	_destroy_vulkan_state()

	ctx.gfx = Graphics{}
}

@(private = "file")
_init_vulkan_state :: proc() {
	ctx.gfx.vk_state.enabled_layer_names = make([dynamic]cstring)
	_create_instance()
	_create_surface()
	_pick_physical_device()
	_init_device_info()
	_create_logical_device()
	_create_vma_allocator()
	_create_descriptor_pool()
	_create_command_pool()
}

@(private = "file")
_destroy_vulkan_state :: proc() {
	_destroy_device_info()
	vma.DestroyAllocator(ctx.gfx.vk_state.allocator)
	_destroy_command_pool()
	_destroy_descriptor_pool()

	_destroy_logical_device()
	_destroy_surface()
	_destroy_instance()
	delete(ctx.gfx.vk_state.enabled_layer_names)
}

@(private = "file")
_init_device_info :: proc() {
	properties := ctx.gfx.vk_state.physical_device_property
	info := &ctx.gfx.device_info
	info.name = strings.clone(string(cstring(&properties.deviceName[0])))
	info.vendor_id = properties.vendorID
	info.device_id = properties.deviceID
	info.driver_version_raw = properties.driverVersion
	versions := &ctx.gfx.vulkan_info
	versions.requested_api_version = _device_info_version(VULKAN_API_VERSION)
	versions.device_api_version = _device_info_version(properties.apiVersion)
	loader_version := u32(vk.API_VERSION_1_0)
	if vk.EnumerateInstanceVersion != nil {
		if vk.EnumerateInstanceVersion(&loader_version) != .SUCCESS do loader_version = 0
	}
	if loader_version != 0 do versions.loader_api_version = _device_info_version(loader_version)

	if properties.apiVersion >= vk.API_VERSION_1_2 && vk.GetPhysicalDeviceProperties2 != nil {
		driver := vk.PhysicalDeviceDriverProperties {
			sType = .PHYSICAL_DEVICE_DRIVER_PROPERTIES,
		}
		properties2 := vk.PhysicalDeviceProperties2 {
			sType = .PHYSICAL_DEVICE_PROPERTIES_2,
			pNext = &driver,
		}
		vk.GetPhysicalDeviceProperties2(ctx.gfx.vk_state.physical_device, &properties2)
		info.driver_id = fmt.aprintf("%v", driver.driverID)
		info.driver_name = strings.clone(string(cstring(&driver.driverName[0])))
		info.driver_info = strings.clone(string(cstring(&driver.driverInfo[0])))
	}
	ctx.gfx.device_info_allocator = context.allocator
	ctx.gfx.device_info_ready = true
}

@(private = "file")
_destroy_device_info :: proc() {
	info := ctx.gfx.device_info
	versions := ctx.gfx.vulkan_info
	values := []string {
		info.name,
		info.driver_id,
		info.driver_name,
		info.driver_info,
		versions.requested_api_version,
		versions.device_api_version,
		versions.loader_api_version,
	}
	for value in values do delete(value, ctx.gfx.device_info_allocator)
	ctx.gfx.device_info = {}
	ctx.gfx.vulkan_info = {}
	ctx.gfx.device_info_ready = false
	ctx.gfx.device_info_allocator = {}
}

@(private = "file")
_device_info_version :: proc(version: u32) -> string {
	return fmt.aprintf(
		"%d.%d.%d",
		vk.API_VERSION_MAJOR(version),
		vk.API_VERSION_MINOR(version),
		vk.API_VERSION_PATCH(version),
	)
}

@(private = "file")
_vk_messenger_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = callback_ctx

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
		append(&ctx.gfx.vk_state.enabled_layer_names, "VK_LAYER_KHRONOS_validation")
		instance_info.ppEnabledLayerNames = raw_data(ctx.gfx.vk_state.enabled_layer_names)
		instance_info.enabledLayerCount = 1

		enable_features := [?]vk.ValidationFeatureEnableEXT{.DEBUG_PRINTF, .SYNCHRONIZATION_VALIDATION}
		validation_feature := vk.ValidationFeaturesEXT {
			sType                         = .VALIDATION_FEATURES_EXT,
			enabledValidationFeatureCount = len(enable_features),
			pEnabledValidationFeatures    = raw_data(&enable_features),
		}

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

		dbg_messenger_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = severity,
			messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE}, // all of them.
			pfnUserCallback = _vk_messenger_callback,
		}
		instance_info.pNext = &validation_feature
	}

	instance_info.enabledExtensionCount = u32(len(extensions))
	instance_info.ppEnabledExtensionNames = raw_data(extensions)

	must(vk.CreateInstance(&instance_info, nil, &ctx.gfx.vk_state.instance))

	vk.load_proc_addresses_instance(ctx.gfx.vk_state.instance)

	when ENABLE_VALIDATION_LAYERS {
		dbg_messenger: vk.DebugUtilsMessengerEXT
		must(
			vk.CreateDebugUtilsMessengerEXT(ctx.gfx.vk_state.instance, &dbg_messenger_create_info, nil, &dbg_messenger),
		)
		ctx.gfx.vk_state.dbg_messenger = dbg_messenger
	}
}

@(private = "file")
_destroy_instance :: proc() {
	when ENABLE_VALIDATION_LAYERS {
		dbg_messenger, ok := ctx.gfx.vk_state.dbg_messenger.?
		assert(ok)
		vk.DestroyDebugUtilsMessengerEXT(ctx.gfx.vk_state.instance, dbg_messenger, nil)
	}
	vk.DestroyInstance(ctx.gfx.vk_state.instance, nil)
}

@(private = "file")
_create_surface :: proc() {
	must(glfw.CreateWindowSurface(ctx.gfx.vk_state.instance, ctx.window.id, nil, &ctx.gfx.vk_state.surface))
}

@(private = "file")
_destroy_surface :: proc() {
	vk.DestroySurfaceKHR(ctx.gfx.vk_state.instance, ctx.gfx.vk_state.surface, nil)
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
	score_physical_device :: proc(device: vk.PhysicalDevice) -> (score: int, err_msg: string) {
		features: Physical_Device_Features
		_get_physical_device_features(device, &features)
		success, msg := _validate_physical_device_features(features, context.temp_allocator)
		if !success {
			return 0, msg
		}

		props: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(device, &props)

		name := byte_arr_str(&props.deviceName)

		// Need certain extensions supported.
		{
			extensions, result := _physical_device_extensions(device, context.temp_allocator)
			if result != .SUCCESS {
				return 0, fmt.tprintf(" ! enumerate device extension properties failed: %v", result)
			}

			required_loop: for required in DEVICE_EXTENSIONS {
				for &extension in extensions {
					extension_name := byte_arr_str(&extension.extensionName)
					if extension_name == string(required) {
						continue required_loop
					}
				}

				return 0, fmt.tprintf(" ! device does not support required extension %q", required)
			}
		}

		// Check if swapchain is adequately supported.
		{
			support, result := _query_swapchain_support(device, ctx.gfx.vk_state.surface, context.temp_allocator)
			if result != .SUCCESS {
				return 0, fmt.tprintf(" ! query swapchain support failure: %v", result)
			}

			// Need at least a format and present mode.
			if len(support.formats) == 0 || len(support.presentModes) == 0 {
				return 0, " ! device does not support swapchain"
			}
		}

		families := _find_queue_families(device, ctx.gfx.vk_state.surface)
		if _, has_graphics := families.graphics.?; !has_graphics {
			return 0, " ! device does not have a graphics queue"
		}
		if _, has_present := families.present.?; !has_present {
			return 0, " ! device does not have a presentation queue"
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

		// Maximum texture size.
		score += int(props.limits.maxImageDimension2D)
		return
	}

	count: u32
	must(vk.EnumeratePhysicalDevices(ctx.gfx.vk_state.instance, &count, nil))
	if count == 0 {log.panic("vulkan: no GPU found")}

	devices := make([]vk.PhysicalDevice, count, context.temp_allocator)
	must(vk.EnumeratePhysicalDevices(ctx.gfx.vk_state.instance, &count, raw_data(devices)))

	best_device_score := -1
	msgs := make([]string, len(devices), context.temp_allocator)
	for device, i in devices {
		if score, msg := score_physical_device(device); score > best_device_score {
			msgs[i] = msg
			ctx.gfx.vk_state.physical_device = device
			best_device_score = score
		}
	}

	if best_device_score <= 0 {
		for device_msg, i in msgs {
			props: vk.PhysicalDeviceProperties
			vk.GetPhysicalDeviceProperties(devices[i], &props)
			log.errorf(
				`
Device Name: %s
API Version: %d
Device Version: %d
Error: %s`,
				props.deviceName,
				props.apiVersion,
				props.driverVersion,
				device_msg,
			)
		}
		log.panicf("vulkan: no suitable GPU found")
	}

	vk.GetPhysicalDeviceProperties(ctx.gfx.vk_state.physical_device, &ctx.gfx.vk_state.physical_device_property)
	vk.GetPhysicalDeviceMemoryProperties(ctx.gfx.vk_state.physical_device, &ctx.gfx.vk_state.memory_propertices)
}

@(private = "file")
_create_logical_device :: proc() {
	indices := _find_queue_families(ctx.gfx.vk_state.physical_device, ctx.gfx.vk_state.surface)
	// TODO: this is kinda messy.
	indices_set := make(map[u32]struct{}, allocator = context.temp_allocator)
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

	_get_required_physical_device_features(&features)

	device_create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &features.features,
		pQueueCreateInfos       = raw_data(queue_create_infos),
		queueCreateInfoCount    = cast(u32)(len(queue_create_infos)),
		ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS),
		enabledExtensionCount   = cast(u32)(len(DEVICE_EXTENSIONS)),
	}

	must(vk.CreateDevice(ctx.gfx.vk_state.physical_device, &device_create_info, nil, &ctx.gfx.vk_state.device))

	vk.GetDeviceQueue(ctx.gfx.vk_state.device, indices.graphics.?, 0, &ctx.gfx.vk_state.graphics_queue)
	vk.GetDeviceQueue(ctx.gfx.vk_state.device, indices.present.?, 0, &ctx.gfx.vk_state.present_queue)
	ctx.gfx.vk_state.queue_indices = indices
}

@(private)
_create_vma_allocator :: proc() {
	vulkan_functions := vma.create_vulkan_functions()
	create_info := vma.AllocatorCreateInfo {
		vulkanApiVersion = VULKAN_API_VERSION,
		physicalDevice   = ctx.gfx.vk_state.physical_device,
		device           = ctx.gfx.vk_state.device,
		instance         = ctx.gfx.vk_state.instance,
		pVulkanFunctions = &vulkan_functions,
	}

	must(vma.CreateAllocator(&create_info, &ctx.gfx.vk_state.allocator), "failed to create vma.Allocator")
}

@(private = "file")
_destroy_logical_device :: proc() {
	vk.DestroyDevice(ctx.gfx.vk_state.device, nil)
}

@(private = "file")
_create_command_pool :: proc() {
	indices := _find_queue_families(ctx.gfx.vk_state.physical_device, ctx.gfx.vk_state.surface)
	pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = indices.graphics.?,
	}
	must(vk.CreateCommandPool(ctx.gfx.vk_state.device, &pool_info, nil, &ctx.gfx.vk_state.command_pool))
}

@(private = "file")
_destroy_command_pool :: proc() {
	vk.DestroyCommandPool(ctx.gfx.vk_state.device, ctx.gfx.vk_state.command_pool, nil)
}

@(private = "file")
_create_draw_command_buffer :: proc(vks: Vulkan_State) -> Command_Buffer {
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

@(private)
_init_limits :: proc() {
	vk_limits := ctx.gfx.vk_state.physical_device_property.limits

	ctx.gfx.limits = Graphics_Limits {
		max_sampler_anisotropy = vk_limits.maxSamplerAnisotropy,
		max_sample_count       = _get_sample_count(vk_limits),
	}
}

get_limits :: proc() -> Graphics_Limits {
	return ctx.gfx.limits
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
	must(vk.CreateFence(ctx.gfx.vk_state.device, &fence_info, nil, &ctx.gfx.fence))
	must(vk.CreateSemaphore(ctx.gfx.vk_state.device, &sem_info, nil, &ctx.gfx.image_available_semaphore))
}

@(private = "file")
_destroy_sync_obj :: proc() {
	vk.DestroySemaphore(ctx.gfx.vk_state.device, ctx.gfx.image_available_semaphore, nil)
	vk.DestroyFence(ctx.gfx.vk_state.device, ctx.gfx.fence, nil)
}

@(private = "file")
byte_arr_str :: proc(arr: ^[$N]byte) -> string {
	return strings.truncate_to_byte(string(arr[:]), 0)
}

@(private = "file")
_get_physical_device_features :: proc(device: vk.PhysicalDevice, features: ^Physical_Device_Features) {
	_get_required_physical_device_features(features)
	vk.GetPhysicalDeviceFeatures2(device, &features.features)
}

@(private = "file")
_validate_physical_device_features :: proc(
	features: Physical_Device_Features,
	allocator := context.allocator,
) -> (
	bool,
	string,
) {
	target: Physical_Device_Features
	_get_required_physical_device_features(&target)

	compare :: proc(dst, src: $T) -> (field: string, success: bool) {
		fields := reflect.struct_fields_zipped(T)
		for f in fields {
			_, ok := f.type.variant.(reflect.Type_Info_Boolean)
			if !ok do continue

			src_enabled := reflect.struct_field_value(src, f).(b32)
			dst_enabled := reflect.struct_field_value(dst, f).(b32)
			if src_enabled && !dst_enabled {
				return f.name, false
			}
		}
		return "", true
	}

	if field, ok := compare(features.features.features, target.features.features); !ok {
		return false, fmt.aprintf("device does not support %s", field, allocator = allocator)
	}
	if field, ok := compare(features.features12, target.features12); !ok {
		return false, fmt.aprintf("device does not support %s (Vulkan 1.2)", field, allocator = allocator)
	}
	if field, ok := compare(features.features13, target.features13); !ok {
		return false, fmt.aprintf("device does not support %s (Vulkan 1.3)", field, allocator = allocator)
	}

	return true, ""
}

@(private)
_get_required_physical_device_features :: proc(features: ^Physical_Device_Features) {
	// FEATURES 1.3
	features.features13.sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES
	features.features13.pNext = nil
	features.features13.subgroupSizeControl = true
	features.features13.dynamicRendering = true
	features.features13.synchronization2 = true
	features.features13.maintenance4 = true
	features.features13.shaderDemoteToHelperInvocation = true

	// FEATURES 1.2
	features.features12.sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES
	features.features12.pNext = &features.features13
	features.features12.vulkanMemoryModel = true
	features.features12.vulkanMemoryModelDeviceScope = true
	features.features12.bufferDeviceAddress = true
	features.features12.timelineSemaphore = true
	features.features12.scalarBlockLayout = true
	features.features12.storageBuffer8BitAccess = true

	// descriptor indexing
	features.features12.descriptorIndexing = true
	features.features12.shaderSampledImageArrayNonUniformIndexing = true
	features.features12.descriptorBindingSampledImageUpdateAfterBind = true
	features.features12.shaderUniformBufferArrayNonUniformIndexing = true
	features.features12.descriptorBindingUniformBufferUpdateAfterBind = true
	features.features12.shaderStorageBufferArrayNonUniformIndexing = true
	features.features12.descriptorBindingStorageBufferUpdateAfterBind = true
	features.features12.runtimeDescriptorArray = true
	features.features12.descriptorBindingPartiallyBound = true

	// FEATURES
	features.features.sType = .PHYSICAL_DEVICE_FEATURES_2
	features.features.pNext = &features.features12
	features.features.features.geometryShader = true
	features.features.features.fillModeNonSolid = true
	features.features.features.samplerAnisotropy = true
	features.features.features.depthBiasClamp = true
	features.features.features.fragmentStoresAndAtomics = true
	features.features.features.vertexPipelineStoresAndAtomics = true
	features.features.features.shaderInt64 = true
}

_init_swapchaint_cfg :: proc() {
	ctx.gfx.swapchain_cfg.depth_format = _find_depth_format(ctx.gfx.vk_state.physical_device, false)
	ctx.gfx.swapchain_cfg.depth_stencil_format = _find_depth_format(ctx.gfx.vk_state.physical_device, true)
	device := ctx.gfx.vk_state.physical_device
	vk_surface := ctx.gfx.vk_state.surface

	{
		count: u32
		must(vk.GetPhysicalDeviceSurfaceFormatsKHR(device, vk_surface, &count, nil))

		formats := make([]vk.SurfaceFormatKHR, count, context.temp_allocator)
		must(vk.GetPhysicalDeviceSurfaceFormatsKHR(device, vk_surface, &count, raw_data(formats)))
		ctx.gfx.swapchain_cfg.vk_surface_format = _choose_swapchain_surface_format(formats)
	}

	{
		count: u32
		must(vk.GetPhysicalDeviceSurfacePresentModesKHR(device, vk_surface, &count, nil))

		present_modes := make([]vk.PresentModeKHR, count, context.temp_allocator)
		must(vk.GetPhysicalDeviceSurfacePresentModesKHR(device, vk_surface, &count, raw_data(present_modes)))
		ctx.gfx.swapchain_cfg.present_mode = _choose_swapchain_present_mode(present_modes)
	}
}

@(private = "file")
@(require_results)
_choose_swapchain_surface_format :: proc(formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
	for format in formats {
		if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
			return format
		}
	}

	log.panic("Failed to find supported swapchain surface format!")
}

@(private = "file")
@(require_results)
_choose_swapchain_present_mode :: proc(modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
	// We would like mailbox for the best tradeoff between tearing and latency.
	for mode in modes {
		if mode == .MAILBOX {
			return .MAILBOX
		}
	}
	// As a fallback, fifo (basically vsync) is always available.
	return .FIFO
}

@(private)
_find_depth_format :: proc(physical_device: vk.PhysicalDevice, stencil: bool) -> Format {
	if stencil {
		return _vk_to_format(
			_find_supported_format(
				physical_device,
				{.D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT},
				.OPTIMAL,
				{.DEPTH_STENCIL_ATTACHMENT},
			),
		)
	}

	return _vk_to_format(
		_find_supported_format(
			physical_device,
			{.D32_SFLOAT, .X8_D24_UNORM_PACK32},
			.OPTIMAL,
			{.DEPTH_STENCIL_ATTACHMENT},
		),
	)
}

@(private)
_has_stencil_component :: proc(format: Format) -> bool {
	return format == .D_f32_S_u8
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

	log.panic("Failed to find supported format!")
}

Queue_Family_Indices :: struct {
	graphics: Maybe(u32),
	present:  Maybe(u32),
}

@(private)
_find_queue_families :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> (ids: Queue_Family_Indices) {
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
