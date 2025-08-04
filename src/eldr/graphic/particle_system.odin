package graphic

import "base:runtime"
import "core:log"
import "core:math"
import "core:math/linalg/glsl"
import "core:math/rand"
import vk "vendor:vulkan"

PARTICLE_COUNT :: 256
DRAW_PIPELINE_NAME :: "particle_pipeline"

Particle :: struct {
	position: glsl.vec2,
	velocity: glsl.vec2,
	color:    glsl.vec4,
}

UniformBufferObject :: struct {
	delta_time: f32,
}

ParticleRenderer :: struct {
	g:                   ^Graphic,
	uniform_buffer:      UniformBuffer,
	ssbo:                Buffer,
	descriptor_set:      vk.DescriptorSet,
	draw_descriptor_set: vk.DescriptorSet,
	comp_pipeline:       ^Pipeline,
	fence:               vk.Fence,
	semaphore:           vk.Semaphore,
	command_buffer:      vk.CommandBuffer,
}

particle_update_uniform_buffer :: proc(r: ^ParticleRenderer, delta_time: f32) {
	ubo := UniformBufferObject {
		delta_time = delta_time,
	}

	runtime.mem_copy(r.uniform_buffer.mapped, &ubo, size_of(ubo))
}

particle_new :: proc(g: ^Graphic) -> ^ParticleRenderer {
	renderer := new(ParticleRenderer)
	renderer.g = g
	particles := generate_particles(cast(f32)g.swapchain.extent.width, cast(f32)g.swapchain.extent.height)
	renderer.uniform_buffer = create_uniform_buffer(g, cast(vk.DeviceSize)size_of(f32))
	renderer.ssbo = create_ssbo(g, particles)
	renderer.comp_pipeline = create_comp_pipeline(g)
	renderer.descriptor_set = _create_descriptor_set(
		g,
		renderer.comp_pipeline,
		0,
		{renderer.uniform_buffer, renderer.ssbo},
	)

	create_draw_pipeline(g)
	draw_pipeline_descriptor_set, ok := create_descriptor_set(g, DRAW_PIPELINE_NAME, 0, {renderer.ssbo})
	if !ok {
		log.error("couldn't create descriptor set for particle pipeline")
	}
	renderer.draw_descriptor_set = draw_pipeline_descriptor_set

	// Semaphore
	semaphore_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	vk.CreateSemaphore(g.device, &semaphore_info, nil, &renderer.semaphore)

	// Fence
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	vk.CreateFence(g.device, &fence_info, nil, &renderer.fence)

	// Command buffer
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = g.command_pool,
		commandBufferCount = 1,
	}
	must(vk.AllocateCommandBuffers(g.device, &alloc_info, &renderer.command_buffer))

	return renderer
}

particle_compute :: proc(r: ^ParticleRenderer) {
	must(vk.WaitForFences(r.g.device, 1, &r.fence, true, max(u64)))
	must(vk.ResetFences(r.g.device, 1, &r.fence))
	must(vk.ResetCommandBuffer(r.command_buffer, {}))

	being_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {},
	}
	must(vk.BeginCommandBuffer(r.command_buffer, &being_info))

	vk.CmdBindPipeline(r.command_buffer, .COMPUTE, r.comp_pipeline.pipeline)
	vk.CmdBindDescriptorSets(r.command_buffer, .COMPUTE, r.comp_pipeline.layout, 0, 1, &r.descriptor_set, 0, nil)
	vk.CmdDispatch(r.command_buffer, PARTICLE_COUNT / 256, 1, 1)

	must(vk.EndCommandBuffer(r.command_buffer))

	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		commandBufferCount   = 1,
		pCommandBuffers      = &r.command_buffer,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &r.semaphore,
	}

	must(vk.QueueSubmit(r.g.graphics_queue, 1, &submit_info, r.fence))
}

particle_draw :: proc(r: ^ParticleRenderer) {
	bind_pipeline(r.g, DRAW_PIPELINE_NAME)
	offset := vk.DeviceSize{}
	vk.CmdBindVertexBuffers(r.g.command_buffer, 0, 1, &r.ssbo.buffer, &offset)
	bind_descriptor_set(r.g, DRAW_PIPELINE_NAME, &r.draw_descriptor_set)
	vk.CmdDraw(r.g.command_buffer, PARTICLE_COUNT, 1, 0, 0)
}

default_shader_attribute :: proc() -> (VertexInputBindingDescription, [2]VertexInputAttributeDescription) {
	bind_description := VertexInputBindingDescription {
		binding   = 0,
		stride    = size_of(Particle),
		inputRate = .VERTEX,
	}

	attribute_descriptions := [2]VertexInputAttributeDescription {
		{binding = 0, location = 0, format = .R32G32_SFLOAT, offset = cast(u32)offset_of(Particle, position)},
		{binding = 0, location = 1, format = .R32G32B32_SFLOAT, offset = cast(u32)offset_of(Particle, color)},
	}

	return bind_description, attribute_descriptions
}

