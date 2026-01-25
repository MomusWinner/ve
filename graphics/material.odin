package graphics

import hm "../handle_map"
import "core:math/linalg/glsl"

Material_Handle :: distinct hm.Handle
Nil_Material_Buffer_Handle :: Material_Handle{max(u32), max(u32)}

Material_Manager :: struct {
	materials: hm.Handle_Map(Material, Material_Handle),
}

Empty_Material :: Material


@(private)
_init_material_manager :: proc() {
	ctx.material_manager = new(Material_Manager)
}

@(private)
_destroy_material_manager :: proc() {
	for &material in ctx.material_manager.materials.values {
		free(material.data)
	}
	hm.destroy(&ctx.material_manager.materials)
	free(ctx.material_manager)
}

create_mtrl_empty :: proc(pipeline_h: Render_Pipeline_Handle) -> Material_Handle {
	m := Material {
		pipeline_h = pipeline_h,
	}
	m.pipeline_h = pipeline_h
	m.type = typeid_of(^Empty_Material)
	m.dirty = false

	return store_material(m)
}

store_material :: proc(m: Material) -> Material_Handle {
	return hm.insert(&ctx.material_manager.materials, m)
}

get_material :: proc(handle: Material_Handle) -> (^Material, bool) {
	return hm.get(&ctx.material_manager.materials, handle)
}

detstroy_material :: proc(handle: Material_Handle) -> bool {
	material, ok := hm.remove(&ctx.material_manager.materials, handle)
	_destroy_mtrl(&material)
	return ok
}

@(private)
_update_materials :: proc() {
	for &m in ctx.material_manager.materials.values {
		if m.dirty {
			m.apply(&m)
		}
	}
}

mtrl_set_pipeline :: proc(material: ^Material, pipeline_h: Render_Pipeline_Handle, loc := #caller_location) {
	assert_not_nil(material, loc)
	material.pipeline_h = pipeline_h
}

@(private)
_destroy_mtrl :: proc(material: ^Material, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(material, loc)
	free(material.data)

	destroy_buffer_h(material.buffer_h, loc)
}
