package ve

import "core:log"
import lin "core:math/linalg/glsl"
import vemath "math"
import vk "vendor:vulkan"

@(private)
DEFAULT_FOV :: 45
@(private)
DEFAULT_NEAR :: 0.01
@(private)
DEFAULT_FAR :: 100

Camera_UBO :: struct {
	view:       mat4,
	projection: mat4,
	position:   vec3,
	_pad0:      f32,
	target:     vec3,
	_pad1:      f32,
}

Camera_Projection_Type :: enum {
	Perspective,
	Orthographic,
}

Camera :: struct {
	type:     Camera_Projection_Type,
	position: vec3,
	zoom:     vec3,
	target:   vec3,
	up:       vec3,
	fov:      f32,
	near:     f32,
	far:      f32,
	buffer:   Buffer, // Camera_UBO
}

set_camera_ex :: proc(camera: Camera, aspect: f32) {
	ctx.gfx.frame.camera = camera_get_buffer(camera, aspect)
}

set_camera :: proc(camera: Camera) {
	aspect := cast(f32)screen_get_width() / cast(f32)screen_get_height()
	ctx.gfx.frame.camera = camera_get_buffer(camera, aspect)
}

// Use the buffer filled by the Camera_UBO data for rendering
set_camera_buffer :: proc(buffer: Buffer) {
	ctx.gfx.frame.camera = buffer
}

init_camera :: proc(camera: ^Camera, type: Camera_Projection_Type = .Perspective, loc := #caller_location) {
	assert_not_nil(camera, loc)

	camera.fov = DEFAULT_FOV
	camera.near = DEFAULT_NEAR
	camera.far = DEFAULT_FAR
	camera.up = {0, 1, 0}
	camera.zoom = 1
	camera.type = type

	buffer := _create_buffer({.Uniform, .Host_Write}, size_of(Camera_UBO))

	camera.buffer = _store_buffer(buffer, loc)
}

destroy_camera :: proc(camera: ^Camera, loc := #caller_location) {
	destroy_buffer(camera.buffer, loc)
}

camera_get_up :: proc(camera: Camera, loc := #caller_location) -> vec3 {
	return lin.normalize_vec3(camera.up)
}

camera_get_forward :: proc(camera: Camera, loc := #caller_location) -> vec3 {
	return lin.normalize_vec3(camera.target - camera.position)
}

camera_get_right :: proc(camera: Camera, loc := #caller_location) -> vec3 {
	return lin.normalize(lin.cross(camera_get_forward(camera), camera_get_up(camera)))
}

camera_get_left :: proc(camera: Camera, loc := #caller_location) -> vec3 {
	return -camera_get_right(camera)
}

camera_move :: proc(camera: ^Camera, translation: vec3) {
	camera.position += translation
	camera.target += translation
}

camera_set_position :: proc(camera: ^Camera, position: vec3, loc := #caller_location) {
	assert_not_nil(camera, loc)

	forward := camera_get_forward(camera^)
	camera.position = position
	camera.target = camera.position + forward
}

camera_set_position_only :: proc(camera: ^Camera, position: vec3) {
	camera.position = position
}

camera_set_target_only :: proc(camera: ^Camera, position: vec3) {
	camera.target = position
}

camera_set_yaw :: proc(camera: ^Camera, angle: f32, loc := #caller_location) {
	camera_rotate(camera, camera_get_up(camera^), angle, loc)
}

// Rotates the camera around its right vector
camera_set_pitch :: proc(camera: ^Camera, angle: f32, loc := #caller_location) {
	camera_rotate(camera, camera_get_right(camera^), angle, loc)
}

camera_set_roll :: proc(camera: ^Camera, angle: f32, loc := #caller_location) {
	camera_rotate(camera, camera_get_forward(camera^), angle, loc)
}

camera_rotate :: proc(camera: ^Camera, axis: vec3, angle: f32, loc := #caller_location) {
	assert_not_nil(camera, loc)

	// Get current direction and distance
	direction := camera.target - camera.position
	distance := lin.length(direction)

	// Normalize direction and rotate around right axis
	normalized_dir := lin.normalize(direction)
	trans := lin.mat4Rotate(axis, angle)
	new_direction := trans * vec4{normalized_dir.x, normalized_dir.y, normalized_dir.z, 0}

	// Apply with original distance
	camera.target = camera.position + new_direction.xyz * distance
}

camera_set_zoom :: proc(camera: ^Camera, zoom: vec3, loc := #caller_location) {
	assert_not_nil(camera, loc)

	camera.zoom = zoom
}

camera_get_view :: proc(camera: Camera, loc := #caller_location) -> mat4 {
	return(
		lin.mat4LookAt(camera.position, camera.position + camera_get_forward(camera), camera_get_up(camera)) *
		lin.mat4Scale(camera.zoom) \
	)
}

camera_get_projection :: proc(camera: Camera, aspect: f32, loc := #caller_location) -> mat4 {
	projection: mat4

	switch camera.type {
	case .Perspective:
		projection = vemath.perspective(lin.radians_f32(camera.fov), aspect, camera.near, camera.far)
	case .Orthographic:
		top := camera.fov / 2.0
		right := top * aspect
		projection = vemath.ortho(-right, right, -top, top, camera.near, camera.far)
	}

	return projection
}

camera_get_buffer :: proc(camera: Camera, aspect: f32, loc := #caller_location) -> Buffer {
	view := camera_get_view(camera)
	projection := camera_get_projection(camera, aspect)

	camera_ubo := Camera_UBO {
		view       = view,
		projection = projection,
		position   = camera.position,
		target     = camera.target,
	}
	buffer_fill(camera.buffer, size_of(Camera_UBO), &camera_ubo)

	return camera.buffer
}

camera_update_simple_controller :: proc(
	camera: ^Camera,
	speed: f32 = 2.0,
	mouse_sens: f32 = 0.0005,
	zoom_speed: f32 = 2.5,
) {
	speed := speed
	speed *= time_get_delta()

	m_delta := mouse_get_delta()
	if lin.length_vec2(m_delta) > 0.0001 {
		up := camera_get_up(camera^)
		forward := camera_get_forward(camera^)

		{ 	// set camera pitch
			angle: f32 = -m_delta.y * mouse_sens

			maxAngleUp := vemath.vec3_angle(up, forward)
			maxAngleUp -= 0.001
			if angle > maxAngleUp do angle = maxAngleUp

			maxAngleDown := -vemath.vec3_angle(-up, forward)
			maxAngleDown += 0.01
			if (angle < maxAngleDown) do angle = maxAngleDown

			camera_set_pitch(camera, angle)
		}

		{ 	// set camera yaw
			camera_set_yaw(camera, -m_delta.x * mouse_sens)
		}
	}

	camera_set_zoom(camera, camera.zoom + mouse_get_scroll_f32() * time_get_delta() * zoom_speed)

	camera.zoom = lin.clamp_vec3(camera.zoom, 0.01, 5)

	if key_is_down(.LeftShift) {
		speed *= 2
	}

	if key_is_down(.W) {
		camera_move(camera, camera_get_forward(camera^) * speed)
	}
	if key_is_down(.S) {
		camera_move(camera, -camera_get_forward(camera^) * speed)
	}
	if key_is_down(.A) {
		camera_move(camera, camera_get_left(camera^) * speed)
	}
	if key_is_down(.D) {
		camera_move(camera, camera_get_right(camera^) * speed)
	}
}
