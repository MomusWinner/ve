package vemath

import lin "core:math/linalg/glsl"

vec2 :: lin.vec2
ivec2 :: lin.ivec2
dvec2 :: lin.dvec2

vec3 :: lin.vec3
ivec3 :: lin.ivec3
dvec3 :: lin.dvec3

vec4 :: lin.vec4
ivec4 :: lin.ivec4
dvec4 :: lin.dvec4

color :: lin.vec4

mat2 :: lin.mat2
mat3 :: lin.mat3
mat4 :: lin.mat4

quat :: lin.quat

// Returns the signed angle between two 2D vectors in radians [-π, π].
vec2_angle :: proc(v1: vec2, v2: vec2) -> f32 {
	det := v1.x * v2.y - v1.y * v2.x
	return lin.atan2(det, lin.dot(v1, v2))
}

// Returns the angle between two 3D vectors in radians [0, π].
vec3_angle :: proc(v1: vec3, v2: vec3) -> f32 {
	return lin.acos(lin.dot(v1, v2) / lin.length_vec3(v1) * lin.length_vec3(v2))
}

// Right hand and zero to one
@(require_results)
ortho :: proc(left, right, bottom, top, near, far: f32) -> (m: mat4) {
	m[0, 0] = 2 / (right - left)
	m[1, 1] = -2 / (top - bottom)
	m[2, 2] = -1 / (far - near)
	m[0, 3] = -(right + left) / (right - left)
	m[1, 3] = -(top + bottom) / (top - bottom)
	m[2, 3] = -near / (far - near)
	m[3, 3] = 1
	return m
}

// Right hand and zero to one
@(require_results)
perspective :: proc "c" (fovy, aspect, near, far: f32) -> (m: mat4) {
	tan_half_fovy := lin.tan(0.5 * fovy)
	m[0, 0] = 1 / (aspect * tan_half_fovy)
	m[1, 1] = -1 / (tan_half_fovy)
	m[2, 2] = far / (near - far)
	m[3, 2] = -1
	m[2, 3] = -far * near / (far - near)
	return
}

// length_sqr 
