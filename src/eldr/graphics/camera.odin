package graphics

import "core:math/linalg/glsl"

DEFAULT_FOV :: 45
DEFAULT_NEAR :: 0.01
DEFAULT_FAR :: 100

Camera_UBO :: struct {
	view:       mat4,
	projection: mat4,
}

Camera :: struct {
	view:       mat4,
	projection: mat4,
	position:   vec3,
	target:     vec3,
	up:         vec3,
	fov:        f32,
	near:       f32,
	far:        f32,
	buffer_h:   Buffer_Handle,
	dirty:      bool,
}

camera_init :: proc(camera: ^Camera, g: ^Graphics) {
	camera.fov = DEFAULT_FOV
	camera.near = DEFAULT_NEAR
	camera.far = DEFAULT_FAR

	buffer := create_uniform_buffer(g, size_of(Camera_UBO))
	camera.buffer_h = bindless_store_buffer(g, buffer)
}

camera_get_forward :: proc(camera: ^Camera) -> vec3 {
	return glsl.normalize_vec3(camera.target - camera.position)
}

camera_set_yaw :: proc(camera: ^Camera, angle: f32) {
	target_position := camera.target - camera.position
	trans := glsl.mat4Rotate(camera.up, glsl.radians(angle))
	target := trans * vec4{target_position.x, target_position.y, target_position.z, 0}
	camera.target = target.xyz
	camera.dirty = true
}

camera_apply :: proc(camera: ^Camera, g: ^Graphics, width: f32, height: f32) {
	if !camera.dirty {
		return
	}
	camera.view = glsl.mat4LookAt(camera.position, camera.position + camera_get_forward(camera), camera.up) // TODO: forawrd
	camera.projection = glsl.mat4Perspective(glsl.radians_f32(camera.fov), (width / height), camera.near, camera.far)
	// NOTE: GLM was originally designed for OpenGL, where the Y coordinate of the clip coordinates is inverted
	camera.projection[1][1] *= -1

	buffer := bindless_get_buffer(g, camera.buffer_h)
	camera_ubo := Camera_UBO {
		view       = camera.view,
		projection = camera.projection,
	}
	_fill_buffer(g, buffer, size_of(Camera_UBO), &camera_ubo)

	camera.dirty = false
}
