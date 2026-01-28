package ve

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "vendor:glfw"

Key :: enum {
	Space        = 32,
	Apostrophe   = 39, /* ' */
	Comma        = 44, /* , */
	Minus        = 45, /* - */
	Period       = 46, /* . */
	Slash        = 47, /* / */
	Semicolon    = 59, /* ; */
	Equal        = 61, /* :: */
	LeftBracket  = 91, /* [ */
	Backslash    = 92, /* \ */
	RightBracket = 93, /* ] */
	GraveAccent  = 96, /* ` */
	World_1      = 161, /* non-US #1 */
	World_2      = 162, /* non-US #2 */

	/* Alphanumeric characters */
	N_0          = 48,
	N_1          = 49,
	N_2          = 50,
	N_3          = 51,
	N_4          = 52,
	N_5          = 53,
	N_6          = 54,
	N_7          = 55,
	N_8          = 56,
	N_9          = 57,
	A            = 65,
	B            = 66,
	C            = 67,
	D            = 68,
	E            = 69,
	F            = 70,
	G            = 71,
	H            = 72,
	I            = 73,
	J            = 74,
	K            = 75,
	L            = 76,
	M            = 77,
	N            = 78,
	O            = 79,
	P            = 80,
	Q            = 81,
	R            = 82,
	S            = 83,
	T            = 84,
	U            = 85,
	V            = 86,
	W            = 87,
	X            = 88,
	Y            = 89,
	Z            = 90,

	/** Function keys **/
	/* Named non-printable keys */
	Escape       = 256,
	Enter        = 257,
	Tab          = 258,
	Backspace    = 259,
	Insert       = 260,
	Delete       = 261,
	Right        = 262,
	Left         = 263,
	Down         = 264,
	Up           = 265,
	PageUp       = 266,
	PageDown     = 267,
	Home         = 268,
	End          = 269,
	CapsLock     = 280,
	ScrollLock   = 281,
	Num_lock     = 282,
	PrintScreen  = 283,
	Pause        = 284,

	/* Function keys */
	F1           = 290,
	F2           = 291,
	F3           = 292,
	F4           = 293,
	F5           = 294,
	F6           = 295,
	F7           = 296,
	F8           = 297,
	F9           = 298,
	F10          = 299,
	F11          = 300,
	F12          = 301,
	F13          = 302,
	F14          = 303,
	F15          = 304,
	F16          = 305,
	F17          = 306,
	F18          = 307,
	F19          = 308,
	F20          = 309,
	F21          = 310,
	F22          = 311,
	F23          = 312,
	F24          = 313,
	F25          = 314,

	/* Keypad numbers */
	KP_0         = 320,
	KP_1         = 321,
	KP_2         = 322,
	KP_3         = 323,
	KP_4         = 324,
	KP_5         = 325,
	KP_6         = 326,
	KP_7         = 327,
	KP_8         = 328,
	KP_9         = 329,

	/* Keypad named function keys */
	KP_Decimal   = 330,
	KP_Divide    = 331,
	KP_Multiply  = 332,
	KP_Subtract  = 333,
	KP_Add       = 334,
	KP_Enter     = 335,
	KP_Equal     = 336,

	/* Modifier keys */
	LeftShift    = 340,
	LeftControl  = 341,
	LeftAlt      = 342,
	LeftSuper    = 343,
	RightShift   = 344,
	RightControl = 345,
	RightAlt     = 346,
	RightSuper   = 347,
	Menu         = 348,
}

KEYBOARD_MAX_KEY :: glfw.KEY_LAST

MouseButton :: enum {
	Left     = 0,
	Right    = 1,
	Middle   = 2,
	Button_4 = 3,
	Button_5 = 4,
	Button_6 = 5,
	Button_7 = 6,
	Button_8 = 7,
}

@(private = "file")
input: struct {
	window:   ^glfw.WindowHandle,
	keyboard: struct {
		states:          [KEYBOARD_MAX_KEY]i32,
		previous_states: [KEYBOARD_MAX_KEY]i32,
	},
	mouse:    struct {
		states:             [glfw.MOUSE_BUTTON_LAST]i32,
		previous_states:    [glfw.MOUSE_BUTTON_LAST]i32,
		position:           vec2,
		previouse_position: vec2,
		scroll:             vec2,
	},
}

is_key_pressed :: proc(key: Key) -> bool {
	return input.keyboard.states[key] == glfw.PRESS && input.keyboard.previous_states[key] == glfw.RELEASE
}

is_key_released :: proc(key: Key) -> bool {
	return input.keyboard.states[key] == glfw.RELEASE && input.keyboard.previous_states[key] == glfw.PRESS
}

is_key_down :: proc(key: Key) -> bool {
	return input.keyboard.states[key] == glfw.PRESS
}

is_key_up :: proc(key: Key) -> bool {
	return input.keyboard.states[key] == glfw.RELEASE
}

get_mouse_position :: proc() -> vec2 {
	return input.mouse.position
}

get_mouse_delta :: proc() -> vec2 {
	return input.mouse.position - input.mouse.previouse_position
}

is_mouse_button_pressed :: proc(button: MouseButton) -> bool {
	return input.mouse.states[button] == glfw.PRESS && input.mouse.previous_states[button] == glfw.RELEASE
}

is_mouse_button_released :: proc(button: MouseButton) -> bool {
	return input.mouse.states[button] == glfw.RELEASE && input.mouse.previous_states[button] == glfw.PRESS
}

is_mouse_button_down :: proc(button: MouseButton) -> bool {
	return input.mouse.states[button] == glfw.PRESS
}

is_mouse_button_up :: proc(button: MouseButton) -> bool {
	return input.mouse.states[button] == glfw.RELEASE
}

cursor_disable :: proc() {
	glfw.SetInputMode(ctx.window, glfw.CURSOR, glfw.CURSOR_DISABLED)
}

cursor_enable :: proc() {
	glfw.SetInputMode(ctx.window, glfw.CURSOR, glfw.CURSOR_NORMAL)
}

get_scroll_vec2 :: proc() -> vec2 {
	return input.mouse.scroll
}

get_scroll_f32 :: proc() -> f32 {
	return(
		input.mouse.scroll.x if math.abs(input.mouse.scroll.x) > math.abs(input.mouse.scroll.y) else input.mouse.scroll.y \
	)
}

@(private)
_init_input :: proc(window: ^glfw.WindowHandle) {
	input.window = window
	glfw.SetScrollCallback(window^, _scroll_callback)
}

@(private)
_update_input :: proc() {
	input.mouse.scroll = 0
	glfw.PollEvents()

	// Keyboard
	input.keyboard.previous_states = input.keyboard.states
	for key in glfw.KEY_SPACE ..< KEYBOARD_MAX_KEY {
		state := glfw.GetKey(input.window^, cast(i32)key)

		input.keyboard.states[key] = state
	}

	// Mouse
	input.mouse.previous_states = input.mouse.states
	for key in glfw.MOUSE_BUTTON_1 ..< glfw.MOUSE_BUTTON_LAST {
		input.mouse.states[key] = glfw.GetMouseButton(input.window^, cast(i32)key)
	}

	input.mouse.previouse_position = input.mouse.position
	mouse_pos_x, mouse_pos_y := glfw.GetCursorPos(input.window^)
	input.mouse.position = {cast(f32)mouse_pos_x, cast(f32)mouse_pos_y}
}

_scroll_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	input.mouse.scroll = vec2{cast(f32)xoffset, cast(f32)yoffset}
}
