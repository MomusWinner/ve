#+private
package graphics

import "core:log"
import vk "vendor:vulkan"

_create_pipeline :: proc(
	g: ^Graphics,
	create_info: ^Create_Pipeline_Info,
	allocator := context.allocator,
) -> (
	^Pipeline,
	bool,
) {
	create_info := _copy_create_pipeline_info(create_info)

	shader_stages, ok := _create_shader_stages(g, create_info)
	if !ok {
		return nil, false
	}
	defer _destroy_shader_stages(g, shader_stages)

	descriptor_set_layouts := _set_infos_to_descriptor_set_layouts(g, create_info.set_infos, allocator)

	pipeline_layout := _create_pipeline_layout(g, descriptor_set_layouts)

	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = cast(u32)len(shader_stages),
		pStages             = raw_data(shader_stages),
		pVertexInputState   = _create_vertex_input_info(g, create_info),
		pInputAssemblyState = _create_input_assembly_info(g, create_info),
		pViewportState      = _create_viewport_info(g, create_info),
		pRasterizationState = _create_rasterizer(g, create_info),
		pMultisampleState   = _create_multisampling_info(g, create_info),
		pColorBlendState    = _create_color_blend_info(g, create_info),
		pDynamicState       = _create_dynamic_info(g, create_info),
		pDepthStencilState  = _create_depth_stencil_info(g, create_info),
		layout              = pipeline_layout,
		renderPass          = g.render_pass,
		subpass             = 0,
		basePipelineIndex   = -1,
	}

	pipeline := new(Pipeline, allocator)
	must(vk.CreateGraphicsPipelines(g.device, 0, 1, &pipeline_info, nil, &pipeline.pipeline))
	pipeline.create_info = create_info
	pipeline.layout = pipeline_layout
	pipeline.descriptor_set_layouts = descriptor_set_layouts

	return pipeline, true
}

_copy_create_pipeline_info :: proc(
	info: ^Create_Pipeline_Info,
	allocator := context.allocator,
) -> ^Create_Pipeline_Info {
	copy_info := new(Create_Pipeline_Info, allocator)
	copy_info.name = info.name

	copy_info.set_infos = make([]Pipeline_Set_Info, len(info.set_infos))
	copy(copy_info.set_infos, info.set_infos)

	copy_info.stage_infos = make([]Pipeline_Stage_Info, len(info.stage_infos))
	copy(copy_info.stage_infos, info.stage_infos)

	copy_info.vertex_input_description = info.vertex_input_description
	copy_info.vertex_input_description.attribute_descriptions = make(
		[]Vertex_Input_Attribute_Description,
		len(info.vertex_input_description.attribute_descriptions),
	)
	copy(
		copy_info.vertex_input_description.attribute_descriptions,
		info.vertex_input_description.attribute_descriptions,
	)

	copy_info.input_assembly = info.input_assembly
	copy_info.rasterizer = info.rasterizer
	copy_info.multisampling = info.multisampling
	copy_info.depth_stencil = info.depth_stencil

	return copy_info
}

_destroy_create_pipeline_info :: proc(info: ^Create_Pipeline_Info) {
	delete(info.set_infos)
	delete(info.stage_infos)
	delete(info.vertex_input_description.attribute_descriptions)
	free(info)
}

_set_infos_to_descriptor_set_layouts :: proc(
	g: ^Graphics,
	set_infos: []Pipeline_Set_Info,
	allocator := context.allocator,
) -> []vk.DescriptorSetLayout {
	descriptor_set_layouts := make([]vk.DescriptorSetLayout, len(set_infos))
	for set_info, i in set_infos {
		descriptor_set_layouts[i] = _set_info_to_descriptor_set_layout(g, set_info)
	}
	return descriptor_set_layouts
}

_set_info_to_descriptor_set_layout :: proc(g: ^Graphics, set_info: Pipeline_Set_Info) -> vk.DescriptorSetLayout {
	descriptor_bindings := make([dynamic]vk.DescriptorSetLayoutBinding, context.temp_allocator)

	for binding in set_info.binding_infos {
		append(
			&descriptor_bindings,
			vk.DescriptorSetLayoutBinding {
				binding = binding.binding,
				descriptorType = binding.descriptor_type,
				descriptorCount = binding.descriptor_count,
				stageFlags = binding.stage_flags,
				pImmutableSamplers = nil,
			},
		)
	}

	descriptor_set_layout := vk.DescriptorSetLayout{}

	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = cast(u32)len(descriptor_bindings),
		pBindings    = raw_data(descriptor_bindings),
	}

	must(
		vk.CreateDescriptorSetLayout(g.device, &layout_info, nil, &descriptor_set_layout),
		"failed to create descriptor set layout!",
	)

	return descriptor_set_layout
}

