package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg/glsl"
import "core:math/rand"
import "eldr"
import "vendor:glfw"
import vk "vendor:vulkan"

Text_Scene_Data :: struct {
	font:        eldr.Font,
	camera:      eldr.Camera,
	text:        eldr.Text,
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

	eldr.camera_init(&data.camera, cast(f32)eldr.get_screen_width(), cast(f32)eldr.get_screen_height())
	data.camera.position = {0, 0, 2}
	data.camera.target = {0, 0, 0}
	data.camera.up = {0, 1, 0}
	data.camera.dirty = true
	eldr.camera_apply(&data.camera)

	data.font = eldr.load_font(
		eldr.Create_Font_Info {
			path = "assets/fonts/RobotoMono.ttf",
			size = 128,
			padding = 2,
			atlas_width = 2024,
			atlas_height = 1024,
			regions = {{start = 32, size = 128}, {start = 1024, size = 255}},
			default_char = '?',
		},
	)

	data.text = eldr.create_text(
		&data.font,
		"По берегу мы шли. Кипел поток,\nГде выли тени злы, полубиты,\nПоверженны в кровавый кипяток.",
		vec3{-0.5, 0, 0},
		0.5,
		eldr.vec4{0, 0.5, 0, 1},
	)
	s.data = data
}

@(private = "file")
elapsed_time: f64
@(private = "file")
time_delta: f64 = 2

text_scene_update :: proc(s: ^Scene, dt: f64) {
	data := cast(^Text_Scene_Data)s.data
	value += cast(f32)dt * 5
	result := (math.sin_f32(value) + 1) / 2
	eldr.text_set_color(&data.text, eldr.color{1, result, 1, 1})


	elapsed_time += dt
	if elapsed_time > time_delta {
		elapsed_time = 0
		eldr.text_set_string(&data.text, fmt.aprintf("%s\n... ", data.text.text))
	}
}

text_scene_draw :: proc(s: ^Scene) {
	data := cast(^Text_Scene_Data)s.data

	frame := eldr.begin_render()

	if eldr.screen_resized() {
		eldr.camera_set_aspect(&data.camera, cast(f32)eldr.get_screen_width(), cast(f32)eldr.get_screen_height())
		eldr.camera_apply(&data.camera)
	}
	// Begin gfx.
	// --------------------------------------------------------------------------------------------------------------------

	eldr.cmd_set_full_viewport(frame.cmd)

	eldr.begin_draw(frame)

	eldr.draw_text(&data.text, frame, data.camera)

	eldr.end_draw(frame)

	// --------------------------------------------------------------------------------------------------------------------
	// End gfx.
	eldr.end_render(frame)
}

text_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Text_Scene_Data)s.data

	eldr.destroy_text(&data.text)
	eldr.unload_font(&data.font)

	free(data)
}
