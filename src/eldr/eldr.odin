package eldr

import "core:log"
import "core:strings"
import gfx "graphics"
import imp "importer"
import "vendor:glfw"
import stb_image "vendor:stb/image"
import vk "vendor:vulkan"

Eldr :: struct {
	gfx: ^gfx.Graphics,
}

// @(private) TODO: make private
ctx: Eldr

destroy_eldr :: proc() {
	gfx.destroy_graphic(ctx.gfx)
}

load_image :: proc(path: string, desired_channels: i32 = 0) -> (image: Image, ok: bool) {
	stb_image.set_flip_vertically_on_load(1)
	width, height, channels: i32

	cpath, alloc_err := strings.clone_to_cstring(path, context.temp_allocator)
	assert(alloc_err == .None, "couldn't allocate memory for cstring")

	data := stb_image.load(cpath, &width, &height, &channels, desired_channels)

	if channels == 0 {
		return {}, false
	}

	image.width = cast(u32)width
	image.height = cast(u32)height
	image.channels = desired_channels == 0 ? cast(u32)channels : cast(u32)desired_channels

	switch image.channels {
	case 1:
		image.pixel = .GRAY
	case 2:
		image.pixel = .GRAY_ALPHA
	case 3:
		image.pixel = .R8G8B8
	case 4:
		image.pixel = .R8G8B8A8
	}

	image.data = data
	ok = true

	return
}

unload_image :: proc(image: Image) {
	defer stb_image.image_free(image.data)
}