_destroy_descriptor_set_layout :: proc(g: ^Graphics, descriptor_set_layout: vk.DescriptorSetLayout) {
	vk.DestroyDescriptorSetLayout(g.device, descriptor_set_layout, nil)
}

_create_shader_stages :: proc(
	g: ^Graphics,
	create_info: ^Create_Pipeline_Info,
	allocator := context.temp_allocator,
) -> (
	[]vk.PipelineShaderStageCreateInfo,
	bool,
) {
	shader_stages := make([]vk.PipelineShaderStageCreateInfo, len(create_info.stage_infos))

	for stage_info, i in create_info.stage_infos {
		shader_module, ok := create_shader_module(g.device, stage_info.shader_path)
		if !ok {
			log.errorf("couldn't create shader module for stage %v. Name: %s", stage_info.stage, create_info.name)
			return nil, false
		}
		shader_stages[i] = vk.PipelineShaderStageCreateInfo {
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = stage_info.stage,
			module = shader_module,
			pName  = "main",
		}
	}

	return shader_stages, true
}

_destroy_shader_stages :: proc(g: ^Graphics, shader_stages: []vk.PipelineShaderStageCreateInfo) {
	for shader_stage in shader_stages {
		vk.DestroyShaderModule(g.device, shader_stage.module, nil)
	}
}

_create_dynamic_info :: proc(
	g: ^Graphics,
	create_info: ^Create_Pipeline_Info,
	allocator := context.temp_allocator,
) -> ^vk.PipelineDynamicStateCreateInfo {
	dynamic_states := make([]vk.DynamicState, 2, allocator)
	dynamic_states[0] = .VIEWPORT
	dynamic_states[1] = .SCISSOR

	dynamic_state := new(vk.PipelineDynamicStateCreateInfo, allocator)
	dynamic_state.sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO
	dynamic_state.dynamicStateCount = 2
	dynamic_state.pDynamicStates = raw_data(dynamic_states)

	return dynamic_state
}

_create_vertex_input_info :: proc(
	g: ^Graphics,
	create_info: ^Create_Pipeline_Info,
	allocator := context.temp_allocator,
) -> ^vk.PipelineVertexInputStateCreateInfo {
	bind_description := new(Vertex_Input_Binding_Description, allocator)
	bind_description.binding = 0
	bind_description.stride = size_of(Vertex)
	bind_description.inputRate = create_info.vertex_input_description.input_rate

	vertex_input_info := new(vk.PipelineVertexInputStateCreateInfo, allocator)
	vertex_input_info.sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
	vertex_input_info.vertexBindingDescriptionCount = 1
	vertex_input_info.vertexAttributeDescriptionCount =
	cast(u32)len(create_info.vertex_input_description.attribute_descriptions)
	vertex_input_info.pVertexBindingDescriptions = bind_description
	vertex_input_info.pVertexAttributeDescriptions = raw_data(
		create_info.vertex_input_description.attribute_descriptions,
	)

	return vertex_input_info
}

_create_input_assembly_info :: proc(
	g: ^Graphics,
	create_info: ^Create_Pipeline_Info,
	allocator := context.temp_allocator,
) -> ^vk.PipelineInputAssemblyStateCreateInfo {
	input_assembly := new(vk.PipelineInputAssemblyStateCreateInfo, allocator)
	input_assembly.sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
	input_assembly.topology = create_info.input_assembly.topology

	return input_assembly
}

_create_viewport_info :: proc(
	g: ^Graphics,
	create_info: ^Create_Pipeline_Info,
	allocator := context.temp_allocator,
) -> ^vk.PipelineViewportStateCreateInfo {
	viewport_state := new(vk.PipelineViewportStateCreateInfo, allocator)
	viewport_state.sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO
	viewport_state.viewportCount = 1
	viewport_state.scissorCount = 1

	return viewport_state
}

