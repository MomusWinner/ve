package main

import "base:runtime"
import "core:log"
import "core:math"
import "core:math/linalg/glsl"
import "core:math/rand"
import "eldr"
import gfx "eldr/graphics"
import vk "vendor:vulkan"

Scene :: struct {
	data:    rawptr,
	init:    proc(s: ^Scene),
	update:  proc(s: ^Scene, dt: f64),
	draw:    proc(s: ^Scene),
	destroy: proc(s: ^Scene),
}
