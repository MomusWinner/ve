package graphics

import "core:math/linalg/glsl"

mtrl_set_pipeline :: proc(material: ^Material, pipeline_h: Render_Pipeline_Handle, loc := #caller_location) {
	assert_not_nil(material, loc)
	material.pipeline_h = pipeline_h
}

destroy_mtrl :: proc(material: ^Material, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(material, loc)
	free(material.data)

	bindless_destroy_buffer(material.buffer_h, loc)
}
