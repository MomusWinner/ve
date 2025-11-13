package eldr

import "core:log"
import gfx "graphics"
import imp "importer"
import "vendor:glfw"
import vk "vendor:vulkan"

@(private)
_init_graphic :: proc(window: glfw.WindowHandle, gfx_init_info: Graphics_Init_Info) {
	ctx.window = window
	ctx.gfx = new(gfx.Graphics)
	gfx.set_logger(context.logger)
	gfx.init_graphic(ctx.gfx, gfx_init_info, &ctx.window)
}

@(require_results)
get_graphics_limits :: proc() -> Graphics_Limits {return ctx.gfx.limits}
@(require_results)
get_screen_width :: proc() -> u32 {return gfx.get_screen_width(ctx.gfx)}
@(require_results)
get_screen_height :: proc() -> u32 {return gfx.get_screen_height(ctx.gfx)}
@(require_results)
screen_resized :: proc() -> bool {return gfx.screen_resized(ctx.gfx)}

// RENDER

@(require_results)
begin_render :: proc() -> Frame_Data {return gfx.begin_render(ctx.gfx)}
end_render :: proc(frame_data: Frame_Data) {
	gfx.end_render(ctx.gfx, frame_data, {})
	glfw.PollEvents()
}
end_render_wait :: proc(frame_data: Frame_Data, sync_data: Sync_Data) {gfx.end_render(ctx.gfx, frame_data, sync_data)}
@(require_results)
begin_draw :: proc(frame_data: Frame_Data) -> Frame_Data {return gfx.begin_draw(ctx.gfx, frame_data)}
end_draw :: proc(frame_data: Frame_Data) {gfx.end_draw(ctx.gfx, frame_data)}

set_full_viewport_scissor :: proc(frame_data: Frame_Data, loc := #caller_location) {
	gfx.set_full_viewport_scissor(ctx.gfx, frame_data, loc)
}
set_viewport :: proc(frame_data: Frame_Data, width, height: u32, max_depth: f32 = 0.1, loc := #caller_location) {
	gfx.set_viewport(ctx.gfx, frame_data, width, height, max_depth, loc)
}
set_scissor :: proc(frame_data: Frame_Data, width, height: u32, offset: ivec2 = {}, loc := #caller_location) {
	gfx.set_scissor(ctx.gfx, frame_data, width, height, offset, loc)
}

// CAMERA

