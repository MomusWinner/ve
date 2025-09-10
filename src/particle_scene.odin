// NOTE: Don't look here it's not ready yet
package main

import "base:runtime"
import "core:log"
import "core:math"
import "core:math/linalg/glsl"
import "core:math/rand"
import "eldr"
import gfx "eldr/graphics"
import vk "vendor:vulkan"

PARTICLE_COUNT :: 256

Particle :: struct {
	position: glsl.vec2,
	velocity: glsl.vec2,
	color:    glsl.vec4,
}

ParticleUniformBufferObject :: struct {
	delta_time: f32,
}


ParticleSceneData :: struct {
	uniform_buffer:      gfx.Buffer,
	ssbo:                gfx.Buffer,
	descriptor_set:      vk.DescriptorSet,
	draw_descriptor_set: vk.DescriptorSet,
	draw_pipeline_h:     gfx.Pipeline_Handle,
	comp_pipeline_h:     gfx.Pipeline_Handle,
	fence:               vk.Fence,
	semaphore:           vk.Semaphore,
	command_buffer:      vk.CommandBuffer,
}

create_particle_scene :: proc(e: ^eldr.Eldr) -> Scene {
	return Scene{init = particle_scene_init, update = particle_scene_update, draw = particle_scene_draw}
}

particle_scene_init :: proc(s: ^Scene) {
	renderer := new(ParticleSceneData)
	g := eldr.ctx.g

	particles := _generate_particles(cast(f32)g.swapchain.extent.width, cast(f32)g.swapchain.extent.height)
	renderer.uniform_buffer = gfx.create_uniform_buffer(g, cast(vk.DeviceSize)size_of(f32))

	size := cast(vk.DeviceSize)(size_of(Particle) * cast(f32)len(particles))
	renderer.ssbo = gfx.create_ssbo(g, raw_data(particles), size)
	renderer.comp_pipeline_h = _create_comp_pipeline(g)

	comp_pipeline, _ := gfx.get_compute_pipeline(g, renderer.comp_pipeline_h)

	renderer.descriptor_set = gfx.create_descriptor_set(
		g,
		comp_pipeline,
		comp_pipeline.create_info.set_infos[0],
		{renderer.uniform_buffer, renderer.ssbo},
	)
	renderer.draw_pipeline_h = _create_draw_pipeline(g)

	draw_pipeline, _ := gfx.get_graphics_pipeline(g, renderer.draw_pipeline_h)
	draw_pipeline_descriptor_set := gfx.create_descriptor_set(
		g,
		draw_pipeline,
		draw_pipeline.create_info.set_infos[0],
		{renderer.ssbo},
	)

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
	vk.AllocateCommandBuffers(g.device, &alloc_info, &renderer.command_buffer)
	s.data = renderer
}

particle_scene_update :: proc(s: ^Scene, dt: f64) {
	e := &eldr.ctx
	data := cast(^ParticleSceneData)s.data
	_particle_update_uniform_buffer(data.uniform_buffer, cast(f32)dt)
	particle_compute(e.g, data)
}

particle_scene_draw :: proc(s: ^Scene) {
	e := &eldr.ctx
	data := cast(^ParticleSceneData)s.data

	pipeline, ok := gfx.get_graphics_pipeline(e.g, data.draw_pipeline_h)

	frame_data, _ := gfx.begin_render(e.g)
	// Begin gfx. ------------------------------

	viewport := vk.Viewport {
		width    = f32(e.g.swapchain.extent.width),
		height   = f32(e.g.swapchain.extent.height),
		maxDepth = 1.0,
	}
	vk.CmdSetViewport(e.g.cmd, 0, 1, &viewport)

	scissor := vk.Rect2D {
		extent = e.g.swapchain.extent,
	}
	vk.CmdSetScissor(e.g.cmd, 0, 1, &scissor)

	draw_pipeline, _ := gfx.get_graphics_pipeline(e.g, data.draw_pipeline_h)
	gfx.bind_pipeline(e.g, draw_pipeline)
	offset := vk.DeviceSize{}
	vk.CmdBindVertexBuffers(e.g.cmd, 0, 1, &data.ssbo.buffer, &offset)
	gfx.bind_descriptor_set(e.g, draw_pipeline, &data.draw_descriptor_set)
	vk.CmdDraw(e.g.cmd, PARTICLE_COUNT, 1, 0, 0)

	// End gfx. ------------------------------
	sync_data := eldr.Sync_Data {
		wait_semaphore_infos = []vk.SemaphoreSubmitInfo{{semaphore = data.semaphore, stageMask = {.VERTEX_INPUT}}},
	}
	gfx.end_render(e.g, frame_data, sync_data)
}

