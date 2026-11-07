package ve

import "core:c"
import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import "lib/vma"
import stb_image "vendor:stb/image"
import vk "vendor:vulkan"

Image :: struct {
	width:    int,
	height:   int,
	channels: int,
	data:     [^]byte,
	path:     string,
}

Sampler_Border_Color :: enum {
	Transparent_Black = 0,
	Opaque_Black      = 2,
	Opaque_White      = 4,
}

Sampler_Filter :: enum {
	Nearest = 0,
	Linear  = 1,
}

Sampler_Address_Mode :: enum {
	Repeat               = 0,
	Mirrored_Repeat      = 1,
	Clamp_To_Edge        = 2,
	Clamp_To_Border      = 3,
	Mirror_Clamp_To_Edge = 4,
}

Sampler_Lod_Clamp :: struct {
	min: f32,
	max: f32,
}

Sampler_Info :: struct {
	mag_filter:        Sampler_Filter,
	min_filter:        Sampler_Filter,
	address_mode_u:    Sampler_Address_Mode,
	address_mode_v:    Sampler_Address_Mode,
	address_mode_w:    Sampler_Address_Mode,
	anisotropy_enable: bool,
	max_anisotropy:    f32,
	border_color:      Sampler_Border_Color,
	mipmap_mode:       Sampler_Filter,
	lod_clamp:         Sampler_Lod_Clamp,
}

Pixel_Format :: enum {
	// 1 channel
	R_norm_u8      = 9,
	R_norm_i8      = 10,
	R_u8           = 13,
	R_i8           = 14,
	// 2 channels
	RG_norm_u8     = 16,
	RG_norm_i8     = 17,
	RG_u8          = 20,
	RG_i8          = 21,
	// 3 channels
	RGB_norm_u8    = 23,
	RGB_norm_i8    = 24,
	RGB_u8         = 27,
	RGB_i8         = 28,
	// 4 channels
	RGBA_norm_u8   = 37,
	RGBA_norm_i8   = 38,
	RGBA_scaled_u8 = 39,
	RGBA_scaled_i8 = 40,
	RGBA_u8        = 41,
	RGBA_i8        = 42,
	RGBA_srgb_u8   = 43,
}

load_image :: proc(path: string, desired_channels: int, loc := #caller_location) -> (image: Image, ok: bool) {
	stb_image.set_flip_vertically_on_load(1)
	width, height, channels: i32

	cpath, alloc_err := strings.clone_to_cstring(path, context.temp_allocator)
	if alloc_err != .None do log.panicf("Failed to allocate memory: %v", alloc_err, loc)

	data := stb_image.load(cpath, &width, &height, &channels, cast(i32)desired_channels)

	if data == nil {
		return {}, false
	}

	image.width = cast(int)width
	image.height = cast(int)height
	image.channels = cast(int)desired_channels
	image.path = path
	image.data = data
	ok = true

	return
}

destroy_image :: proc(image: Image) {
	stb_image.image_free(image.data)
}

@(require_results)
load_texture :: proc(
	path: string,
	format: Pixel_Format = .RGBA_srgb_u8,
	sampler_info: Sampler_Info = DEFAULT_SAMPLER_INFO,
	mip_levels: u32 = 1,
	loc := #caller_location,
) -> Texture {
	channels := pixel_format_to_channels(format)
	image, ok := load_image(path, channels, loc = loc)
	defer destroy_image(image)
	if !ok {
		log.error("Couldn't load texture by path: ", path)
		return {}
	}
	return create_texture(image, format, sampler_info, mip_levels, loc)
}

create_texture :: proc(
	image: Image,
	format: Pixel_Format,
	sampler_info: Sampler_Info = DEFAULT_SAMPLER_INFO,
	mip_levels: u32 = 1,
	loc := #caller_location,
) -> Texture {
	return _store_texture(_create_texture(image, format, sampler_info, mip_levels, loc), loc)
}

destroy_texture :: proc(texture: Texture, loc := #caller_location) {
	t := _acquire_texture_h(texture, loc)
	_deferred_destructor_add(t, loc)
}

texture_get_size :: proc(texture: Texture) -> (w: int, h: int) {
	t := _get_texture_h(texture)
	return t.width, t.height
}

texture_get_format :: proc(texture: Texture) -> Format {
	t := _get_texture_h(texture)
	return t.format
}

texture_set_sampler :: proc(texture: Texture, info: Sampler_Info) {
	t := _get_texture_h(texture)
	_destroy_sampler(t.sampler)
	new_sampler := _create_sampler(info)
	t.sampler = new_sampler
	_update_texture_h(texture)
}

CUBEMAP_LAYER_COUNT :: 6

// Creates a cubemap texture from 6 face images.
// Face orientation follows the standard cubemap layout:
// 0: +X (right)   1: -X (left)
// 2: +Y (top)     3: -Y (bottom)
// 4: +Z (front)   5: -Z (back)
@(require_results)
load_cubemap_texture :: proc(
	paths: [CUBEMAP_LAYER_COUNT]string,
	format: Pixel_Format = .RGBA_srgb_u8,
	sampler_info: Sampler_Info = DEFAULT_SAMPLER_INFO,
	mip_levels: u32 = 1,
	loc := #caller_location,
) -> Texture {
	images: [CUBEMAP_LAYER_COUNT]Image
	channels := pixel_format_to_channels(format)
	for path, i in paths {
		image, ok := load_image(path, channels, loc)
		if !ok {
			log.error("Couldn't load texture by path: ", path)
			return {}
		}

		images[i] = image
	}

	texture := _create_texture_cubemap(images, format, sampler_info, mip_levels)

	for &image in images {
		destroy_image(image)
	}

	return _store_texture(texture)
}

