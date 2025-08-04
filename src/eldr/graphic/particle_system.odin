package graphic

import vk "vendor:vulkan"

import "core:math/linalg/glsl"

// PARTICLE_COUNT :: 256
//
// Particle :: struct {
// 	position: glsl.vec2,
// 	velocity: glsl.vec2,
// 	color:    glsl.vec4,
// }
//
// create_sbo :: proc(g: ^Graphic) {
// 	size := cast(vk.DeviceSize)(size_of(Particle) * PARTICLE_COUNT)
// 	sbo := create_buffer(g, size, {.STORAGE_BUFFER, .VERTEX_BUFFER, .TRANSFER_DST}, {.DEVICE_LOCAL})
// }
//