_create_rasterizer :: proc(
	g: ^Graphics,
	create_info: ^Create_Pipeline_Info,
	allocator := context.temp_allocator,
) -> ^vk.PipelineRasterizationStateCreateInfo {
	rasterizer := new(vk.PipelineRasterizationStateCreateInfo, allocator)
	rasterizer.sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO
	rasterizer.polygonMode = create_info.rasterizer.polygonMode
	rasterizer.lineWidth = create_info.rasterizer.lineWidth
	rasterizer.cullMode = create_info.rasterizer.cullMode
	rasterizer.frontFace = create_info.rasterizer.frontFace

	return rasterizer
}

_create_multisampling_info :: proc(
	g: ^Graphics,
	create_info: ^Create_Pipeline_Info,
	allocator := context.temp_allocator,
) -> ^vk.PipelineMultisampleStateCreateInfo {
	multisampling := new(vk.PipelineMultisampleStateCreateInfo, allocator)
	multisampling.sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
	multisampling.rasterizationSamples = g.msaa_samples
	multisampling.minSampleShading = 1

	return multisampling
}

_create_color_blend_info :: proc(
	g: ^Graphics,
	create_info: ^Create_Pipeline_Info,
	allocator := context.temp_allocator,
) -> ^vk.PipelineColorBlendStateCreateInfo {
	color_blend_attachment := new(vk.PipelineColorBlendAttachmentState, context.temp_allocator)
	color_blend_attachment.colorWriteMask = {.R, .G, .B, .A}

	color_blending := new(vk.PipelineColorBlendStateCreateInfo, context.temp_allocator)
	color_blending.sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
	color_blending.attachmentCount = 1
	color_blending.pAttachments = color_blend_attachment

	return color_blending
}

_create_depth_stencil_info :: proc(
	g: ^Graphics,
	create_info: ^Create_Pipeline_Info,
	allocator := context.temp_allocator,
) -> ^vk.PipelineDepthStencilStateCreateInfo {
	depth_stencil := new(vk.PipelineDepthStencilStateCreateInfo, context.temp_allocator)
	depth_stencil.sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
	depth_stencil.depthTestEnable = create_info.depth_stencil.depthTestEnable
	depth_stencil.depthWriteEnable = create_info.depth_stencil.depthWriteEnable
	depth_stencil.depthCompareOp = create_info.depth_stencil.depthCompareOp
	depth_stencil.depthBoundsTestEnable = create_info.depth_stencil.depthBoundsTestEnable
	depth_stencil.minDepthBounds = create_info.depth_stencil.minDepthBounds
	depth_stencil.maxDepthBounds = create_info.depth_stencil.maxDepthBounds
	depth_stencil.stencilTestEnable = create_info.depth_stencil.stencilTestEnable
	depth_stencil.front = create_info.depth_stencil.front
	depth_stencil.back = create_info.depth_stencil.back

	return depth_stencil
}

_create_pipeline_layout :: proc(
	g: ^Graphics,
	descriptor_set_layouts: []vk.DescriptorSetLayout,
	allocator := context.allocator,
) -> vk.PipelineLayout {

	pipeline_layout_info := vk.PipelineLayoutCreateInfo {
		sType          = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = cast(u32)len(descriptor_set_layouts),
		pSetLayouts    = raw_data(descriptor_set_layouts),
	}

	layout := vk.PipelineLayout{}
	must(vk.CreatePipelineLayout(g.device, &pipeline_layout_info, nil, &layout))

	return layout
}

_create_descriptor_pool :: proc(g: ^Graphics) {
	pool_sizes := [?]vk.DescriptorPoolSize {
		vk.DescriptorPoolSize{type = .UNIFORM_BUFFER, descriptorCount = UNIFORM_DESCRIPTOR_MAX},
		vk.DescriptorPoolSize{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = IMAGE_SAMPLER_DESCRIPTOR_MAX},
		vk.DescriptorPoolSize{type = .STORAGE_BUFFER, descriptorCount = STORAGE_DESCRIPTOR_MAX},
	}

	poolInfo := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = len(pool_sizes),
		pPoolSizes    = raw_data(&pool_sizes),
		maxSets       = DESCRIPTOR_SET_MAX,
	}

	must(vk.CreateDescriptorPool(g.device, &poolInfo, nil, &g.descriptor_pool), "failed to create descriptor pool!")
}

_destroy_descriptor_pool :: proc(g: ^Graphics) {
	vk.DestroyDescriptorPool(g.device, g.descriptor_pool, nil)
}

