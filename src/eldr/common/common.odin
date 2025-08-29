package common

import "core:math/linalg/glsl"
import vk "vendor:vulkan"

vec2 :: glsl.vec2
vec3 :: glsl.vec3
vec4 :: glsl.vec4
mat4 :: glsl.mat4

Vertex :: struct {
	position:  vec3,
	tex_coord: vec2,
	normal:    vec3,
}

Image :: struct {
	width:    u32,
	height:   u32,
	channels: u32,
	data:     [^]byte,
}
