package graphics

import hm "../handle_map"
import "core:math/linalg/glsl"

material_init :: proc(material: ^Material, g: ^Graphics, pipeline_h: Pipeline_Handle) {
	buffer := create_uniform_buffer(g, size_of(Material_UBO))
	material.buffer_h = bindless_store_buffer(g, buffer)
	material.pipeline_h = pipeline_h
	material.color = {1, 1, 1, 1}
}

material_update :: proc(material: ^Material, g: ^Graphics) {
	ubo := Material_UBO {
		texture = material.texture_h.index,
		color   = material.color,
	}
	buffer := bindless_get_buffer(g, material.buffer_h)
	_fill_buffer(g, buffer, size_of(Material_UBO), &ubo)
}

Transform :: struct {
	buffer_h: Buffer_Handle,
	model:    mat4,
	position: vec3,
	rotation: vec3,
	scale:    vec3,
	dirty:    bool,
}

transform_init :: proc(transform: ^Transform, g: ^Graphics) {
	buffer := create_uniform_buffer(g, size_of(Model_UBO))
	transform.buffer_h = bindless_store_buffer(g, buffer)
}

transform_set_position :: proc(transform: ^Transform, position: vec3) {
	transform.position = position
	transform.dirty = true
}

transform_apply :: proc(transform: ^Transform, g: ^Graphics) {
	if !transform.dirty {
		return
	}

	transform.model = glsl.mat4Translate(transform.position) * glsl.mat4Scale(transform.scale)
	transform.dirty = false

	buffer := bindless_get_buffer(g, transform.buffer_h)
	model_ubo := Model_UBO {
		model   = transform.model,
		tangens = 0,
	}

	_fill_buffer(g, buffer, size_of(Model_UBO), &model_ubo)
}
