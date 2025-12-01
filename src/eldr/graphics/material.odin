package graphics

import "core:math/linalg/glsl"

init_material :: proc(g: ^Graphics, material: ^Material, pipeline_h: Pipeline_Handle, loc := #caller_location) {
	assert_not_nil(g, loc)
	assert_not_nil(material, loc)

	buffer := create_uniform_buffer(g.vulkan_state, size_of(Material_UBO))
	material.buffer_h = bindless_store_buffer(g, buffer)
	material.pipeline_h = pipeline_h
	material.color = {1, 1, 1, 1}
	material.dirty = true
}

material_set_color :: proc(material: ^Material, color: color, loc := #caller_location) {
	assert_not_nil(material, loc)

	material.color = color
	material.dirty = true
}

material_set_texture :: proc(material: ^Material, texture_h: Texture_Handle, loc := #caller_location) {
	assert_not_nil(material, loc)

	material.texture_h = texture_h
	material.dirty = true
}

material_set_pipeline :: proc(material: ^Material, pipeline_h: Pipeline_Handle, loc := #caller_location) {
	assert_not_nil(material, loc)

	material.pipeline_h = pipeline_h
	material.dirty = true
}

@(private)
_material_apply :: proc(material: ^Material, g: ^Graphics, loc := #caller_location) {
	assert_not_nil(g, loc)
	assert_not_nil(material, loc)

	if !material.dirty {
		return
	}

	texture_index: u32 = 0
	if texture, has := material.texture_h.?; has {
		texture_index = texture.index
	}

	ubo := Material_UBO {
		color   = material.color,
		texture = texture_index,
	}
	buffer := bindless_get_buffer(g, material.buffer_h)
	_fill_buffer(buffer, g.vulkan_state, size_of(Material_UBO), &ubo)
	material.dirty = false
}

destroy_material :: proc(g: ^Graphics, material: ^Material, loc := #caller_location) {
	assert_not_nil(g, loc)
	assert_not_nil(material, loc)

	bindless_destroy_buffer(g, material.buffer_h)
}
