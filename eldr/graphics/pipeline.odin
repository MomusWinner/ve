package graphics

import "../common"
import hm "../handle_map"
import sm "core:container/small_array"
import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"
import "shaderc"
import vk "vendor:vulkan"

create_render_pipeline :: proc(
	create_pipeline_info: Create_Pipeline_Info,
	loc := #caller_location,
) -> Render_Pipeline_Handle {
	return _pipeline_manager_add_render_pipeline(
		ctx.pipeline_manager,
		Render_Pipeline{create_info = create_pipeline_info},
	)
}

// Looks up a pipeline in cache using surface settings. If not found, creates a new one.
render_pipeline_get_pipeline :: proc(pipeline: ^Render_Pipeline, surface_info: Surface_Info) -> Graphics_Pipeline {
	graphics_pipeline, ok := pipeline.cache[surface_info]
	if ok do return graphics_pipeline

	new_pipeline := _create_graphics_pipeline(pipeline.create_info, surface_info)
	pipeline.cache[surface_info] = new_pipeline

	return new_pipeline
}

destroy_render_pipeline :: proc(pipeline: ^Render_Pipeline) {
	for key, &pipeline in pipeline.cache {
		_destroy_graphics_pipeline(&pipeline)
	}
	delete(pipeline.cache)
}

@(require_results)
create_compute_pipeline :: proc(
	g: ^Graphics,
	create_pipeline_info: ^Create_Compute_Pipeline_Info,
) -> (
	Pipeline_Handle,
	bool,
) {
	pipeline, ok := _create_compute_pipeline(g, create_pipeline_info, context.allocator)
	if !ok {
		log.errorf("couldn't load pipeline")
		return {}, false
	}

	handle := _pipeline_manager_registe_compute_pipeline(g.pipeline_manager, pipeline)

	return handle, true
}

destroy_compute_pipeline :: proc(pipeline: ^Compute_Pipeline) {
	_destroy_pipline(pipeline)
}

@(private)
_reload_render_pipelines :: proc(pipeline: ^Render_Pipeline) {
	for _, &graphics_pipeline in pipeline.cache {
		_reload_graphics_pipeline(&graphics_pipeline, pipeline.create_info)
	}
}

@(private)
_reload_graphics_pipeline :: proc(pipeline: ^Graphics_Pipeline, create_info: Create_Pipeline_Info) {
	create_info := create_info

	vk.DestroyPipeline(ctx.vulkan_state.device, pipeline.pipeline, nil)

	shader_stages := _create_shader_stages(create_info, true)
	defer _destroy_shader_stages(shader_stages)

	depth_format := _find_depth_format(ctx.vulkan_state.physical_device)

	pipeline_layout := get_pipeline_layout(pipeline.layout)

	pipeline_rendering_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		// stencilAttachmentFormat = surface_info.depthAttachmentFormat,
		depthAttachmentFormat   = pipeline.surface_info.depth_format,
		colorAttachmentCount    = cast(u32)pipeline.surface_info.color_formats.len,
		pColorAttachmentFormats = raw_data(sm.slice(&pipeline.surface_info.color_formats)),
	}

	vertex_binding_info: Vertex_Input_Binding_Description
	vertex_input_sate: vk.PipelineVertexInputStateCreateInfo
	input_assembly_state: vk.PipelineInputAssemblyStateCreateInfo
	view_port_state: vk.PipelineViewportStateCreateInfo
	rasterization_sate: vk.PipelineRasterizationStateCreateInfo
	multisample_state: vk.PipelineMultisampleStateCreateInfo
	color_blend_sate: vk.PipelineColorBlendStateCreateInfo
	color_blend_attachment: vk.PipelineColorBlendAttachmentState
	dynamic_state: vk.PipelineDynamicStateCreateInfo
	dynamic_states: [2]vk.DynamicState
	depth_stancil: vk.PipelineDepthStencilStateCreateInfo

	_init_vertex_input_info(&vertex_input_sate, &vertex_binding_info, &create_info)
	_init_input_assembly_info(&input_assembly_state, &create_info)
	_init_viewport_info(&view_port_state, &create_info)
	_init_rasterizer(&rasterization_sate, &create_info)
	_init_multisampling_info(&multisample_state, &create_info, pipeline.surface_info.sample_count)
	_init_color_blend_info(&color_blend_sate, &color_blend_attachment, &create_info)
	_init_dynamic_info(&dynamic_state, &dynamic_states, &create_info)
	_init_depth_stencil_info(&depth_stancil, &create_info)

	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &pipeline_rendering_info,
		stageCount          = cast(u32)shader_stages.len,
		pStages             = raw_data(sm.slice(&shader_stages)),
		pVertexInputState   = &vertex_input_sate,
		pInputAssemblyState = &input_assembly_state,
		pViewportState      = &view_port_state,
		pRasterizationState = &rasterization_sate,
		pMultisampleState   = &multisample_state,
		pColorBlendState    = &color_blend_sate,
		pDynamicState       = &dynamic_state,
		pDepthStencilState  = &depth_stancil,
		layout              = pipeline_layout,
		subpass             = 0,
		basePipelineIndex   = -1,
	}

	must(vk.CreateGraphicsPipelines(ctx.vulkan_state.device, 0, 1, &pipeline_info, nil, &pipeline.pipeline))
}

