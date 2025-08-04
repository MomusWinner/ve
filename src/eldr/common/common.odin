package common

import vk "vendor:vulkan"

vec2 :: [2]f32
vec3 :: [3]f32

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
