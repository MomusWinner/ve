package graphics

import "core:math/linalg/glsl"
//
// init_mat_base :: proc(material: ^Material, pipeline_h: Pipeline_Handle, loc := #caller_location) {
// 	assert_gfx_ctx(loc)
// 	assert_not_nil(material, loc)
//
// 	buffer := create_uniform_buffer(size_of(Base_Material_UBO))
// 	material.buffer_h = bindless_store_buffer(buffer)
// 	material.pipeline_h = pipeline_h
// 	mat := new(Base_Material)
//
// 	mat.texture_h = Texture_Handle {
// 		index      = max(u32),
// 		generation = 0,
// 	}
// 	mat.color = {1, 1, 1, 1}
// 	material.data = mat
// 	material.type = typeid_of(^Base_Material)
//
// 	material.apply = _material_apply
// 	material.dirty = true
// }
//
// material_set_color :: proc(material: ^Material, color: color, loc := #caller_location) {
// 	assert_not_nil(material, loc)
// 	assert(material.type == typeid_of(^Base_Material))
// 	mat := cast(^Base_Material)material.data
//
// 	mat.color = color
// 	material.dirty = true
// }
//
// material_set_texture :: proc(material: ^Material, texture_h: Texture_Handle, loc := #caller_location) {
// 	assert_not_nil(material, loc)
// 	assert(material.type == typeid_of(^Base_Material))
// 	mat := cast(^Base_Material)material.data
//
// 	mat.texture_h = texture_h
// 	material.dirty = true
// }
//
mtrl_set_pipeline :: proc(material: ^Material, pipeline_h: Pipeline_Handle, loc := #caller_location) {
	assert_not_nil(material, loc)
	material.pipeline_h = pipeline_h
}

// @(private)
// _material_apply :: proc(material: ^Material, loc := #caller_location) {
// 	// assert_gfx_ctx(loc)
// 	// assert_not_nil(material, loc)
// 	assert(material.type == typeid_of(^Base_Material))
// 	mat := cast(^Base_Material)material.data
//
// 	if !material.dirty {
// 		return
// 	}
//
// 	texture_index: u32 = 0
// 	if bindless_has_texture(mat.texture_h) {
// 		texture_index = mat.texture_h.index
// 	} else {
// 		texture_index = max(u32)
// 	}
//
// 	ubo := Base_Material_UBO {
// 		color   = mat.color,
// 		texture = texture_index,
// 	}
// 	buffer := bindless_get_buffer(material.buffer_h) // loc
// 	fill_buffer(buffer, size_of(Base_Material_UBO), &ubo)
// 	material.dirty = false
// }
//
destroy_mtrl :: proc(material: ^Material, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(material, loc)
	free(material.data)

	bindless_destroy_buffer(material.buffer_h, loc)
}
