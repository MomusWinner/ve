package eldr

import "core:log"
import gfx "graphic"
import imp "importer"
import "vendor:glfw"
import vk "vendor:vulkan"

init_graphic :: proc(e: ^Eldr, window: glfw.WindowHandle) {
	e.g = new(gfx.Graphic)
	gfx.set_logger(context.logger)
	gfx.init_graphic(e.g, window)
}

load_texture :: proc(e: ^Eldr, path: string) -> (texture: Texture) {
	image, ok := load_image(path)
	defer unload_image(image)
	if !ok {
		log.error("couldn't load texture by path: ", path)
		return
	}
	texture = gfx.create_texture(e.g, image)
	return
}

unload_texture :: proc(e: ^Eldr, texture: ^Texture) {
	gfx.destroy_texture(e.g, texture)
}

load_model :: proc(e: ^Eldr, path: string) -> Model {
	vertices, indices, ok := imp.import_obj(path)

	vertices_size := cast(vk.DeviceSize)(size_of(vertices[0]) * len(vertices))
	vertex_buffer := gfx.create_vertex_buffer(e.g, raw_data(vertices), vertices_size)

	indices_size := cast(vk.DeviceSize)(size_of(indices[0]) * len(indices))
	index_buffer := gfx.create_index_buffer(e.g, raw_data(indices), indices_size)

	return Model{vertices = vertices, indices = indices, vbo = vertex_buffer, ebo = index_buffer}
}

destroy_model :: proc(e: ^Eldr, model: ^Model) {
	gfx.destroy_buffer(e.g, &model.vbo)
	gfx.destroy_buffer(e.g, &model.ebo)
	delete(model.vertices)
	delete(model.indices)
}
