package graphics

import "core:log"

Resource :: union {
	Buffer,
	Texture,
	Buffer_Handle,
	Texture_Handle,
}

DEFFERED_DESTRUCTOR_SIZE :: 1000

Deferred_Destructor :: struct {
	resources:  [DEFFERED_DESTRUCTOR_SIZE]Resource,
	next_index: int,
}

deffered_destructor_add :: proc(g: ^Graphics, resource: Resource) {
	_deffered_destructor_add(g.deffered_destructor, resource)
}

deffered_destructor_clean :: proc(g: ^Graphics) {
	_deffered_destructor_clean(g.deffered_destructor, g)
}

destroy_deffered_destructor :: proc(g: ^Graphics) {
	_destroy_deffered_destructor(g, g.deffered_destructor)
}

@(private)
_deffered_destructor_add :: proc(d: ^Deferred_Destructor, resource: Resource) {
	d.resources[d.next_index] = resource
	d.next_index += 1
}

@(private)
_deffered_destructor_clean :: proc(d: ^Deferred_Destructor, g: ^Graphics) {
	for i in 0 ..< d.next_index {
		switch &resource in d.resources[i] {
		case Buffer:
			destroy_buffer(g, &resource)
		case Buffer_Handle:
			bindless_destroy_buffer(g, resource)
		case Texture:
			destroy_texture(g, &resource)
		case Texture_Handle:
			bindless_destroy_texture(g, resource)
		}
	}
	d.next_index = 0
}

@(private)
_destroy_deffered_destructor :: proc(g: ^Graphics, d: ^Deferred_Destructor) {
	_deffered_destructor_clean(d, g)
}
