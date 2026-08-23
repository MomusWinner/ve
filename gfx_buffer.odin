package ve

import hm "container/handle_map"

Buffer_Usage_Flags :: distinct bit_set[Buffer_Usage_Flag]
Buffer_Usage_Flag :: enum {
	// GPU
	Vertex,
	Index,
	Uniform,
	Storage,
	Transfer,
	// CPU
	Host_Read,
	Host_Write,
}

Uniform_Buffer :: distinct hm.Handle
INVALID_UNIFORM_BUFFER_HANDLE :: Uniform_Buffer{max(u32), max(u32)}
Storage_Buffer :: distinct hm.Handle
INVALID_STORAGE_BUFFER_HANDLE :: Storage_Buffer{max(u32), max(u32)}

Cached_Buffer :: struct {
	buffer: Buffer,
	dirty:  bool,
	apply:  proc(data: ^Cached_Buffer, loc := #caller_location),
	data:   rawptr,
	type:   typeid,
}

Uniform_Buffer_Data :: Cached_Buffer
Storage_Buffer_Data :: Cached_Buffer

@(require_results)
create_buffer :: proc(usage: Buffer_Usage_Flags, size: int, data: rawptr = nil, loc := #caller_location) -> Buffer {
	data := _create_buffer(usage, cast(Device_Size)size, data, loc)
	return _store_buffer(data)
}

destroy_buffer :: proc(b: Buffer, loc := #caller_location) {
	_deferred_destructor_add(b, loc)
}

buffer_fill :: proc(b: Buffer, size: int, data: rawptr, offset: int = 0, loc := #caller_location) {
	b_data := _get_buffer_h(b)
	_buffer_fill(b_data, data, cast(Device_Size)size, cast(Device_Size)offset, loc)
}

buffer_read :: proc(b: Buffer, loc := #caller_location) -> (data: rawptr, size: int) {
	b_data := _get_buffer_h(b)
	d, s := _buffer_read(b_data, loc)
	return d, cast(int)s
}

// used for generated uniform and storage object structs

ubo_get_buffer :: proc(h: Uniform_Buffer) -> Buffer {
	b := ubo_get_data(h)
	return b.buffer
}

store_ubo :: proc(ubo: Uniform_Buffer_Data) -> Uniform_Buffer {
	return hm.insert(&ctx.gfx.buffer_manager.uniform_buffers, ubo)
}

ubo_get_data :: proc(handle: Uniform_Buffer, loc := #caller_location) -> ^Uniform_Buffer_Data {
	b, ok := hm.get(&ctx.gfx.buffer_manager.uniform_buffers, handle)
	assert(ok, "Invalid uniform buffer handle", loc)
	return b
}

ubo_is_valid :: proc(handle: Uniform_Buffer) -> bool {
	return hm.has_handle(&ctx.gfx.buffer_manager.uniform_buffers, handle)
}

destroy_ubo :: proc(handle: Uniform_Buffer, loc := #caller_location) -> bool {
	uniform_buffer, ok := hm.remove(&ctx.gfx.buffer_manager.uniform_buffers, handle)
	if !ok do return false
	free(uniform_buffer.data)
	destroy_buffer(uniform_buffer.buffer, loc)
	return true
}

sbo_get_buffer :: proc(h: Storage_Buffer) -> Buffer {
	b := sbo_get_data(h)
	return b.buffer
}

store_sbo :: proc(sbo: Storage_Buffer_Data) -> Storage_Buffer {
	return hm.insert(&ctx.gfx.buffer_manager.storage_buffers, sbo)
}

sbo_is_valid :: proc(handle: Storage_Buffer) -> bool {
	return hm.has_handle(&ctx.gfx.buffer_manager.storage_buffers, handle)
}

sbo_get_data :: proc(handle: Storage_Buffer, loc := #caller_location) -> ^Storage_Buffer_Data {
	b, ok := hm.get(&ctx.gfx.buffer_manager.storage_buffers, handle)
	assert(ok, "Invalid uniform buffer handle", loc)
	return b
}

destroy_sbo :: proc(handle: Storage_Buffer, loc := #caller_location) -> bool {
	storage_buffer, ok := hm.remove(&ctx.gfx.buffer_manager.storage_buffers, handle)
	if !ok do return false
	free(storage_buffer.data)
	destroy_buffer(storage_buffer.buffer, loc)
	return true
}
