package common

import "core:math/linalg/glsl"

Transform :: struct {
	position: vec3,
	rotation: quat,
	scale:    vec3,
	dirty:    bool,
}

init_trf :: proc(trf: ^Transform, loc := #caller_location) {
	assert_not_nil(trf, loc)

	trf.scale = 1
	trf.position = 0
	trf.dirty = true
}

trf_set_position :: proc(trf: ^Transform, position: vec3, loc := #caller_location) {
	assert_not_nil(trf, loc)

	trf.position = position
	trf.dirty = true
}

trf_set_scale :: proc(trf: ^Transform, scale: vec3, loc := #caller_location) {
	assert_not_nil(trf, loc)

	trf.scale = scale
	trf.dirty = true
}


trf_set_rotation :: proc(trf: ^Transform, rotation: quat, loc := #caller_location) {
	assert_not_nil(trf, loc)

	trf.rotation = rotation
	trf.dirty = true
}

trf_rotate :: proc(trf: ^Transform, axis: vec3, radians: f32, loc := #caller_location) {
	assert_not_nil(trf, loc)

	trf.rotation = glsl.quatAxisAngle(axis, radians)
	trf.dirty = true
}

trf_get_forward :: proc(trf: Transform) -> vec3 {
	return glsl.quatMulVec3(trf.rotation, {0, 0, 1})
}

trf_get_up :: proc(trf: Transform) -> vec3 {
	return glsl.quatMulVec3(trf.rotation, {0, 1, 0})
}

trf_get_right :: proc(trf: Transform) -> vec3 {
	return glsl.quatMulVec3(trf.rotation, {1, 0, 0})
}

trf_get_matrix :: proc(trf: Transform) -> mat4 {
	return glsl.mat4Translate(trf.position) * glsl.mat4Scale(trf.scale) * glsl.mat4FromQuat(trf.rotation)
}
