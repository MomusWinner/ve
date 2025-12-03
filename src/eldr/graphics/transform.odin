package graphics

import "../common"
import "core:math/linalg/glsl"
import vk "vendor:vulkan"

init_gfx_trf :: proc(trf: ^Gfx_Transform, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(trf, loc)

	buffer := create_uniform_buffer(size_of(Transform_UBO))
	common.init_trf(trf, loc)
	trf.buffer_h = bindless_store_buffer(buffer)
}

@(private)
_trf_apply :: proc(trf: ^Gfx_Transform, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(trf, loc)

	if !trf.dirty {
		return
	}

	model := common.trf_get_matrix(trf)
	trf.dirty = false

	buffer := bindless_get_buffer(trf.buffer_h)

	transform_ubo := Transform_UBO {
		model = model,
	}

	_fill_buffer(buffer, size_of(Transform_UBO), &transform_ubo)
}

destroy_trf :: proc(transform: ^Gfx_Transform, loc := #caller_location) {
	assert_not_nil(transform, loc)
	bindless_destroy_buffer(transform.buffer_h)
}
