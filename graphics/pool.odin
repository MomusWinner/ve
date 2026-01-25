package graphics

import hm "../handle_map"

Handle_Map_Apply :: struct($T: typeid, $HT: typeid) {
	items:    hm.Handle_Map(T, HT),
	apply:    proc(item: T),
	is_dirty: proc(itme: T) -> bool,
}

Transform_Handle :: hm.Handle

transform_pool: Handle_Map_Apply(Gfx_Transform, Transform_Handle)

// Material
// Uniform
// Gfx_Transform

// materials
// transforms
// uniforms
//
// for material in materials {
// 	if material.dirty {
// 		applay(matterial)
// 	}
// }
//
// for transform in transforms {
// 	if material.dirty {
// 		applay(matterial)
// 	}
// }
//
// for transform in uniforms {
// 	if material.dirty {
// 		applay(matterial)
// 	}
// }