@(private = "file")
_generate_particles :: proc(width, height: f32) -> []Particle {
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

@(private = "file")
_create_comp_pipeline :: proc(g: ^gfx.Graphics) -> gfx.Pipeline_Handle {
	pipeline_binding_infos := make([]gfx.Pipeline_Set_Binding_Info, 2)
	pipeline_binding_infos[0] = gfx.Pipeline_Set_Binding_Info {
		binding          = 0,
		descriptor_type  = .UNIFORM_BUFFER,
		descriptor_count = 1,
		stage_flags      = {.COMPUTE},
	}
	pipeline_binding_infos[1] = gfx.Pipeline_Set_Binding_Info {
		binding          = 1,
		descriptor_type  = .STORAGE_BUFFER,
		descriptor_count = 1,
		stage_flags      = {.COMPUTE},
	}
	set_info := gfx.Pipeline_Set_Info {
		set           = 0,
		binding_infos = pipeline_binding_infos,
	}

	set_infos := make([]gfx.Pipeline_Set_Info, 1)
	set_infos[0] = set_info
	create_info := gfx.Create_Compute_Pipeline_Info {
		shader_path = "assets/particle_comp.spv",
		set_infos   = set_infos,
	}
	handle, ok := gfx.create_compute_pipeline(g, &create_info)
	if !ok {
		log.error("couldn't create pipeline")
	}
	return handle
}

@(private = "file")
_create_draw_pipeline :: proc(g: ^gfx.Graphics) -> gfx.Pipeline_Handle {
	vert_bind, vert_attr := _particle_shader_attribute()

	bindings := make([]gfx.Pipeline_Set_Binding_Info, 1)
	bindings[0] = gfx.Pipeline_Set_Binding_Info {
		binding          = 0,
		descriptor_type  = .STORAGE_BUFFER,
		descriptor_count = 1,
		stage_flags      = {.VERTEX},
	}

	set_infos := []gfx.Pipeline_Set_Info{gfx.Pipeline_Set_Info{set = 0, binding_infos = bindings}}

	create_info := gfx.Create_Pipeline_Info {
		set_infos = set_infos,
		vertex_input_description = {binding_description = vert_bind, attribute_descriptions = vert_attr[:]},
		stage_infos = []gfx.Pipeline_Stage_Info {
			{stage = {.VERTEX}, shader_path = "assets/particle_vert.spv"},
			{stage = {.FRAGMENT}, shader_path = "assets/particle_frag.spv"},
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

	handle, ok := gfx.create_graphics_pipeline(g, &create_info)
	if !ok {
		log.error("couldn't create draw particle pipeline")
	}
	return handle
}

@(private = "file")
_particle_shader_attribute :: proc(
) -> (
	gfx.Vertex_Input_Binding_Description,
	[2]gfx.Vertex_Input_Attribute_Description,
) {
	bind_description := gfx.Vertex_Input_Binding_Description {
		binding   = 0,
		stride    = size_of(Particle),
		inputRate = .VERTEX,
	}

	attribute_descriptions := [2]gfx.Vertex_Input_Attribute_Description {
		{binding = 0, location = 0, format = .R32G32_SFLOAT, offset = cast(u32)offset_of(Particle, position)},
		{binding = 0, location = 1, format = .R32G32B32_SFLOAT, offset = cast(u32)offset_of(Particle, color)},
	}

	return bind_description, attribute_descriptions
}

@(private = "file")
_particle_update_uniform_buffer :: proc(uniform_buffer: gfx.Buffer, delta_time: f32) {
	ubo := ParticleUniformBufferObject {
		delta_time = delta_time,
	}

	runtime.mem_copy(uniform_buffer.mapped, &ubo, size_of(ubo))
}

@(private = "file")
particle_compute :: proc(g: ^gfx.Graphics, data: ^ParticleSceneData) {
	vk.WaitForFences(g.device, 1, &data.fence, true, max(u64))
	vk.ResetFences(g.device, 1, &data.fence)
	vk.ResetCommandBuffer(data.command_buffer, {})

	being_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {},
	}
	vk.BeginCommandBuffer(data.command_buffer, &being_info)

	comp_pipeline, _ := gfx.get_compute_pipeline(g, data.comp_pipeline_h)

	vk.CmdBindPipeline(data.command_buffer, .COMPUTE, comp_pipeline.pipeline)
	vk.CmdBindDescriptorSets(data.command_buffer, .COMPUTE, comp_pipeline.layout, 0, 1, &data.descriptor_set, 0, nil)
	vk.CmdDispatch(data.command_buffer, PARTICLE_COUNT / 256, 1, 1)

	vk.EndCommandBuffer(data.command_buffer)

	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		commandBufferCount   = 1,
		pCommandBuffers      = &data.command_buffer,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &data.semaphore,
	}

	vk.QueueSubmit(g.graphics_queue, 1, &submit_info, data.fence)
}
