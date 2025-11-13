package eldr

import "core:c"
import "core:log"
import "core:strings"
import "core:time"
import gfx "graphics"
import imp "importer"
import "vendor:glfw"
import stb_image "vendor:stb/image"
import vk "vendor:vulkan"

game_event_proc :: proc(user_data: rawptr)

Game_Time :: struct {
	total_game_time:         f64,
	delta_time:              f32,
	target_time:             f32,
	fixed_target_time:       f32,
	previous_frame:          f64,
	fixed_update_total_time: f64,
}

Eldr :: struct {
	window:            glfw.WindowHandle,
	gfx:               ^gfx.Graphics,
	game_time:         Game_Time,
	user_data:         rawptr,
	fixed_update_proc: game_event_proc,
	update_proc:       game_event_proc,
	draw_proc:         game_event_proc,
	destroy_proc:      game_event_proc,
}

Eldr_Info :: struct {
	gfx:    Graphics_Init_Info,
	window: struct {
		title:  string,
		width:  i32,
		height: i32,
	},
}

// @(private)  TODO: make private
ctx: Eldr

init :: proc(
	user_data: rawptr,
	fixed_update_proc: game_event_proc,
	update_proc: game_event_proc,
	draw_proc: game_event_proc,
	destroy_proc: game_event_proc,
	info: Eldr_Info,
	loc := #caller_location,
) {
	ctx.user_data = user_data
	ctx.fixed_update_proc = fixed_update_proc
	ctx.update_proc = update_proc
	ctx.draw_proc = draw_proc
	ctx.destroy_proc = destroy_proc

	// TODO: update vendor bindings to glfw 3.4 and use this to set a custom allocator.
	// glfw.InitAllocator()

	if !glfw.Init() {
		log.panic("glfw: could not be initialized")
	} else {
		log.info("glfw: initialized")
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)

	window := glfw.CreateWindow(
		info.window.width,
		info.window.height,
		strings.clone_to_cstring(info.window.title, context.temp_allocator),
		nil,
		nil,
	)
	assert(window != nil, "Couldn't create window. Please check window settings", loc)


	ctx.window = window
	ctx.game_time.target_time = 1.0 / 60.0
	ctx.game_time.fixed_target_time = 1.0 / 38.0

	_init_graphic(window, info.gfx)
}

fixed_frame_count: u64

run :: proc() {
	for (!_window_should_close()) {
		start := glfw.GetTime()

		ctx.game_time.delta_time = cast(f32)(start - ctx.game_time.previous_frame)
		if ctx.game_time.delta_time < 0 {
			ctx.game_time.delta_time = 0
		}
		ctx.game_time.previous_frame = start

		ctx.game_time.total_game_time += cast(f64)ctx.game_time.delta_time

		free_all(context.temp_allocator)

		fixed_update_dept_time := ctx.game_time.total_game_time - ctx.game_time.fixed_update_total_time
		fixed_update_dept_count := cast(int)(fixed_update_dept_time / cast(f64)ctx.game_time.fixed_target_time)

		if fixed_update_dept_count > 0 {
			for i in 0 ..< fixed_update_dept_count {
				fixed_frame_count += 1
				ctx.fixed_update_proc(ctx.user_data)
				ctx.game_time.fixed_update_total_time += cast(f64)ctx.game_time.fixed_target_time
			}
		}

		ctx.update_proc(ctx.user_data)
		ctx.draw_proc(ctx.user_data)

		end := glfw.GetTime()

		frame_duration := cast(f32)(end - start)

		if frame_duration < ctx.game_time.target_time {
			wait_time: f32 = ctx.game_time.target_time - frame_duration
			wait_duration := cast(time.Duration)(wait_time * 1e9) * time.Nanosecond
			time.accurate_sleep(wait_duration)
		}
	}

	gfx.wait_render_completion(ctx.gfx)

	ctx.destroy_proc(ctx.user_data)

	_destroy()
}

@(private)
_destroy :: proc() {
	gfx.destroy_graphic(ctx.gfx)
	glfw.DestroyWindow(ctx.window)
	glfw.Terminate()
}

load_image :: proc(path: string, desired_channels: i32 = 0) -> (image: Image, ok: bool) {
	stb_image.set_flip_vertically_on_load(1)
	width, height, channels: i32

	cpath, alloc_err := strings.clone_to_cstring(path, context.temp_allocator)
	assert(alloc_err == .None, "couldn't allocate memory for cstring")

	data := stb_image.load(cpath, &width, &height, &channels, desired_channels)

	if channels == 0 {
		return {}, false
	}

	image.width = cast(u32)width
	image.height = cast(u32)height
	image.channels = desired_channels == 0 ? cast(u32)channels : cast(u32)desired_channels

	switch image.channels {
	case 1:
		image.pixel = .R8
	case 2:
		image.pixel = .RG8
	case 3:
		image.pixel = .RGB8
	case 4:
		image.pixel = .RGBA8
	}

	image.data = data
	ok = true

	return
}

unload_image :: proc(image: Image) {
	defer stb_image.image_free(image.data)
}
