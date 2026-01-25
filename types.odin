package ve

import "common"
import gfx "graphics"
import "vendor:glfw"

vec2 :: common.vec2
vec3 :: common.vec3
vec4 :: common.vec4
ivec2 :: common.ivec2
ivec3 :: common.ivec3
ivec4 :: common.ivec4
mat4 :: common.mat4
color :: common.color
Vertex :: common.Vertex
Image :: common.Image

game_event_proc :: proc(user_data: rawptr)

Game_Time :: struct {
	total_game_time:         f64,
	delta_time:              f32,
	target_time:             f32,
	fixed_target_time:       f32,
	previous_frame:          f64,
	fixed_update_total_time: f64,
}

Ve :: struct {
	window:            glfw.WindowHandle,
	should_close:      bool,
	game_time:         Game_Time,
	user_data:         rawptr,
	fixed_update_proc: game_event_proc,
	update_proc:       game_event_proc,
	draw_proc:         game_event_proc,
	destroy_proc:      game_event_proc,
}

Ve_Info :: struct {
	gfx:    gfx.Graphics_Init_Info,
	window: struct {
		title:  string,
		width:  i32,
		height: i32,
	},
}
