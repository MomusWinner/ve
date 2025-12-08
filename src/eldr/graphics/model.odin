package graphics

import "core:log"
import vk "vendor:vulkan"

create_mesh :: proc(vertices: []Vertex, indices: []u16, loc := #caller_location) -> Mesh {
	assert(len(vertices) > 0, loc = loc)

	vertices_size := cast(vk.DeviceSize)(size_of(vertices[0]) * len(vertices))
	vertex_buffer := create_vertex_buffer(raw_data(vertices), vertices_size)

	mesh := Mesh {
		vertices = vertices,
		indices  = indices,
		vbo      = vertex_buffer,
	}

	if len(indices) != 0 {
		indices_size := cast(vk.DeviceSize)(size_of(indices[0]) * len(indices))
		index_buffer := create_index_buffer(raw_data(indices), indices_size)
		mesh.ebo = index_buffer
	} else {
		mesh.ebo = nil
	}

	return mesh
}

destroy_mesh :: proc(mesh: ^Mesh, loc := #caller_location) {
	assert_not_nil(mesh)

	destroy_buffer(&mesh.vbo)
	ebo, has_ebo := mesh.ebo.?
	if has_ebo {
		destroy_buffer(&ebo)
	}
	delete(mesh.vertices)
	delete(mesh.indices)
}

draw_mesh :: proc(
	frame_data: Frame_Data,
	mesh: ^Mesh,
	material: ^Material,
	camera: ^Camera,
	transform: ^Gfx_Transform,
	loc := #caller_location,
) {
	assert_gfx_ctx(loc)
	assert_not_nil(mesh, loc)
	assert_not_nil(material, loc)
	assert_not_nil(camera, loc)
	assert_not_nil(transform, loc)
	assert_frame_data(frame_data, loc)

	ebo, has_ebo := mesh.ebo.?

	offset := vk.DeviceSize{}
	vk.CmdBindVertexBuffers(frame_data.cmd, 0, 1, &mesh.vbo.buffer, &offset)
	if has_ebo {
		vk.CmdBindIndexBuffer(frame_data.cmd, ebo.buffer, 0, .UINT16)
	}

	pipeline, ok := get_graphics_pipeline(material.pipeline_h)
	assert(ok, "Couldn't get pipeline")

	_trf_apply(transform)
	material.apply(material)

	bind_pipeline(pipeline, frame_data, loc)

	bindless_bind(frame_data.cmd, pipeline.layout)

	const := Push_Constant {
		camera   = _camera_get_buffer(camera, get_screen_aspect()).index,
		model    = transform.buffer_h.index,
		material = material.buffer_h.index,
	}

	vk.CmdPushConstants(
		frame_data.cmd,
		pipeline.layout,
		vk.ShaderStageFlags_ALL_GRAPHICS,
		0,
		size_of(Push_Constant),
		&const,
	)

	if has_ebo {
		vk.CmdDrawIndexed(frame_data.cmd, cast(u32)len(mesh.indices), 1, 0, 0, 0)
	} else {
		vk.CmdDraw(frame_data.cmd, cast(u32)len(mesh.vertices), 1, 0, 0)
	}
}

create_model :: proc(meshes: []Mesh, materials: [dynamic]Material, mesh_material: [dynamic]int) -> Model {
	return Model{meshes = meshes, materials = materials, mesh_material = mesh_material}
}

destroy_model :: proc(model: ^Model) {
	for &mesh in model.meshes {
		destroy_mesh(&mesh)
	}
	for &mat in model.materials {
		destroy_mtrl(&mat)
	}

	delete(model.meshes)
	delete(model.materials)
	delete(model.mesh_material)
}

draw_model :: proc(
	frame_data: Frame_Data,
	model: Model,
	camera: ^Camera,
	transform: ^Gfx_Transform,
	loc := #caller_location,
) {
	assert_gfx_ctx(loc)
	assert_not_nil(transform, loc)
	for &mesh, i in model.meshes {
		material_index := model.mesh_material[i]
		draw_mesh(frame_data, &mesh, &model.materials[material_index], camera, transform, loc)
	}
}