_create_descriptor_set :: proc(
	g: ^Graphics,
	pipeline: ^Pipeline,
	set_index: int,
	resources: []Pipeline_Resource,
) -> vk.DescriptorSet {
	set_info := pipeline.create_info.set_infos[set_index]
	descripotr_set_layout := pipeline.descriptor_set_layouts[set_index]

	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = g.descriptor_pool,
		descriptorSetCount = 1,
		pSetLayouts        = &pipeline.descriptor_set_layouts[set_index],
	}

	descriptor_set: vk.DescriptorSet
	must(vk.AllocateDescriptorSets(g.device, &alloc_info, &descriptor_set), "failed to allocate descriptor sets!")

	assert(len(set_info.binding_infos) == len(resources))

	write_descriptor_sets := make([]vk.WriteDescriptorSet, len(resources), context.temp_allocator)
	for binding, i in set_info.binding_infos {
		resource := resources[i]
		switch r in resource {
		case Texture:
			descriptor_image_info := new(vk.DescriptorImageInfo, context.temp_allocator)
			descriptor_image_info.imageLayout = .SHADER_READ_ONLY_OPTIMAL
			descriptor_image_info.imageView = r.image.view
			descriptor_image_info.sampler = r.sampler

			write_descriptor_sets[i] = vk.WriteDescriptorSet {
				sType           = .WRITE_DESCRIPTOR_SET,
				dstSet          = descriptor_set,
				dstBinding      = binding.binding,
				descriptorType  = binding.descriptor_type,
				dstArrayElement = 0,
				descriptorCount = binding.descriptor_count,
				pImageInfo      = descriptor_image_info,
			}
		case Uniform_Buffer:
			descriptor_buffer_info := new(vk.DescriptorBufferInfo, context.temp_allocator)
			descriptor_buffer_info.buffer = r.buffer
			descriptor_buffer_info.offset = 0
			descriptor_buffer_info.range = cast(vk.DeviceSize)vk.WHOLE_SIZE

			write_descriptor_sets[i] = vk.WriteDescriptorSet {
				sType           = .WRITE_DESCRIPTOR_SET,
				dstSet          = descriptor_set,
				dstBinding      = binding.binding,
				descriptorType  = binding.descriptor_type,
				dstArrayElement = 0,
				descriptorCount = binding.descriptor_count,
				pBufferInfo     = descriptor_buffer_info,
			}
		case Buffer:
			descriptor_buffer_info := new(vk.DescriptorBufferInfo, context.temp_allocator)
			descriptor_buffer_info.buffer = r.buffer
			descriptor_buffer_info.offset = 0
			descriptor_buffer_info.range = cast(vk.DeviceSize)vk.WHOLE_SIZE

			write_descriptor_sets[i] = vk.WriteDescriptorSet {
				sType           = .WRITE_DESCRIPTOR_SET,
				dstSet          = descriptor_set,
				dstBinding      = binding.binding,
				descriptorType  = binding.descriptor_type,
				dstArrayElement = 0,
				descriptorCount = binding.descriptor_count,
				pBufferInfo     = descriptor_buffer_info,
			}
		}
	}

	vk.UpdateDescriptorSets(g.device, cast(u32)len(write_descriptor_sets), raw_data(write_descriptor_sets), 0, nil)
	return descriptor_set
}

_reload_pipeline :: proc(g: ^Graphics, pipeline: ^Pipeline) {
	vk.DestroyPipeline(g.device, pipeline.pipeline, nil)

	create_info := pipeline.create_info

	shader_stages, ok := _create_shader_stages(g, create_info)
	if !ok {
		return
	}
	defer _destroy_shader_stages(g, shader_stages)

	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = cast(u32)len(shader_stages),
		pStages             = raw_data(shader_stages),
		pVertexInputState   = _create_vertex_input_info(g, create_info),
		pInputAssemblyState = _create_input_assembly_info(g, create_info),
		pViewportState      = _create_viewport_info(g, create_info),
		pRasterizationState = _create_rasterizer(g, create_info),
		pMultisampleState   = _create_multisampling_info(g, create_info),
		pColorBlendState    = _create_color_blend_info(g, create_info),
		pDynamicState       = _create_dynamic_info(g, create_info),
		pDepthStencilState  = _create_depth_stencil_info(g, create_info),
		layout              = pipeline.layout,
		renderPass          = g.render_pass,
		subpass             = 0,
		basePipelineIndex   = -1,
	}

	must(vk.CreateGraphicsPipelines(g.device, 0, 1, &pipeline_info, nil, &pipeline.pipeline))
}