@(private)
_create_descriptor_pool :: proc() {
	pool_sizes := [?]vk.DescriptorPoolSize {
		vk.DescriptorPoolSize{type = .UNIFORM_BUFFER, descriptorCount = MAX_DESCRIPTOR_UNIFORM_COUNT},
		vk.DescriptorPoolSize{type = .UNIFORM_BUFFER_DYNAMIC, descriptorCount = MAX_DESCRIPTOR_UNIFORM_DYNAMIC_COUNT},
		vk.DescriptorPoolSize{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = MAX_DESCRIPTOR_IMAGE_SAMPLER_COUNT},
		vk.DescriptorPoolSize{type = .STORAGE_BUFFER, descriptorCount = MAX_DESCRIPTOR_STORAGE_COUNT},
	}

	poolInfo := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		flags         = {.UPDATE_AFTER_BIND},
		poolSizeCount = len(pool_sizes),
		pPoolSizes    = raw_data(&pool_sizes),
		maxSets       = MAX_DESCRIPTOR_SET_COUNT,
	}

	must(
		vk.CreateDescriptorPool(ctx.vulkan_state.device, &poolInfo, nil, &ctx.vulkan_state.descriptor_pool),
		"failed to create descriptor pool!",
	)
}

@(private)
_destroy_descriptor_pool :: proc() {
	vk.DestroyDescriptorPool(ctx.vulkan_state.device, ctx.vulkan_state.descriptor_pool, nil)
}