// Creates a cubemap texture from 6 face images.
// Face orientation follows the standard cubemap layout:
// 0: +X (right)   1: -X (left)
// 2: +Y (top)     3: -Y (bottom)
// 4: +Z (front)   5: -Z (back)
@(require_results)
create_texture_cubemap :: proc(
	faces: [CUBEMAP_LAYER_COUNT]Image,
	format: Pixel_Format,
	sampler_info: Sampler_Info = DEFAULT_SAMPLER_INFO,
	mip_levels: u32 = 1,
	loc := #caller_location,
) -> Texture {
	return _store_texture(_create_texture_cubemap(faces, format, sampler_info, mip_levels, loc), loc)
}

@(private)
_create_texture_cubemap :: proc(
	faces: [CUBEMAP_LAYER_COUNT]Image,
	format: Pixel_Format,
	sampler_info: Sampler_Info = DEFAULT_SAMPLER_INFO,
	mip_levels: u32 = 1,
	loc := #caller_location,
) -> (
	cubemap: Texture_Cubemap,
) {
	for _, i in faces {
		for _, j in faces {
			if i == j do continue
			ERROR :: "All cubemap faces must have identical width, height, and channel count"
			assert(faces[i].width == faces[j].width, ERROR, loc)
			assert(faces[i].height == faces[j].height, ERROR, loc)
			assert(faces[i].channels == faces[j].channels, ERROR, loc)
		}
	}

	image := faces[0]
	channels: int = pixel_format_to_channels(format)
	layer_size := cast(Device_Size)(image.width * image.height * channels)
	image_size := layer_size * CUBEMAP_LAYER_COUNT

	sc := begin_single_cmd()

	// Staging Buffer
	staging_buffer := _create_buffer({.Transfer, .Host_Write}, size = image_size)
	defer _destroy_buffer(&staging_buffer)

	data := make([]byte, image_size, context.temp_allocator)
	for face, i in faces {
		offset := cast(Device_Size)i * layer_size
		dest := rawptr(uintptr(&data[0]) + uintptr(offset))
		src := rawptr(face.data)

		mem.copy(dest, src, int(layer_size))
	}

	_buffer_fill(&staging_buffer, raw_data(data), image_size)

	_cmd_buffer_barrier(sc.cmd, staging_buffer.id, {.HOST_WRITE}, {.TRANSFER_READ}, {.HOST}, {.TRANSFER})

	format := cast(Format)format

	// Image
	vk_image, allocation, allocation_info := _create_vk_image(
		cast(u32)image.width,
		cast(u32)image.height,
		mip_levels,
		._1,
		_format_to_vk(format),
		.OPTIMAL,
		{.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED},
		vma.MemoryUsage.AUTO_PREFER_DEVICE,
		vma.AllocationCreateFlags{},
		6,
		{.CUBE_COMPATIBLE},
	)

	_cmd_image_transition_layout(
		sc.cmd,
		vk_image,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		vk.ImageSubresourceRange{aspectMask = {.COLOR}, levelCount = mip_levels, layerCount = CUBEMAP_LAYER_COUNT},
	)

	regions: [CUBEMAP_LAYER_COUNT]vk.BufferImageCopy

	for i in 0 ..< CUBEMAP_LAYER_COUNT {
		regions[i] = vk.BufferImageCopy {
			bufferOffset = layer_size * cast(Device_Size)i,
			bufferRowLength = 0,
			bufferImageHeight = 0,
			imageSubresource = vk.ImageSubresourceLayers {
				aspectMask = {.COLOR},
				mipLevel = 0,
				baseArrayLayer = cast(u32)i,
				layerCount = 1,
			},
			imageOffset = {},
			imageExtent = vk.Extent3D{cast(u32)image.width, cast(u32)image.height, 1},
		}
	}

	_cmd_copy_buffer_to_image(sc.cmd, staging_buffer.id, vk_image, regions[:])

	if mip_levels > 1 {
		_generate_mipmaps(
			sc.cmd,
			vk_image,
			_format_to_vk(format),
			cast(i32)image.width,
			cast(i32)image.height,
			mip_levels,
		)
	}

	end_single_cmd(sc)

	image_view := _create_vk_image_view(
		vk_image,
		_format_to_vk(format),
		{.COLOR},
		mip_levels,
		.CUBE,
		CUBEMAP_LAYER_COUNT,
	)
	sampler: vk.Sampler = _create_sampler(sampler_info)

	cubemap.id = vk_image
	cubemap.view = image_view
	cubemap.format = format
	cubemap.sampler = sampler
	cubemap.allocation = allocation
	cubemap.allocation_info = allocation_info

	_vk_set_debug_texture_name(cubemap, fmt.tprintf("%s %s", image.path, _location_to_string(loc)))

	return
}

pixel_format_to_channels :: proc(format: Pixel_Format) -> int {
	if format >= Pixel_Format.R_norm_u8 && format <= Pixel_Format.R_i8 {
		return 1
	} else if format >= Pixel_Format.RG_norm_u8 && format <= Pixel_Format.RG_i8 {
		return 2
	} else if format >= Pixel_Format.RGB_norm_u8 && format <= Pixel_Format.RGB_i8 {
		return 3
	} else if format >= Pixel_Format.RGBA_norm_u8 && format <= Pixel_Format.RGBA_srgb_u8 {
		return 4
	}
	return 0
}
