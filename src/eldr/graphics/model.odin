package graphics

import "core:log"
import vk "vendor:vulkan"

Model :: struct {
	meshes:        []Mesh,
	materials:     [dynamic]Material,
	mesh_material: [dynamic]int,
}

Mesh :: struct {
	vbo:      Buffer,
	ebo:      Maybe(Buffer),
	vertices: []Vertex,
	indices:  []u16,
}

create_mesh :: proc(g: ^Graphics, vertices: []Vertex, indices: []u16) -> Mesh {
	assert(len(vertices) > 0)
	vertices_size := cast(vk.DeviceSize)(size_of(vertices[0]) * len(vertices))
	vertex_buffer := create_vertex_buffer(g, raw_data(vertices), vertices_size)

	mesh := Mesh {
		vertices = vertices,
		indices  = indices,
		vbo      = vertex_buffer,
	}

	if len(indices) != 0 {
		indices_size := cast(vk.DeviceSize)(size_of(indices[0]) * len(indices))
		index_buffer := create_index_buffer(g, raw_data(indices), indices_size)
		mesh.ebo = index_buffer
	} else {
		mesh.ebo = nil
	}

	return mesh
}

destroy_mesh :: proc(g: ^Graphics, mesh: ^Mesh) {
	destroy_buffer(g, &mesh.vbo)
	ebo, has_ebo := mesh.ebo.?
	if has_ebo {destroy_buffer(g, &ebo)}
	delete(mesh.vertices)
	delete(mesh.indices)
}

draw_mesh :: proc(
	g: ^Graphics,
	mesh: ^Mesh,
	material: Material,
	camera: Camera,
	transform: Transform,
	cmd: vk.CommandBuffer,
) {
	ebo, has_ebo := mesh.ebo.?

	offset := vk.DeviceSize{}
	vk.CmdBindVertexBuffers(cmd, 0, 1, &mesh.vbo.buffer, &offset)
	if has_ebo {
		vk.CmdBindIndexBuffer(cmd, ebo.buffer, 0, .UINT16)
	}

	pipeline, ok := get_graphics_pipeline(g, material.pipeline_h)
	if !ok {
		log.error("Couldn't get pipeline")
	}

	bind_pipeline(g, pipeline)

	// gfx.bind_descriptor_set(e.g, pipeline, &data.descriptor_set)
	bindless_bind(g, cmd, pipeline.layout)

	const := Push_Constant {
		camera   = camera.buffer_h.index,
		model    = transform.buffer_h.index,
		material = material.buffer_h.index,
	}

	vk.CmdPushConstants(cmd, pipeline.layout, vk.ShaderStageFlags_ALL_GRAPHICS, 0, size_of(Push_Constant), &const)

	if has_ebo {
		vk.CmdDrawIndexed(cmd, cast(u32)len(mesh.indices), 1, 0, 0, 0)
	} else {
		vk.CmdDraw(cmd, cast(u32)len(mesh.vertices), 1, 0, 0)
	}
}

create_model :: proc(meshes: []Mesh, materials: [dynamic]Material, mesh_material: [dynamic]int) -> Model {
	return Model{meshes = meshes, materials = materials, mesh_material = mesh_material}
}

destroy_model :: proc(g: ^Graphics, model: ^Model) {
	for &mesh in model.meshes {
		destroy_mesh(g, &mesh)
	}
	delete(model.meshes)
	delete(model.materials)
	delete(model.mesh_material)
}

draw_model :: proc(g: ^Graphics, model: Model, camera: Camera, transform: Transform, cmd: vk.CommandBuffer) {
	for &mesh, i in model.meshes {
		material_index := model.mesh_material[i]
		draw_mesh(g, &mesh, model.materials[material_index], camera, transform, cmd)
	}
}