// TODO: need modification
// @(private)
// @(require_results)
// create_descriptor_set :: proc(
// 	pipeline: ^Pipeline,
// 	set: u32,
// 	set_info: Pipeline_Layout_Set_Info,
// 	resources: []Pipeline_Resource,
// ) -> vk.DescriptorSet {
// 	descripotr_set_layout := pipeline.descriptor_set_layouts.data[set]
//
// 	alloc_info := vk.DescriptorSetAllocateInfo {
// 		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
// 		descriptorPool     = ctx.vulkan_state.descriptor_pool,
// 		descriptorSetCount = 1,
// 		pSetLayouts        = &pipeline.descriptor_set_layouts.data[set],
// 	}
//
// 	descriptor_set: vk.DescriptorSet
// 	must(
// 		vk.AllocateDescriptorSets(ctx.vulkan_state.device, &alloc_info, &descriptor_set),
// 		"failed to allocate descriptor sets!",
// 	)
//
// 	assert(set_info.binding_infos.len == len(resources))
//
// 	write_descriptor_sets := make([]vk.WriteDescriptorSet, len(resources), context.temp_allocator)
// 	descriptor_image_info := vk.DescriptorImageInfo{}
// 	descriptor_buffer_info := vk.DescriptorBufferInfo{}
//
// 	for i in 0 ..< set_info.binding_infos.len {
// 		binding := set_info.binding_infos.data[i]
// 		resource := resources[i]
//
// 		switch r in resource {
// 		case Texture:
// 			descriptor_image_info.imageLayout = .SHADER_READ_ONLY_OPTIMAL
// 			descriptor_image_info.imageView = r.view
// 			descriptor_image_info.sampler = r.sampler
//
// 			write_descriptor_sets[i] = vk.WriteDescriptorSet {
// 				sType           = .WRITE_DESCRIPTOR_SET,
// 				dstSet          = descriptor_set,
// 				dstBinding      = binding.binding,
// 				descriptorType  = binding.descriptor_type,
// 				dstArrayElement = 0,
// 				descriptorCount = binding.descriptor_count,
// 				pImageInfo      = &descriptor_image_info,
// 			}
// 		case Buffer:
// 			descriptor_buffer_info.buffer = r.buffer
// 			descriptor_buffer_info.offset = 0
// 			descriptor_buffer_info.range = cast(vk.DeviceSize)vk.WHOLE_SIZE
//
// 			write_descriptor_sets[i] = vk.WriteDescriptorSet {
// 				sType           = .WRITE_DESCRIPTOR_SET,
// 				dstSet          = descriptor_set,
// 				dstBinding      = binding.binding,
// 				descriptorType  = binding.descriptor_type,
// 				dstArrayElement = 0,
// 				descriptorCount = binding.descriptor_count,
// 				pBufferInfo     = &descriptor_buffer_info,
// 			}
// 		}
// 	}
//
// 	vk.UpdateDescriptorSets(
// 		ctx.vulkan_state.device,
// 		cast(u32)len(write_descriptor_sets),
// 		raw_data(write_descriptor_sets),
// 		0,
// 		nil,
// 	)
//
// 	return descriptor_set
// }

@(private = "file")
@(require_results)
_create_graphics_pipeline :: proc(
	create_info: Create_Pipeline_Info,
	surface_info: Surface_Info,
	loc := #caller_location,
) -> Graphics_Pipeline {
	assert(surface_info.type != .None, loc = loc)

	create_info := create_info
	surface_info := surface_info

	shader_stages := _create_shader_stages(create_info, DEBUG, loc = loc)
	defer _destroy_shader_stages(shader_stages)


	pipelie_layout_info := Pipeline_Layout_Info {
		layout_infos = create_info.set_infos,
	}

	if create_info.bindless {
		pipelie_layout_info.push_constant = Push_Constant_Range {
			offset     = 0,
			size       = size_of(Push_Constant),
			stageFlags = vk.ShaderStageFlags_ALL_GRAPHICS,
		}
	}

	pipeline_layout := get_pipeline_layout(pipelie_layout_info)

	pipeline_rendering_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		// stencilAttachmentFormat = surface_info.depthAttachmentFormat,
		depthAttachmentFormat   = surface_info.depth_format,
		colorAttachmentCount    = cast(u32)surface_info.color_formats.len,
		pColorAttachmentFormats = raw_data(sm.slice(&surface_info.color_formats)),
	}

	vertex_binding_info: Vertex_Input_Binding_Description
	vertex_input_sate: vk.PipelineVertexInputStateCreateInfo
	input_assembly_state: vk.PipelineInputAssemblyStateCreateInfo
	view_port_state: vk.PipelineViewportStateCreateInfo
	rasterization_sate: vk.PipelineRasterizationStateCreateInfo
	multisample_state: vk.PipelineMultisampleStateCreateInfo
	color_blend_sate: vk.PipelineColorBlendStateCreateInfo
	color_blend_attachment: vk.PipelineColorBlendAttachmentState
	dynamic_state: vk.PipelineDynamicStateCreateInfo
	dynamic_states: [2]vk.DynamicState
	depth_stancil: vk.PipelineDepthStencilStateCreateInfo

	_init_vertex_input_info(&vertex_input_sate, &vertex_binding_info, &create_info)
	_init_input_assembly_info(&input_assembly_state, &create_info)
	_init_viewport_info(&view_port_state, &create_info)
	_init_rasterizer(&rasterization_sate, &create_info)
	_init_multisampling_info(&multisample_state, &create_info, surface_info.sample_count)
	_init_color_blend_info(&color_blend_sate, &color_blend_attachment, &create_info)
	_init_dynamic_info(&dynamic_state, &dynamic_states, &create_info)
	_init_depth_stencil_info(&depth_stancil, &create_info)

	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &pipeline_rendering_info,
		stageCount          = cast(u32)shader_stages.len,
		pStages             = raw_data(sm.slice(&shader_stages)),
		pVertexInputState   = &vertex_input_sate,
		pInputAssemblyState = &input_assembly_state,
		pViewportState      = &view_port_state,
		pRasterizationState = &rasterization_sate,
		pMultisampleState   = &multisample_state,
		pColorBlendState    = &color_blend_sate,
		pDynamicState       = &dynamic_state,
		pDepthStencilState  = &depth_stancil,
		layout              = pipeline_layout,
		subpass             = 0,
		basePipelineIndex   = -1,
	}

	vk_pipeline := vk.Pipeline{}

	must(vk.CreateGraphicsPipelines(ctx.vulkan_state.device, 0, 1, &pipeline_info, nil, &vk_pipeline))

	pipeline := Graphics_Pipeline {
		pipeline     = vk_pipeline,
		layout       = pipelie_layout_info,
		surface_info = surface_info,
	}

	return pipeline
}

