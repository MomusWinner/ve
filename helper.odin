package ve

import "core:log"
import lin "core:math/linalg/glsl"
import gfx "graphics"
import vemath "math"

camera_update_simple_controller :: proc(
	camera: ^gfx.Camera,
	speed: f32 = 2.0,
	mouse_sens: f32 = 0.1,
	zoom_speed: f32 = 2.5,
) {
	speed := speed
	speed *= get_delta_time()

	m_delta := get_mouse_delta()
	if lin.length_vec2(m_delta) > 0.0001 {
		up := gfx.camera_get_up(camera)
		forward := gfx.camera_get_forward(camera)

		{ 	// set camera pitch
			angle: f32 = -m_delta.y * get_delta_time() * mouse_sens

			maxAngleUp := vemath.vec3_angle(up, forward)
			maxAngleUp -= 0.001
			if angle > maxAngleUp do angle = maxAngleUp

			maxAngleDown := -vemath.vec3_angle(-up, forward)
			maxAngleDown += 0.01
			if (angle < maxAngleDown) do angle = maxAngleDown

			gfx.camera_set_pitch(camera, angle)
		}

		{ 	// set camera yaw
			gfx.camera_set_yaw(camera, -m_delta.x * get_delta_time() * mouse_sens)
		}
	}

	gfx.camera_set_zoom(camera, camera.zoom + get_scroll_f32() * get_delta_time() * zoom_speed)

	camera.zoom = lin.clamp_vec3(camera.zoom, 0.01, 5)

	if is_key_down(.LeftShift) {
		speed *= 2
	}

	if is_key_down(.W) {
		gfx.camera_move(camera, gfx.camera_get_forward(camera) * speed)
	}
	if is_key_down(.S) {
		gfx.camera_move(camera, -gfx.camera_get_forward(camera) * speed)
	}
	if is_key_down(.A) {
		gfx.camera_move(camera, gfx.camera_get_left(camera) * speed)
	}
	if is_key_down(.D) {
		gfx.camera_move(camera, gfx.camera_get_right(camera) * speed)
	}
}
