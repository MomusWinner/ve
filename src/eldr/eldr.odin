package eldr

import "core:log"
import "core:strings"
import gfx "graphic"
import imp "importer"
import "vendor:glfw"
import stb_image "vendor:stb/image"
import vk "vendor:vulkan"

// Engine
Eldr :: struct {
	g: ^gfx.Graphic,
}

destroy_eldr :: proc(e: ^Eldr) {
	gfx.destroy_graphic(e.g)
	free(e)
}

load_image :: proc(path: string, desired_channels: i32 = 4) -> (image: Image, ok: bool) {
	stb_image.set_flip_vertically_on_load(1)
	width, height, channels: i32

	cpath, alloc_err := strings.clone_to_cstring(path, context.temp_allocator)

	if (alloc_err != .None) {
		log.error("couldn't allocate memory for cstring")
		return image, false
	}

	data := stb_image.load(cpath, &width, &height, &channels, desired_channels)

	image.width = cast(u32)width
	image.height = cast(u32)height
	image.channels = cast(u32)channels
	image.data = data
	ok = true
	return
}

unload_image :: proc(image: Image) {
	defer stb_image.image_free(image.data)
}
