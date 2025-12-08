package eldr

import "core:log"
import gfx "graphics"
import imp "importer"
import "vendor:glfw"
import vk "vendor:vulkan"

@(private)
_init_graphic :: proc(window: ^glfw.WindowHandle, gfx_init_info: gfx.Graphics_Init_Info) {
	gfx.init(gfx_init_info, window)
}

@(require_results)
get_screen_width :: proc() -> u32 {return gfx.get_screen_width()}
@(require_results)
get_screen_height :: proc() -> u32 {return gfx.get_screen_height()}
@(require_results)
screen_resized :: proc() -> bool {return gfx.screen_resized()}

// TEXTURE

@(require_results)
load_texture :: proc(path: string, mip_levels: u32 = 1, anisotropy: f32 = 1) -> gfx.Texture_Handle {
	image, ok := load_image(path)
	defer unload_image(image)
	if !ok {
		log.error("couldn't load texture by path: ", path)
		return {}
	}
	texture := gfx.create_texture(image, path, mip_levels, anisotropy)

	return gfx.bindless_store_texture(texture)
}

@(require_results)
get_texture :: proc(texture_h: gfx.Texture_Handle, loc := #caller_location) -> ^gfx.Texture {
	texture, ok := gfx.bindless_get_texture(texture_h)
	if !ok {
		log.panicf("Incorrect texture handle", location = loc)
	}

	return texture
}

unload_texture :: proc(texture_h: gfx.Texture_Handle) {
	gfx.bindless_destroy_texture(texture_h)
}

// MODEL

@(require_results)
load_model :: proc(path: string) -> gfx.Model {
	imp_meshes, ok := imp.import_obj(path)
	defer delete(imp_meshes)
	if !ok {
		log.error("Couldn't import obj", path)
	}
	meshes := make([]gfx.Mesh, len(imp_meshes))

	for imp_mesh, i in imp_meshes {
		meshes[i] = gfx.create_mesh(imp_mesh.vertices, imp_mesh.indices)
	}

	model := gfx.create_model(meshes, {}, {})

	return model
}
