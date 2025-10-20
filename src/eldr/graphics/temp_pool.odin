// A temporary pool acquires resources (materials, transforms) for one-frame usage.

package graphics

import "core:log"

@(private = "file")
_init_temp_pool :: proc(pool: ^$P/Temp_Pool($T), size: int) {
	pool.resources = make([]T, size)
	pool.next_free_resource = 0
}

@(private = "file")
_destroy_temp_pool :: proc(pool: ^$P/Temp_Pool($T)) {
	delete(pool.resources)
}

@(private)
@(require_results)
_temp_pool_acquire :: proc(pool: ^$P/Temp_Pool($T)) -> T {
	if pool.next_free_resource >= cast(u32)len(pool.resources) {
		log.panicf("Temp %v Pool exhausted: requested element but max %d reached.", typeid_of(T), len(pool.resources))
	}
	defer pool.next_free_resource += 1

	return pool.resources[pool.next_free_resource]
}

@(private)
_temp_pool_clear :: proc(pool: ^$P/Temp_Pool($T)) {
	pool.next_free_resource = 0
}

@(private)
_init_temp_material_pool :: proc(g: ^Graphics, pool: ^Temp_Material_Pool, size: int, allocator := context) {
	_init_temp_pool(pool, size)
	for i in 0 ..< size {
		init_material(g, &pool.resources[i], {})
	}
}

@(private)
_destroy_temp_material_pool :: proc(g: ^Graphics, pool: ^Temp_Material_Pool) {
	for i in 0 ..< len(pool.resources) {
		destroy_material(g, &pool.resources[i])
	}
	_destroy_temp_pool(pool)
}

@(private)
_init_temp_transform_pool :: proc(g: ^Graphics, pool: ^Temp_Transform_Pool, size: int, allocator := context) {
	_init_temp_pool(pool, size)
	for i in 0 ..< size {
		init_transform(g, &pool.resources[i])
	}
}

@(private)
_destroy_temp_transform_pool :: proc(g: ^Graphics, pool: ^Temp_Transform_Pool) {
	for i in 0 ..< len(pool.resources) {
		transform_destroy(&pool.resources[i], g)
	}
	_destroy_temp_pool(pool)
}
