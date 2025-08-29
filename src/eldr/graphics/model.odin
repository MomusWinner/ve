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
	ebo:      Buffer,
	vertices: []Vertex,
	indices:  []u16,
}

// TODO:
// draw_model :: proc(g: ^Graphic, vbo: ^Buffer, ebo: ^Buffer) {
// 	offset := vk.DeviceSize{}
// 	vk.CmdBindVertexBuffers(g.command_buffer, 0, 1, &vbo.buffer, &offset)
// 	vk.CmdBindIndexBuffer(g.command_buffer, ebo.buffer, 0, .UINT16)
//
// 	vk.CmdBindDescriptorSets(
// 		g.command_buffer,
// 		.GRAPHICS,
// 		g.pipeline_layout,
// 		0,
// 		1,
// 		&descriptor_set,
// 		0,
// 		nil,
// 	)
// 	// vk.CmdDraw(gr.command_buffer, 3, 1, 0, 0)
// 	vk.CmdDrawIndexed(g.command_buffer, cast(u32)len(model.indices), 1, 0, 0, 0)
// }

create_mesh :: proc(g: ^Graphics, vertices: []Vertex, indices: []u16) -> Mesh {
	vertices_size := cast(vk.DeviceSize)(size_of(vertices[0]) * len(vertices))
	vertex_buffer := create_vertex_buffer(g, raw_data(vertices), vertices_size)

	indices_size := cast(vk.DeviceSize)(size_of(indices[0]) * len(indices))
	index_buffer := create_index_buffer(g, raw_data(indices), indices_size)

	return Mesh{vertices = vertices, indices = indices, vbo = vertex_buffer, ebo = index_buffer}
}

destroy_mesh :: proc(g: ^Graphics, mesh: ^Mesh) {
	destroy_buffer(g, &mesh.vbo)
	destroy_buffer(g, &mesh.ebo)
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
	offset := vk.DeviceSize{}
	vk.CmdBindVertexBuffers(cmd, 0, 1, &mesh.vbo.buffer, &offset)
	vk.CmdBindIndexBuffer(cmd, mesh.ebo.buffer, 0, .UINT16)

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
	vk.CmdDrawIndexed(cmd, cast(u32)len(mesh.indices), 1, 0, 0, 0)
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
