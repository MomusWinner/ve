package graphics

import "core:log"
import "core:math/linalg/glsl"
import "core:math/linalg/hlsl"
import vk "vendor:vulkan"

@(private)
DEFAULT_FOV :: 45
@(private)
DEFAULT_NEAR :: 0.01
@(private)
DEFAULT_FAR :: 100

camera_init :: proc(camera: ^Camera, type: Camera_Type = .Perspective, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(camera, loc)

	camera.fov = DEFAULT_FOV
	camera.near = DEFAULT_NEAR
	camera.far = DEFAULT_FAR
	camera.zoom = vec3{1, 1, 1}
	camera.type = type
	camera.dirty = true

	buffer := create_uniform_buffer(size_of(Camera_UBO))
	camera._buffer_h = store_buffer(buffer, loc)
}

camera_get_forward :: proc(camera: ^Camera, loc := #caller_location) -> vec3 {
	assert_not_nil(camera, loc)

	return glsl.normalize_vec3(camera.target - camera.position)
}

camera_get_right :: proc(camera: ^Camera, loc := #caller_location) -> vec3 {
	assert_not_nil(camera, loc)

	return glsl.normalize(glsl.cross(camera_get_forward(camera), camera.up))
}

camera_get_left :: proc(camera: ^Camera, loc := #caller_location) -> vec3 {
	assert_not_nil(camera, loc)

	return -camera_get_right(camera)
}

camera_set_yaw :: proc(camera: ^Camera, angle: f32, loc := #caller_location) {
	assert_not_nil(camera, loc)

	target_position := camera.target - camera.position
	trans := glsl.mat4Rotate(camera.up, glsl.radians(angle))
	target := trans * vec4{target_position.x, target_position.y, target_position.z, 0}
	camera.target = target.xyz

	camera.dirty = true
}

camera_set_pitch :: proc(camera: ^Camera, angle: f32, loc := #caller_location) {
	assert_not_nil(camera, loc)

	target_position := camera.target - camera.position
	trans := glsl.mat4Rotate(camera_get_right(camera), glsl.radians(angle))
	target := trans * vec4{target_position.x, target_position.y, target_position.z, 0}
	camera.target = target.xyz

	camera.dirty = true
}

camera_set_roll :: proc(camera: ^Camera, angle: f32, loc := #caller_location) {
	assert_not_nil(camera, loc)

	target_position := camera.target - camera.position
	trans := glsl.mat4Rotate(camera_get_forward(camera), glsl.radians(angle))
	target := trans * vec4{target_position.x, target_position.y, target_position.z, 0}
	camera.target = target.xyz

	camera.dirty = true
}

camera_set_zoom :: proc(camera: ^Camera, zoom: vec3, loc := #caller_location) {
	assert_not_nil(camera, loc)

	camera.zoom = zoom

	camera.dirty = true
}

camera_get_view :: proc(camera: ^Camera, loc := #caller_location) -> mat4 {
	assert_not_nil(camera, loc)

	return(
		glsl.mat4LookAt(camera.position, camera.position + camera_get_forward(camera), camera.up) *
		glsl.mat4Scale(camera.zoom) \
	)
}

camera_get_projection :: proc(camera: ^Camera, aspect: f32, loc := #caller_location) -> mat4 {
	assert_not_nil(camera, loc)

	projection: mat4

	switch camera.type {
	case .Perspective:
		projection = perspective(glsl.radians_f32(camera.fov), aspect, camera.near, camera.far)

	case .Orthographic:
		top := camera.fov / 2.0
		right := top * aspect
		projection = ortho(-right, right, -top, top, camera.near, camera.far)
	}

	return projection
}

@(private)
_camera_get_buffer :: proc(camera: ^Camera, aspect: f32, loc := #caller_location) -> Buffer_Handle {
	assert_gfx_ctx(loc)
	assert_not_nil(camera, loc)

	if !camera.dirty && aspect == camera.last_aspect {
		return camera._buffer_h
	}

	camera.last_aspect = aspect

	view := camera_get_view(camera)
	projection := camera_get_projection(camera, aspect)

	buffer := get_buffer_h(camera._buffer_h)
	camera_ubo := Camera_UBO {
		view       = view,
		projection = projection,
	}
	fill_buffer(buffer, size_of(Camera_UBO), &camera_ubo)
	camera.dirty = false

	return camera._buffer_h
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
	tan_half_fovy := glsl.tan(0.5 * fovy)
	m[0, 0] = 1 / (aspect * tan_half_fovy)
	m[1, 1] = -1 / (tan_half_fovy)
	m[2, 2] = far / (near - far)
	m[3, 2] = -1
	m[2, 3] = -far * near / (far - near)
	return
}
