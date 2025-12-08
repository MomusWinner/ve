// A temporary pool acquires resources (materials, transforms) for one-frame usage.

package graphics

import "core:log"

@(private)
_init_temp_pools :: proc() {
	ctx.temp_material_pool = new(Temp_Material_Pool)
	_init_temp_material_pool(ctx.temp_material_pool, TEMP_POOL_MATERIAL_SIZE)
	ctx.temp_transform_pool = new(Temp_Transform_Pool)
	_init_temp_transform_pool(ctx.temp_transform_pool, TEMP_POOL_TRANSFORM_SIZE)
}

@(private)
_destroy_temp_pools :: proc() {
	_destroy_temp_material_pool(ctx.temp_material_pool)
	free(ctx.temp_material_pool)
	_destroy_temp_transform_pool(ctx.temp_transform_pool)
	free(ctx.temp_transform_pool)
}

@(require_results)
_temp_pool_acquire_material :: proc() -> Material {
	return _temp_pool_acquire(ctx.temp_material_pool)
}

@(require_results)
_temp_pool_acquire_transform :: proc() -> Gfx_Transform {
	return _temp_pool_acquire(ctx.temp_transform_pool)
}

@(private)
_clear_temp_pool :: proc() {
	_temp_pool_clear(ctx.temp_material_pool)
	_temp_pool_clear(ctx.temp_transform_pool)
}

@(private = "file")
_init_temp_pool :: proc(pool: ^$P/Temp_Pool($T), size: int) {
	pool.resources = make([]T, size)
	pool.next_free_resource = 0
}

@(private = "file")
_destroy_temp_pool :: proc(pool: ^$P/Temp_Pool($T)) {
	delete(pool.resources)
}

@(private = "file")
@(require_results)
_temp_pool_acquire :: proc(pool: ^$P/Temp_Pool($T)) -> T {
	when DEBUG {
		if pool.next_free_resource >= cast(u32)len(pool.resources) {
			log.panicf(
				"Temp %v Pool exhausted: requested element but max %d reached.",
				typeid_of(T),
				len(pool.resources),
			)
		}
	}

	defer pool.next_free_resource += 1

	return pool.resources[pool.next_free_resource]
}

@(private = "file")
_temp_pool_clear :: proc(pool: ^$P/Temp_Pool($T)) {
	pool.next_free_resource = 0
}

@(private = "file")
_init_temp_material_pool :: proc(pool: ^Temp_Material_Pool, size: int, allocator := context) {
	_init_temp_pool(pool, size)
	for i in 0 ..< size {
		init_mtrl_base(&pool.resources[i], {})
	}
}

@(private = "file")
_destroy_temp_material_pool :: proc(pool: ^Temp_Material_Pool) {
	for i in 0 ..< len(pool.resources) {
		destroy_mtrl(&pool.resources[i])
	}
	_destroy_temp_pool(pool)
}

@(private = "file")
_init_temp_transform_pool :: proc(pool: ^Temp_Transform_Pool, size: int, allocator := context) {
	_init_temp_pool(pool, size)
	for i in 0 ..< size {
		init_gfx_trf(&pool.resources[i])
	}
}

@(private)
_destroy_temp_transform_pool :: proc(pool: ^Temp_Transform_Pool) {
	for i in 0 ..< len(pool.resources) {
		destroy_trf(&pool.resources[i])
	}
	_destroy_temp_pool(pool)
}
