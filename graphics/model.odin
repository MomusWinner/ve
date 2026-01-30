package graphics

import "../common"
import sm "core:container/small_array"
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

	cmd_bind_vertex_buffer(frame_data, mesh.vbo)
	if has_ebo {
		cmd_bind_index_buffer(frame_data, ebo)
	}

	pipeline, ok := get_render_pipeline(material.pipeline_h)
	assert(ok, "Couldn't get pipeline")

	g_pipeline := cmd_bind_material(frame_data, material, loc)

	const := Push_Constant {
		model    = common.trf_get_matrix(transform),
		camera   = _camera_get_buffer(camera, cast(f32)frame_data.surface_info.width / cast(f32)frame_data.surface_info.height).index,
		material = material.buffer_h.index,
		slots    = _g_res_manager_get_resource_indices(),
	}

	cmd_push_constants(frame_data, g_pipeline, &const)

	if has_ebo {
		cmd_draw_indexed(frame_data, cast(u32)len(mesh.indices))
	} else {
		cmd_draw(frame_data, cast(u32)len(mesh.vertices))
	}
}

create_model :: proc(meshes: []Mesh, materials: [dynamic]Material_Handle, mesh_material: [dynamic]int) -> Model {
	return Model{meshes = meshes, materials = materials, mesh_material = mesh_material}
}

destroy_model :: proc(model: ^Model) {
	for &mesh in model.meshes {
		destroy_mesh(&mesh)
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
		mtrl, ok := get_material(model.materials[material_index])
		assert(ok, loc = loc)

		draw_mesh(frame_data, &mesh, mtrl, camera, transform, loc)
	}
}

draw_model_solid :: proc(
	frame_data: Frame_Data,
	model: Model,
	camera: ^Camera,
	transform: ^Gfx_Transform,
	material: ^Material,
	loc := #caller_location,
) {
	assert_gfx_ctx(loc)
	assert_not_nil(transform, loc)

	for &mesh, i in model.meshes {
		draw_mesh(frame_data, &mesh, material, camera, transform, loc)
	}
}

model_set_material :: proc(model: ^Model, material_h: Material_Handle, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(model, loc)

	if model.mesh_material != nil {
		delete(model.mesh_material)
	}

	if model.materials != nil {
		delete(model.materials)
	}

	model.materials = make([dynamic]Material_Handle, 1)
	model.mesh_material = make([dynamic]int, len(model.meshes))

	model.materials[0] = material_h
	for &mesh, i in model.meshes {
		model.mesh_material[i] = 0
	}
}