@(private)
_destroy_graphics_pipeline :: proc(pipeline: ^Graphics_Pipeline) {
	_destroy_pipline(pipeline)
}

@(private = "file")
@(require_results)
_create_compute_pipeline :: proc(
	g: ^Graphics,
	create_info: ^Create_Compute_Pipeline_Info,
	allocator := context.allocator,
) -> (
	Compute_Pipeline,
	bool,
) {
	create_info := create_info

	module, ok := _create_shader_module(create_info.shader_path)
	if !ok {
		log.error("couldn't find comp shader. ", create_info.shader_path)
		return {}, false
	}

	comp_stage_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.COMPUTE},
		module = module,
		pName  = "main",
	}

	pipelie_layout_info := Pipeline_Layout_Info {
		layout_infos = create_info.set_infos,
		push_constant = Push_Constant_Range {
			offset = 0,
			size = size_of(Push_Constant),
			stageFlags = vk.ShaderStageFlags_ALL_GRAPHICS,
		},
	}

	pipeline_layout := get_pipeline_layout(pipelie_layout_info)


	vk_create_info := vk.ComputePipelineCreateInfo {
		sType  = .COMPUTE_PIPELINE_CREATE_INFO,
		layout = pipeline_layout,
		stage  = comp_stage_info,
	}

	pipeline := vk.Pipeline{}

	vk.CreateComputePipelines(g.vulkan_state.device, vk.FALSE, 1, &vk_create_info, nil, &pipeline)

	compute_pipeline := Compute_Pipeline {
		pipeline    = pipeline,
		create_info = create_info,
		layout      = pipelie_layout_info,
	}

	return compute_pipeline, true
}

@(private = "file")
_destroy_pipline :: proc(pipeline: ^Pipeline) {
	vk.DestroyPipeline(ctx.vulkan_state.device, pipeline.pipeline, nil)
}

