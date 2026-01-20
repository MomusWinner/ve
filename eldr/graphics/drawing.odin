package graphics

draw_on_unit_square :: proc(
	frame_data: Frame_Data,
	trf: ^Gfx_Transform,
	camera: ^Camera,
	material: ^Material,
	loc := #caller_location,
) {
	assert_gfx_ctx(loc)

	draw_mesh(frame_data, &ctx.buildin.unit_square, material, camera, trf, loc)
}
