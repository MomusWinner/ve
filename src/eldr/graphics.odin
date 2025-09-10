package eldr

import "core:log"
import gfx "graphics"
import imp "importer"
import "vendor:glfw"
import vk "vendor:vulkan"

init_graphic :: proc(window: glfw.WindowHandle) {
	ctx.g = new(gfx.Graphics)
	gfx.set_logger(context.logger)
	gfx.init_graphic(ctx.g, window)
}

get_width :: proc() -> u32 {return gfx.get_width(ctx.g)}
get_height :: proc() -> u32 {return gfx.get_height(ctx.g)}

begin_render :: proc() -> (Frame_Data, Begin_Render_Error) {return gfx.begin_render(ctx.g)}
end_render :: proc(frame_data: Frame_Data) {gfx.end_render(ctx.g, frame_data, {})}
end_render_wait :: proc(frame_data: Frame_Data, sync_data: Sync_Data) {gfx.end_render(ctx.g, frame_data, sync_data)}
begin_draw :: proc(frame_data: Frame_Data) {gfx.begin_draw(ctx.g, frame_data)}
end_draw :: proc(frame_data: Frame_Data) {gfx.end_draw(ctx.g, frame_data)}

cmd_set_full_viewport :: proc(cmd: Command_Buffer) {gfx.cmd_set_full_viewport(ctx.g, cmd)}

// CAMERA

camera_init :: proc(camera: ^Camera) {gfx.camera_init(camera, ctx.g)}
camera_set_yaw :: proc(camera: ^Camera, angle: f32) {gfx.camera_set_yaw(camera, angle)}
camera_get_forward :: proc(camera: ^Camera) -> vec3 {return gfx.camera_get_forward(camera)}
camera_apply :: proc(camera: ^Camera, width: f32, height: f32) {gfx.camera_apply(camera, ctx.g, width, height)}

// TRANSFORM

transform_init :: proc(transfrom: ^Transform) {gfx.transform_init(transfrom, ctx.g)}
transform_set_position :: proc(transfrom: ^Transform, pos: vec3) {gfx.transform_set_position(transfrom, pos)}
transform_apply :: proc(transfrom: ^Transform) {gfx.transform_apply(transfrom, ctx.g)}

// MATERIALS

material_init :: proc(material: ^Material, pipeline_h: Pipeline_Handle) {gfx.material_init(material, ctx.g, pipeline_h)}
material_update :: proc(material: ^Material) {gfx.material_update(material, ctx.g)}

// BUFFERS

create_uniform_buffer :: proc(size: Gfx_Size) {}

// PIPELINE

create_graphics_pipeline :: proc(create_info: ^Create_Pipeline_Info) -> (Pipeline_Handle, bool) {
	return gfx.create_graphics_pipeline(ctx.g, create_info)
}

get_graphics_pipeline :: proc(pipeline_h: Pipeline_Handle, loc := #caller_location) -> ^Pipeline {
	pipeline, ok := gfx.get_graphics_pipeline(ctx.g, pipeline_h)
	assert(ok, "Couldn't get pipeline", loc)
	return pipeline
}

create_bindless_pipeline_set_info :: proc(allocator := context.allocator) -> Pipeline_Set_Info {
	return gfx.create_bindless_pipeline_set_info(allocator)
}

// TEXTURE

load_texture :: proc(path: string) -> Texture_Handle {
	image, ok := load_image(path)
	defer unload_image(image)
	if !ok {
		log.error("couldn't load texture by path: ", path)
		return {}
	}
	texture := gfx.create_texture(ctx.g, image, path)

	return gfx.bindless_store_texture(ctx.g, texture)
}

get_texture :: proc(texture_h: Texture_Handle, loc := #caller_location) -> ^Texture {
	texture, ok := gfx.bindless_get_texture(ctx.g, texture_h)
	if !ok {
		log.panicf("Incorrect texture handle", location = loc)
	}

	return texture
}

unload_texture :: proc(texture_h: Texture_Handle) {
	gfx.bindless_destroy_texture(ctx.g, texture_h)
}

// MODEL

load_model :: proc(path: string) -> Model {
	imp_meshes, ok := imp.import_obj(path)
	defer delete(imp_meshes)
	if !ok {
		log.error("Couldn't import obj", path)
	}
	meshes := make([]gfx.Mesh, len(imp_meshes))

	for imp_mesh, i in imp_meshes {
		meshes[i] = gfx.create_mesh(ctx.g, imp_mesh.vertices, imp_mesh.indices)
	}

	model := gfx.create_model(meshes, {}, {})

	return model
}

destroy_model :: proc(model: ^Model) {gfx.destroy_model(ctx.g, model)}

draw_model :: proc(model: Model, camera: Camera, transform: Transform, cmd: Command_Buffer) {
	gfx.draw_model(ctx.g, model, camera, transform, cmd)
}

// SURFACE

surface_init :: proc(surface: ^Surface, width, height: u32, allocator := context.allocator) {
	gfx.surface_init(surface, ctx.g, width, height, allocator)
}

surface_destroy :: proc(surface: ^Surface) {gfx.surface_destroy(surface, ctx.g)}

surface_add_color_attachment :: proc(surface: ^Surface) {gfx.surface_add_color_attachment(surface, ctx.g)}

surface_add_depth_attachment :: proc(surface: ^Surface) {gfx.surface_add_depth_attachment(surface, ctx.g)}

surface_begin :: proc(surface: ^Surface) -> Frame_Data {return gfx.surface_begin(surface, ctx.g)}

surface_end :: proc(surface: ^Surface, fame_data: Frame_Data) {gfx.surface_end(surface, fame_data)}

surface_draw :: proc(surface: ^Surface, frame_data: Frame_Data, pipeline_h: Pipeline_Handle) {
	gfx.surface_draw(surface, ctx.g, frame_data, pipeline_h)
}