// @(private = "file")
// @(require_results)
// _set_infos_to_descriptor_set_layouts :: proc(
// 	set_infos: Pipeline_Set_Infos,
// ) -> (
// 	descriptor_set_layouts: Descriptor_Set_Layouts,
// ) {
// 	for i in 0 ..< set_infos.len {
// 		sm.push(&descriptor_set_layouts, _set_info_to_descriptor_set_layout(set_infos.data[i]))
// 	}
//
// 	return descriptor_set_layouts
// }
//
// @(private = "file")
// @(require_results)
// _set_info_to_descriptor_set_layout :: proc(set_info: Pipeline_Set_Info) -> vk.DescriptorSetLayout {
// 	descriptor_bindings: sm.Small_Array(MAX_PIPELINE_BINDING_COUNT, vk.DescriptorSetLayoutBinding)
// 	flags_array: sm.Small_Array(MAX_PIPELINE_BINDING_COUNT, vk.DescriptorBindingFlags)
//
// 	use_binding_flags := false
//
// 	for i in 0 ..< set_info.binding_infos.len {
// 		binding := set_info.binding_infos.data[i]
// 		sm.push(
// 			&descriptor_bindings,
// 			vk.DescriptorSetLayoutBinding {
// 				binding = binding.binding,
// 				descriptorType = binding.descriptor_type,
// 				descriptorCount = binding.descriptor_count,
// 				stageFlags = binding.stage_flags,
// 				pImmutableSamplers = nil,
// 			},
// 		)
//
// 		flags, has_flags := binding.flags.?
// 		if has_flags {
// 			use_binding_flags = true
// 			sm.push(&flags_array, flags)
// 		} else {
// 			sm.push(&flags_array, vk.DescriptorBindingFlags{})
// 		}
// 	}
//
// 	p_binding_flags: ^vk.DescriptorSetLayoutBindingFlagsCreateInfo = nil
//
// 	if use_binding_flags {
// 		binding_flags := vk.DescriptorSetLayoutBindingFlagsCreateInfo {
// 			sType         = .DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
// 			pNext         = nil,
// 			pBindingFlags = raw_data(sm.slice(&flags_array)),
// 			bindingCount  = cast(u32)flags_array.len,
// 		}
// 		p_binding_flags = &binding_flags
// 	}
//
// 	descriptor_set_layout := vk.DescriptorSetLayout{}
//
// 	layout_info := vk.DescriptorSetLayoutCreateInfo {
// 		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
// 		pNext        = p_binding_flags,
// 		bindingCount = cast(u32)descriptor_bindings.len,
// 		pBindings    = raw_data(sm.slice(&descriptor_bindings)),
// 		flags        = {.UPDATE_AFTER_BIND_POOL},
// 	}
//
// 	must(
// 		vk.CreateDescriptorSetLayout(ctx.vulkan_state.device, &layout_info, nil, &descriptor_set_layout),
// 		"failed to create descriptor set layout!",
// 	)
//
// 	return descriptor_set_layout
// }

// @(private = "file")
// _destroy_descriptor_set_layout :: proc(descriptor_set_layout: vk.DescriptorSetLayout) {
// 	vk.DestroyDescriptorSetLayout(ctx.vulkan_state.device, descriptor_set_layout, nil)
// }

@(private = "file")
@(require_results)
_create_shader_module :: proc {
	_create_shader_module_from_file,
	_create_shader_module_from_memory,
}

@(private = "file")
@(require_results)
_create_shader_module_from_file :: proc(
	path: string,
	compile: bool = false,
	loc := #caller_location,
) -> (
	module: vk.ShaderModule,
	ok: bool,
) {
	source_path := strings.trim_right(path, ".spv")

	if compile {
		when DEBUG {
			data, w_ok := _shader_compile_and_write(ctx.pipeline_manager, source_path, loc)
			if !w_ok {
				log.panic("Couldn't write compiled shader ", path)
			}

			return _create_shader_module_from_memory(data), w_ok
		} else {
			log.panic("couldn't compile shader on release mode")
		}
	}
	data, success := common.read_file(path, context.temp_allocator)

	if !success {
		when DEBUG {
			data = _shader_compile(ctx.pipeline_manager, source_path, loc)
			success := common.wirte_file(path, data)
			if !success {
				log.panic("Couldn't write compiled shader ", path)
			}
		} else {
			log.error("coulnd't load shader module: ", path)
		}
	}

	return _create_shader_module_from_memory(data), success
}

@(private = "file")
@(require_results)
_create_shader_module_from_memory :: proc(code: []byte) -> (module: vk.ShaderModule) {
	as_u32 := slice.reinterpret([]u32, code)

	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = raw_data(as_u32),
	}
	must(vk.CreateShaderModule(ctx.vulkan_state.device, &create_info, nil, &module))

	return
}

