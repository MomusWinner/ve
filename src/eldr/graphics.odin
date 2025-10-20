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

@(require_results)
get_screen_width :: proc() -> u32 {return gfx.get_screen_width(ctx.g)}
@(require_results)
get_screen_height :: proc() -> u32 {return gfx.get_screen_height(ctx.g)}
@(require_results)
screen_resized :: proc() -> bool {return gfx.screen_resized(ctx.g)}

@(require_results)
begin_render :: proc() -> Frame_Data {return gfx.begin_render(ctx.g)}
end_render :: proc(frame_data: Frame_Data) {gfx.end_render(ctx.g, frame_data, {})}
end_render_wait :: proc(frame_data: Frame_Data, sync_data: Sync_Data) {gfx.end_render(ctx.g, frame_data, sync_data)}
begin_draw :: proc(frame_data: Frame_Data) {gfx.begin_draw(ctx.g, frame_data)}
end_draw :: proc(frame_data: Frame_Data) {gfx.end_draw(ctx.g, frame_data)}

cmd_set_full_viewport :: proc(cmd: Command_Buffer) {gfx.cmd_set_full_viewport(ctx.g, cmd)}

// CAMERA

camera_init :: proc(camera: ^Camera, width: f32, height: f32) {gfx.camera_init(camera, ctx.g, width, height)}

@(require_results)
camera_get_forward :: proc(camera: ^Camera) -> vec3 {return gfx.camera_get_forward(camera)}
@(require_results)
camera_get_right :: proc(camera: ^Camera) -> vec3 {return gfx.camera_get_right(camera)}
@(require_results)
camera_get_left :: proc(camera: ^Camera) -> vec3 {return gfx.camera_get_left(camera)}

camera_set_yaw :: proc(camera: ^Camera, angle: f32) {gfx.camera_set_yaw(camera, angle)}
camera_set_pitch :: proc(camera: ^Camera, angle: f32) {gfx.camera_set_pitch(camera, angle)}
camera_set_roll :: proc(camera: ^Camera, angle: f32) {gfx.camera_set_roll(camera, angle)}
camera_set_zoom :: proc(camera: ^Camera, zoom: vec3) {gfx.camera_set_zoom(camera, zoom)}
camera_set_aspect :: proc(camera: ^Camera, width: f32, height: f32) {gfx.camera_set_aspect(camera, width, height)}

camera_apply :: proc(camera: ^Camera) {gfx.camera_apply(camera, ctx.g)}

// TRANSFORM

init_transform :: proc(transfrom: ^Transform) {gfx.init_transform(ctx.g, transfrom)}
transform_set_position :: proc(transfrom: ^Transform, pos: vec3) {gfx.transform_set_position(transfrom, pos)}

// MATERIALS

material_init :: proc(material: ^Material, pipeline_h: Pipeline_Handle) {gfx.init_material(ctx.g, material, pipeline_h)}
material_set_color :: proc(material: ^Material, color: color) {gfx.material_set_color(material, color)}
material_set_texture :: proc(material: ^Material, texture_h: Texture_Handle) {
	gfx.material_set_texture(material, texture_h)
}

// BUFFERS

create_uniform_buffer :: proc(size: Gfx_Size) {}

// PIPELINE

@(require_results)
create_graphics_pipeline :: proc(create_info: ^Create_Pipeline_Info) -> (Pipeline_Handle, bool) {
	return gfx.create_graphics_pipeline(ctx.g, create_info)
}

@(require_results)
get_graphics_pipeline :: proc(pipeline_h: Pipeline_Handle, loc := #caller_location) -> ^Pipeline {
	pipeline, ok := gfx.get_graphics_pipeline(ctx.g, pipeline_h)
	assert(ok, "Couldn't get pipeline", loc)
	return pipeline
}

@(require_results)
create_bindless_pipeline_set_info :: proc(allocator := context.allocator) -> Pipeline_Set_Info {
	return gfx.create_bindless_pipeline_set_info(allocator)
}

// TEXTURE

@(require_results)
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

@(require_results)
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

@(require_results)
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

draw_model :: proc(model: Model, camera: Camera, transform: ^Transform, cmd: Command_Buffer) {
	gfx.draw_model(ctx.g, model, camera, transform, cmd)
}

// TEXT

@(require_results)
load_font :: proc(create_info: Create_Font_Info, loc := #caller_location) -> Font {
	return gfx.load_font(ctx.g, create_info, loc)
}
unload_font :: proc(font: ^Font) {gfx.unload_font(ctx.g, font)}
@(require_results)
create_text :: proc(
	font: ^Font,
	text: string,
	position: vec3,
	size: f32,
	color: color = color{1, 1, 1, 1},
	loc := #caller_location,
) -> Text {
	return gfx.create_text(ctx.g, font, text, position, color, size, loc)
}
destroy_text :: proc(text: ^Text) {gfx.destroy_text(ctx.g, text)}
draw_text :: proc(text: ^Text, frame_data: Frame_Data, camera: Camera) {gfx.draw_text(ctx.g, text, frame_data, camera)}
text_set_color :: proc(text: ^Text, color: color) {gfx.text_set_color(text, color)}
text_set_string :: proc(text: ^Text, str: string) {gfx.text_set_string(text, ctx.g, str)}

// SURFACE

@(require_results)
create_surface :: proc(width, height: u32, allocator := context.allocator) -> Surface_Handle {
	return gfx.create_surface(ctx.g, width, height, allocator)
}
@(require_results)
get_surface :: proc(surface_h: Surface_Handle) -> (^Surface, bool) {return gfx.get_surface(ctx.g, surface_h)}
destroy_surface :: proc(surface_h: Surface_Handle) {gfx.destroy_surface(ctx.g, surface_h)}
surface_add_color_attachment :: proc(surface: ^Surface) {gfx.surface_add_color_attachment(surface, ctx.g)}
surface_add_depth_attachment :: proc(surface: ^Surface) {gfx.surface_add_depth_attachment(surface, ctx.g)}
@(require_results)
surface_begin :: proc(surface: ^Surface) -> Frame_Data {return gfx.surface_begin(surface, ctx.g)}
surface_end :: proc(surface: ^Surface, fame_data: Frame_Data) {gfx.surface_end(surface, fame_data)}
surface_draw :: proc(surface: ^Surface, frame_data: Frame_Data, pipeline_h: Pipeline_Handle) {
	gfx.surface_draw(surface, ctx.g, frame_data, pipeline_h)
}
