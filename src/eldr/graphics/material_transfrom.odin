package graphics

import hm "../handle_map"
import "core:log"
import "core:math/linalg/glsl"

init_material :: proc(g: ^Graphics, material: ^Material, pipeline_h: Pipeline_Handle) {
	buffer := create_uniform_buffer(g, size_of(Material_UBO))
	material.buffer_h = bindless_store_buffer(g, buffer)
	material.pipeline_h = pipeline_h
	material.color = {1, 1, 1, 1}
	material.dirty = true
}

material_set_color :: proc(material: ^Material, color: color) {
	material.color = color
	material.dirty = true
}

material_set_texture :: proc(material: ^Material, texture_h: Texture_Handle) {
	material.texture_h = texture_h
	material.dirty = true
}

@(private)
_material_apply :: proc(material: ^Material, g: ^Graphics) {
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
	_fill_buffer(g, buffer, size_of(Material_UBO), &ubo)
	material.dirty = false
}

destroy_material :: proc(g: ^Graphics, material: ^Material) {
	bindless_destroy_buffer(g, material.buffer_h)
}

init_transform :: proc(g: ^Graphics, transform: ^Transform) {
	buffer := create_uniform_buffer(g, size_of(Transform_UBO))
	transform.scale = 1
	transform.rotation = 0
	transform.position = 0
	transform.dirty = true
	transform.buffer_h = bindless_store_buffer(g, buffer)
}

transform_set_position :: proc(transform: ^Transform, position: vec3) {
	transform.position = position
	transform.dirty = true
}

transform_set_scale :: proc(transform: ^Transform, scale: vec3) {
	transform.scale = scale
	transform.dirty = true
}

@(private)
_transform_apply :: proc(transform: ^Transform, g: ^Graphics) {
	if !transform.dirty {
		return
	}

	transform.model = glsl.mat4Translate(transform.position) * glsl.mat4Scale(transform.scale)
	transform.dirty = false

	buffer := bindless_get_buffer(g, transform.buffer_h)
	transform_ubo := Transform_UBO {
		model   = transform.model,
		tangens = 0,
	}

	_fill_buffer(g, buffer, size_of(Transform_UBO), &transform_ubo)
}

transform_destroy :: proc(transform: ^Transform, g: ^Graphics) {
	bindless_destroy_buffer(g, transform.buffer_h)
}