@(private = "file")
@(require_results)
_create_shader_stages :: proc(
	create_info: Create_Pipeline_Info,
	compile := false,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	shader_stages: Pipeline_Shader_Stage_Create_Infos,
) {
	for i in 0 ..< create_info.stage_infos.len {
		stage_info := create_info.stage_infos.data[i]
		path := strings.concatenate({stage_info.shader_path, ".spv"}, context.temp_allocator)
		shader_module, c_ok := _create_shader_module(path, compile, loc)

		if !c_ok {
			log.panicf("couldn't create shader module for stage %v. Path: %s", stage_info.stage, stage_info.shader_path)
		}
		sm.push(
			&shader_stages,
			vk.PipelineShaderStageCreateInfo {
				sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
				stage = _to_vulkan_stages({stage_info.stage}),
				module = shader_module,
				pName = "main",
			},
		)
	}

	return
}

@(private = "file")
_destroy_shader_stages :: proc(shader_stages: Pipeline_Shader_Stage_Create_Infos) {
	for i in 0 ..< shader_stages.len {
		vk.DestroyShaderModule(ctx.vulkan_state.device, shader_stages.data[i].module, nil)
	}
}

@(private = "file")
_init_dynamic_info :: proc(
	info: ^vk.PipelineDynamicStateCreateInfo,
	dynamic_states: ^[2]vk.DynamicState,
	create_info: ^Create_Pipeline_Info,
) {
	dynamic_states[0] = .VIEWPORT
	dynamic_states[1] = .SCISSOR

	info.sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO
	info.dynamicStateCount = 2
	info.pDynamicStates = raw_data(dynamic_states)
}

@(private = "file")
_init_vertex_input_info :: proc(
	state_info: ^vk.PipelineVertexInputStateCreateInfo,
	binding_info: ^Vertex_Input_Binding_Description,
	create_info: ^Create_Pipeline_Info,
) {
	binding_info.binding = 0
	binding_info.stride = create_info.vertex_input_description.binding_description.stride
	binding_info.inputRate = create_info.vertex_input_description.input_rate

	state_info.sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
	state_info.vertexBindingDescriptionCount = 1
	state_info.vertexAttributeDescriptionCount =
	cast(u32)create_info.vertex_input_description.attribute_descriptions.len
	state_info.pVertexBindingDescriptions = binding_info
	state_info.pVertexAttributeDescriptions = raw_data(
		sm.slice(&create_info.vertex_input_description.attribute_descriptions),
	)
}

@(private = "file")
_init_input_assembly_info :: proc(info: ^vk.PipelineInputAssemblyStateCreateInfo, create_info: ^Create_Pipeline_Info) {
	info.sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
	info.topology = create_info.input_assembly.topology
}

@(private = "file")
_init_viewport_info :: proc(info: ^vk.PipelineViewportStateCreateInfo, create_info: ^Create_Pipeline_Info) {
	info.sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO
	info.viewportCount = 1
	info.scissorCount = 1
}

@(private = "file")
_init_rasterizer :: proc(info: ^vk.PipelineRasterizationStateCreateInfo, create_info: ^Create_Pipeline_Info) {
	info.sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO
	info.polygonMode = create_info.rasterizer.polygon_mode
	info.lineWidth = create_info.rasterizer.line_width
	info.cullMode = create_info.rasterizer.cull_mode
	info.frontFace = create_info.rasterizer.front_face
}

@(private = "file")
_init_multisampling_info :: proc(
	info: ^vk.PipelineMultisampleStateCreateInfo,
	create_info: ^Create_Pipeline_Info,
	sampel_count: vk.SampleCountFlag,
) {
	info.sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
	info.rasterizationSamples = {sampel_count}
	info.minSampleShading = 1
}

@(private = "file")
_init_color_blend_info :: proc(
	info: ^vk.PipelineColorBlendStateCreateInfo,
	color_blend_attachment: ^vk.PipelineColorBlendAttachmentState,
	create_info: ^Create_Pipeline_Info,
) {
	// enable blending
	// TODO:
	color_blend_attachment.blendEnable = true
	color_blend_attachment.srcColorBlendFactor = .SRC_ALPHA
	color_blend_attachment.dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA
	color_blend_attachment.colorBlendOp = .ADD
	color_blend_attachment.srcAlphaBlendFactor = .ONE
	color_blend_attachment.dstAlphaBlendFactor = .ZERO
	color_blend_attachment.alphaBlendOp = .ADD

	color_blend_attachment.colorWriteMask = {.R, .G, .B, .A}

	info.sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
	info.attachmentCount = 1
	info.pAttachments = color_blend_attachment
}

