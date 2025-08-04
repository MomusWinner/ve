package input

import "vendor:glfw"
import "vendor:sdl3"

Input :: struct {
	window: glfw.WindowHandle,
}

handler :: proc "c" (window: WindowHandle, key, scancode, action, mods: c.int) {
	if key == glfw.KEY_ESC {
	}
}

new :: proc(window: glfw.WindowHandle) -> Input {
	glfw.SetKeyCallback(window, handler)
	return Input{window = window}
}
