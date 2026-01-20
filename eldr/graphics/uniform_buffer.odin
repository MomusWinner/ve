package graphics

import hm "../handle_map/"
import "core:log"

Uniform_Buffer_Handle :: distinct hm.Handle
Nil_Uniform_Buffer_Handle :: Uniform_Buffer_Handle{max(u32), max(u32)}

Uniform_Buffer_Manager :: struct {
	buffers: hm.Handle_Map(Uniform_Buffer, Uniform_Buffer_Handle),
}

@(private)
_init_uniform_buffer_manager :: proc() {
	ctx.unifiorm_buffer_manager = new(Uniform_Buffer_Manager)
}

@(private)
_destroy_uniform_buffer_manager :: proc() {
	for ubo in ctx.unifiorm_buffer_manager.buffers.values {
		free(ubo.data)
	}
	hm.destroy(&ctx.unifiorm_buffer_manager.buffers)
	free(ctx.unifiorm_buffer_manager)
}

store_uniform_buffer :: proc(ubo: Uniform_Buffer) -> Uniform_Buffer_Handle {
	return hm.insert(&ctx.unifiorm_buffer_manager.buffers, ubo)
}

get_uniform_buffer :: proc(handle: Uniform_Buffer_Handle) -> (^Uniform_Buffer, bool) {
	return hm.get(&ctx.unifiorm_buffer_manager.buffers, handle)
}

detstroy_uniform_buffer :: proc(handle: Uniform_Buffer_Handle) -> bool {
	uniform_buffer, ok := hm.remove(&ctx.unifiorm_buffer_manager.buffers, handle)
	destroy_buffer_h(uniform_buffer.buffer_h)
	return ok
}

@(private)
_update_uniform_buffers :: proc() {
	for &ubo in ctx.unifiorm_buffer_manager.buffers.values {
		if ubo.dirty {
			ubo.apply(&ubo)
		}
	}
}
