package eldr

import "core:log"
import "vendor:glfw"

get_target_fps :: proc() -> f32 {
	return 1 / ctx.game_time.delta_time
}

set_target_fps :: proc(fps: int) {
	ctx.game_time.target_time = 1 / cast(f32)fps
}

get_target_fixed_fps :: proc() -> f32 {
	return 1 / ctx.game_time.fixed_target_time
}

set_target_fixed_fps :: proc(fps: int) {
	ctx.game_time.fixed_target_time = 1 / cast(f32)fps
}

get_delta_time :: proc() -> f32 {
	return ctx.game_time.delta_time
}

get_fixed_delta_time :: proc() -> f32 {
	return ctx.game_time.fixed_target_time
}

get_total_game_time :: proc() -> f64 {
	return ctx.game_time.total_game_time
}

@(private)
_window_should_close :: proc() -> b32 {
	return glfw.WindowShouldClose(ctx.window)
}