@(private = "file")
create_ssbo :: proc(g: ^Graphic, particles: []Particle) -> Buffer {
	size := cast(vk.DeviceSize)(size_of(Particle) * cast(f32)len(particles))

	staging_buffer := create_buffer(g, size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT})
	fill_buffer(g, staging_buffer, size, raw_data(particles))

	ssbo := create_buffer(g, size, {.TRANSFER_DST, .VERTEX_BUFFER, .STORAGE_BUFFER}, {.DEVICE_LOCAL})
	copy_buffer(g, staging_buffer, ssbo, size)

	destroy_buffer(g, &staging_buffer)

	return ssbo
}

@(private = "file")
create_compute_stage :: proc(g: ^Graphic) {
	module, ok := create_shader_module(g.device, "assets/shader.comp")
	if !ok {
		log.error("couldn't find comp shader")
	}

	comp_stage_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.COMPUTE},
		module = module,
		pName  = "main",
	}
}

@(private = "file")
generate_particles :: proc(width, height: f32) -> []Particle {
	rand.reset(30)
	particles := make([]Particle, PARTICLE_COUNT)

	for &particle in particles {
		r := 0.25 * math.sqrt_f32(cast(f32)rand.float32_range(0, 1))
		theta := cast(f32)rand.float32_range(0, 1) * 2 * math.PI
		x := r * math.cos(theta) * height / width
		y := r * math.sin(theta)
		particle.position = glsl.vec2{x, y}
		particle.velocity = glsl.normalize(particle.position) * 0.5
		particle.color = glsl.vec4 {
			cast(f32)rand.float32_range(0, 1),
			cast(f32)rand.float32_range(0, 1),
			cast(f32)rand.float32_range(0, 1),
			cast(f32)rand.float32_range(0, 1),
		}
	}

	return particles
}

@(private)
create_draw_pipeline :: proc(g: ^Graphic) {
	vert_bind, vert_attr := default_shader_attribute()

	bindings := make([]PipelineSetBindingInfo, 1)
	bindings[0] = PipelineSetBindingInfo {
		binding          = 0,
		descriptor_type  = .STORAGE_BUFFER,
		descriptor_count = 1,
		stage_flags      = {.VERTEX},
	}

	set_infos := []PipelineSetInfo{PipelineSetInfo{set = 0, binding_infos = bindings}}

	create_info := CreatePipelineInfo {
		name = DRAW_PIPELINE_NAME,
		set_infos = set_infos,
		vertex_input_description = {binding_description = vert_bind, attribute_descriptions = vert_attr[:]},
		stage_infos = []PipelineStageInfo {
			PipelineStageInfo{stage = {.VERTEX}, shader_path = "assets/particle_vert.spv"},
			PipelineStageInfo{stage = {.FRAGMENT}, shader_path = "assets/particle_frag.spv"},
		},
		input_assembly = {topology = .POINT_LIST},
		rasterizer = {polygonMode = .FILL, lineWidth = 1, cullMode = {}, frontFace = .CLOCKWISE},
		multisampling = {rasterizationSamples = {._1}, minSampleShading = 1},
		depth_stencil = {
			depthTestEnable = false,
			depthWriteEnable = true,
			depthCompareOp = .LESS,
			depthBoundsTestEnable = false,
			minDepthBounds = 0,
			maxDepthBounds = 0,
			stencilTestEnable = false,
			front = {},
			back = {},
		},
	}

	create_pipeline(g, &create_info)
}

@(private = "file")
create_comp_pipeline :: proc(g: ^Graphic) -> ^Pipeline {
	module, ok := create_shader_module(g.device, "assets/particle_comp.spv")
	if !ok {
		log.error("couldn't find comp shader")
	}

	comp_stage_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.COMPUTE},
		module = module,
		pName  = "main",
	}

	pipeline_binding_infos := make([]PipelineSetBindingInfo, 2)
	pipeline_binding_infos[0] = PipelineSetBindingInfo {
		binding          = 0,
		descriptor_type  = .UNIFORM_BUFFER,
		descriptor_count = 1,
		stage_flags      = {.COMPUTE},
	}
	pipeline_binding_infos[1] = PipelineSetBindingInfo {
		binding          = 1,
		descriptor_type  = .STORAGE_BUFFER,
		descriptor_count = 1,
		stage_flags      = {.COMPUTE},
	}
	set_info := PipelineSetInfo {
		set           = 0,
		binding_infos = pipeline_binding_infos,
	}

	set_infos := make([]PipelineSetInfo, 1)
	set_infos[0] = set_info

	pipeline_info := new(CreatePipelineInfo)
	pipeline_info.set_infos = set_infos

	descriptor_set_layouts := _set_infos_to_descriptor_set_layouts(g, set_infos)
	pipeline_layout := _create_pipeline_layout(g, descriptor_set_layouts)

	create_info := vk.ComputePipelineCreateInfo {
		sType  = .COMPUTE_PIPELINE_CREATE_INFO,
		layout = pipeline_layout,
		stage  = comp_stage_info,
	}

	pipeline := vk.Pipeline{}

	vk.CreateComputePipelines(g.device, vk.FALSE, 1, &create_info, nil, &pipeline)

	result := new(Pipeline)
	result.pipeline = pipeline
	result.create_info = pipeline_info
	result.layout = pipeline_layout
	result.descriptor_set_layouts = descriptor_set_layouts

	return result
}
