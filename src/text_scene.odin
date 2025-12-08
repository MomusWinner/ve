package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg/glsl"
import "core:math/rand"
import "core:strings"
import "eldr"
import gfx "eldr/graphics"

Text_Scene_Data :: struct {
	font:        gfx.Font,
	camera:      gfx.Camera,
	text:        gfx.Text,
	builder:     strings.Builder,
	color_value: f32,
}

create_text_scene :: proc() -> Scene {
	return Scene {
		init = text_scene_init,
		update = text_scene_update,
		draw = text_scene_draw,
		destroy = text_scene_destroy,
	}
}

text_scene_init :: proc(s: ^Scene) {
	data := new(Text_Scene_Data)

	gfx.camera_init(&data.camera)
	data.camera.position = {0, 0, 2}
	data.camera.target = {0, 0, 0}
	data.camera.up = {0, 1, 0}
	data.camera.dirty = true

	data.font = gfx.load_font(
		gfx.Create_Font_Info {
			path = "assets/buildin/fonts/RobotoMono.ttf",
			size = 128,
			padding = 2,
			atlas_width = 2024,
			atlas_height = 1024,
			regions = {{start = 32, size = 128}, {start = 1024, size = 255}},
			default_char = '?',
		},
	)

	data.text = gfx.create_text(
		&data.font,
		"По берегу мы шли. Кипел поток,\nГде выли тени злы, полубиты,\nПоверженны в кровавый кипяток.",
		vec3{-0.5, 0, 0},
		vec4{0, 0.5, 0, 1},
		0.5,
	)

	strings.builder_init_len(&data.builder, len(data.text.text))
	strings.write_string(&data.builder, data.text.text)

	s.data = data
}

@(private = "file")
elapsed_time: f64
@(private = "file")
time_delta: f64 = 2

text_scene_update :: proc(s: ^Scene) {
	data := cast(^Text_Scene_Data)s.data
	value += eldr.get_delta_time() * 5
	result := (math.sin_f32(value) + 1) / 2
	gfx.text_set_color(&data.text, eldr.color{1, result, 1, 1})


	elapsed_time += cast(f64)eldr.get_delta_time()
	if elapsed_time > time_delta {
		elapsed_time = 0
		strings.write_string(&data.builder, "\n... ")
		str := strings.to_string(data.builder)
		gfx.text_set_string(&data.text, str)
	}
}

text_scene_draw :: proc(s: ^Scene) {
	data := cast(^Text_Scene_Data)s.data

	frame := gfx.begin_render()

	// Begin gfx.
	// --------------------------------------------------------------------------------------------------------------------

	gfx.set_full_viewport_scissor(frame)

	base_frame := gfx.begin_draw(frame)

	gfx.draw_text(&data.text, base_frame, &data.camera)

	gfx.end_draw(frame)

	// --------------------------------------------------------------------------------------------------------------------
	// End gfx.
	gfx.end_render(frame)
}

text_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Text_Scene_Data)s.data

	strings.builder_destroy(&data.builder)
	gfx.destroy_text(&data.text)
	gfx.unload_font(&data.font)

	free(data)
}