camera_init :: proc(camera: ^Camera, loc := #caller_location) {gfx.camera_init(camera, ctx.gfx, loc)}

@(require_results)
camera_get_forward :: proc(camera: ^Camera, loc := #caller_location) -> vec3 {
	return gfx.camera_get_forward(camera, loc)
}
@(require_results)
camera_get_right :: proc(camera: ^Camera, loc := #caller_location) -> vec3 {return gfx.camera_get_right(camera, loc)}
@(require_results)
camera_get_left :: proc(camera: ^Camera, loc := #caller_location) -> vec3 {return gfx.camera_get_left(camera, loc)}

camera_set_yaw :: proc(camera: ^Camera, angle: f32, loc := #caller_location) {gfx.camera_set_yaw(camera, angle, loc)}
camera_set_pitch :: proc(camera: ^Camera, angle: f32, loc := #caller_location) {
	gfx.camera_set_pitch(camera, angle, loc)
}
camera_set_roll :: proc(camera: ^Camera, angle: f32, loc := #caller_location) {gfx.camera_set_roll(camera, angle, loc)}
camera_set_zoom :: proc(camera: ^Camera, zoom: vec3, loc := #caller_location) {gfx.camera_set_zoom(camera, zoom, loc)}

// TRANSFORM

init_transform :: proc(transfrom: ^Transform) {gfx.init_transform(ctx.gfx, transfrom)}
transform_set_position :: proc(transfrom: ^Transform, pos: vec3) {gfx.transform_set_position(transfrom, pos)}

// MATERIALS

material_init :: proc(material: ^Material, pipeline_h: Pipeline_Handle) {gfx.init_material(
		ctx.gfx,
		material,
		pipeline_h,
	)}
material_set_color :: proc(material: ^Material, color: color) {gfx.material_set_color(material, color)}
material_set_texture :: proc(material: ^Material, texture_h: Texture_Handle) {
	gfx.material_set_texture(material, texture_h)
}

// BUFFERS

create_uniform_buffer :: proc(size: Gfx_Size) {}

// PIPELINE

@(require_results)
create_graphics_pipeline :: proc(
	create_info: ^Create_Pipeline_Info,
	loc := #caller_location,
) -> (
	Pipeline_Handle,
	bool,
) {
	return gfx.create_graphics_pipeline(ctx.gfx, create_info, loc)
}

@(require_results)
get_graphics_pipeline :: proc(pipeline_h: Pipeline_Handle, loc := #caller_location) -> ^Pipeline {
	pipeline, ok := gfx.get_graphics_pipeline(ctx.gfx, pipeline_h)
	assert(ok, "Couldn't get pipeline", loc)
	return pipeline
}

@(require_results)
create_bindless_pipeline_set_info :: proc(allocator := context.allocator) -> Pipeline_Set_Info {
	return gfx.create_bindless_pipeline_set_info(allocator)
}

// TEXTURE

@(require_results)
load_texture :: proc(path: string, mip_levels: u32 = 1, anisotropy: f32 = 1) -> Texture_Handle {
	image, ok := load_image(path)
	defer unload_image(image)
	if !ok {
		log.error("couldn't load texture by path: ", path)
		return {}
	}
	texture := gfx.create_texture(ctx.gfx, image, path, mip_levels, anisotropy)

	return gfx.bindless_store_texture(ctx.gfx, texture)
}

@(require_results)
get_texture :: proc(texture_h: Texture_Handle, loc := #caller_location) -> ^Texture {
	texture, ok := gfx.bindless_get_texture(ctx.gfx, texture_h)
	if !ok {
		log.panicf("Incorrect texture handle", location = loc)
	}

	return texture
}

unload_texture :: proc(texture_h: Texture_Handle) {
	gfx.bindless_destroy_texture(ctx.gfx, texture_h)
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
		meshes[i] = gfx.create_mesh(ctx.gfx.vulkan_state, imp_mesh.vertices, imp_mesh.indices)
	}

	model := gfx.create_model(meshes, {}, {})

	return model
}

destroy_model :: proc(model: ^Model) {gfx.destroy_model(ctx.gfx, model)}

draw_model :: proc(
	frame_data: Frame_Data,
	model: Model,
	camera: ^Camera,
	transform: ^Transform,
	loc := #caller_location,
) {
	gfx.draw_model(ctx.gfx, frame_data, model, camera, transform, loc)
}

// TEXT

@(require_results)
load_font :: proc(create_info: Create_Font_Info, loc := #caller_location) -> Font {
	return gfx.load_font(ctx.gfx, create_info, loc)
}

unload_font :: proc(font: ^Font, loc := #caller_location) {
	gfx.unload_font(ctx.gfx, font, loc)
}

@(require_results)
create_text :: proc(
	font: ^Font,
	text: string,
	position: vec3,
	size: f32,
	color: color = color{1, 1, 1, 1},
	loc := #caller_location,
) -> Text {
	return gfx.create_text(ctx.gfx, font, text, position, color, size, loc)
}

destroy_text :: proc(text: ^Text, loc := #caller_location) {
	gfx.destroy_text(ctx.gfx, text, loc)
}

draw_text :: proc(text: ^Text, frame_data: Frame_Data, camera: ^Camera, loc := #caller_location) {
	gfx.draw_text(ctx.gfx, text, frame_data, camera, loc)
}

text_set_color :: proc(text: ^Text, color: color, loc := #caller_location) {
	gfx.text_set_color(text, color, loc)
}

text_set_string :: proc(text: ^Text, str: string, loc := #caller_location) {
	gfx.text_set_string(text, ctx.gfx, str, loc)
}

// SURFACE

@(require_results)
create_surface :: proc(
	sample_count: Sample_Count_Flag = ._4,
	anisotropy: f32 = 1,
	allocator := context.allocator,
) -> Surface_Handle {
	return gfx.create_surface(ctx.gfx, sample_count, anisotropy, allocator)
}

@(require_results)
get_surface :: proc(surface_h: Surface_Handle) -> (^Surface, bool) {return gfx.get_surface(ctx.gfx, surface_h)}
destroy_surface :: proc(surface_h: Surface_Handle) {gfx.destroy_surface(ctx.gfx, surface_h)}

surface_add_color_attachment :: proc(
	surface: ^Surface,
	clear_value: color = {0.01, 0.01, 0.01, 1.0},
	loc := #caller_location,
) {
	gfx.surface_add_color_attachment(surface, ctx.gfx, clear_value, loc)
}

surface_add_depth_attachment :: proc(surface: ^Surface, clear_value: f32 = 1, loc := #caller_location) {
	gfx.surface_add_depth_attachment(surface, ctx.gfx, clear_value, loc)
}

@(require_results)
begin_surface :: proc(surface: ^Surface, frame_data: Frame_Data, loc := #caller_location) -> Frame_Data {
	return gfx.begin_surface(surface, frame_data, loc)
}

end_surface :: proc(surface: ^Surface, frame_data: Frame_Data, loc := #caller_location) {
	gfx.end_surface(surface, frame_data, loc)
}

draw_surface :: proc(surface: ^Surface, frame_data: Frame_Data, pipeline_h: Pipeline_Handle, loc := #caller_location) {
	gfx.draw_surface(surface, ctx.gfx, frame_data, pipeline_h, loc)
}
