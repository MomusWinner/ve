package graphics

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
	descriptor_sets: []Descriptor_Set = {},
	bindless := true, // FIX:
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

	_trf_apply(transform)
	material.apply(material)

	g_pipeline := cmd_bind_render_pipeline(frame_data, pipeline, loc)

	if (bindless) {
		s := sm.Small_Array(MAX_PIPELINE_SET_COUNT, Descriptor_Set){}
		sm.push(&s, get_descriptor_set_bindless())
		sm.push(&s, ..descriptor_sets)
		cmd_bind_descriptor_set_graphics(frame_data, &g_pipeline, ..sm.slice(&s))
	} else {
		cmd_bind_descriptor_set_graphics(frame_data, &g_pipeline, ..descriptor_sets)
	}

	const := Push_Constant {
		camera   = _camera_get_buffer(camera, get_screen_aspect()).index,
		model    = transform.buffer_h.index,
		material = material.buffer_h.index,
	}

	cmd_push_constants(frame_data, g_pipeline, &const)

	if has_ebo {
		cmd_draw_indexed(frame_data, cast(u32)len(mesh.indices))
	} else {
		cmd_draw(frame_data, cast(u32)len(mesh.vertices))
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
	bindless: bool = true,
	descriptor_sets: []Descriptor_Set = {},
	loc := #caller_location,
) {
	assert_gfx_ctx(loc)
	assert_not_nil(transform, loc)

	for &mesh, i in model.meshes {
		material_index := model.mesh_material[i]
		draw_mesh(
			frame_data,
			&mesh,
			&model.materials[material_index],
			camera,
			transform,
			descriptor_sets,
			bindless,
			loc,
		)
	}
}