@(private = "file")
_init_depth_stencil_info :: proc(info: ^vk.PipelineDepthStencilStateCreateInfo, create_info: ^Create_Pipeline_Info) {
	info.sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
	info.depthTestEnable = create_info.depth.enable
	info.depthWriteEnable = create_info.depth.write_enable
	info.depthCompareOp = create_info.depth.compare_op
	info.depthBoundsTestEnable = create_info.depth.bounds_test_enable
	info.minDepthBounds = create_info.depth.min_bounds
	info.maxDepthBounds = create_info.depth.max_bounds
	info.stencilTestEnable = create_info.stencil.enable
	info.front = create_info.stencil.front
	info.back = create_info.stencil.back
}

// @(private = "file")
// @(require_results)
// _create_pipeline_layout :: proc(
// 	descriptor_set_layouts: Descriptor_Set_Layouts,
// 	push_constant: Maybe(vk.PushConstantRange),
// ) -> vk.PipelineLayout {
// 	descriptor_set_layouts := descriptor_set_layouts
// 	push, has_push := push_constant.?
//
// 	pipeline_layout_info := vk.PipelineLayoutCreateInfo {
// 		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
// 		setLayoutCount         = cast(u32)descriptor_set_layouts.len,
// 		pSetLayouts            = raw_data(sm.slice(&descriptor_set_layouts)),
// 		pushConstantRangeCount = 1 if has_push else 0,
// 		pPushConstantRanges    = &push,
// 	}
//
// 	layout := vk.PipelineLayout{}
// 	must(vk.CreatePipelineLayout(ctx.vulkan_state.device, &pipeline_layout_info, nil, &layout))
//
// 	return layout
// }

@(private = "file")
@(require_results)
_shader_compile_and_write :: proc(pm: ^Pipeline_Manager, path: string, loc := #caller_location) -> ([]byte, bool) {
	data := _shader_compile(pm, path, loc)
	result_path := strings.concatenate({path, ".spv"}, context.temp_allocator)

	return data, common.wirte_file(result_path, data)
}

@(private = "file")
_shader_compile :: proc(pm: ^Pipeline_Manager, path: string, loc := #caller_location) -> []u8 {
	kind: shaderc.shaderKind
	file_ext := strings.split(path, ".", context.temp_allocator)[1]

	switch file_ext {
	case "frag":
		kind = .FragmentShader
	case "vert":
		kind = .VertexShader
	case "comp":
		kind = .ComputeShader
	}

	data, ok := common.read_file(path, context.temp_allocator)
	if !ok {
		log.panic("Failed to load file:", path, location = loc)
	}

	source := strings.clone_to_cstring(cast(string)data, context.temp_allocator)

	strs := strings.split(path, "/", context.temp_allocator)
	file_name := strs[len(strs) - 1]
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, file_name)
	input_file_name := strings.to_cstring(&b)

	result := shaderc.compile_into_spv(
		pm.compiler,
		source,
		len(source),
		kind,
		input_file_name,
		"main",
		pm.compiler_options,
	)

	if (shaderc.result_get_compilation_status(result) != shaderc.compilationStatus.Success) {
		log.error("Failed to compile ", path, "shader")
		log.panic(string(shaderc.result_get_error_message(result)))
	} else {
		log.debug("Success compile shader", path)
	}

	result_len := shaderc.result_get_length(result)
	bytes := shaderc.result_get_bytes(result)
	shaderCode := transmute([]u8)bytes[:result_len]

	return shaderCode
}


@(private = "file")
_to_vulkan_stages :: proc(flags: Shader_Stage_Flags) -> vk.ShaderStageFlags {
	result: vk.ShaderStageFlags = {}

	if .Vertex in flags do result |= {.VERTEX}
	if .Geometry in flags do result |= {.GEOMETRY}
	if .Fragment in flags do result |= {.FRAGMENT}
	if .Compute in flags do result |= {.COMPUTE}

	return result
}
