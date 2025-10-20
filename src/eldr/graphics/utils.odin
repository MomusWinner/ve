package graphics

import "core:log"
import vk "vendor:vulkan"

@(private)
must :: proc(result: vk.Result, msg: string = "", loc := #caller_location) {
	if result != .SUCCESS {
		log.panicf("vulkan failure: %s (%v)", msg, result, location = loc)
	}
}

@(private)
concat :: proc(a: []$T, b: []T, allocator := context.allocator, loc := #caller_location) -> []T {
	result := make([]T, len(a) + len(b), allocator)
	copy(result, a)
	copy(result[len(a):], b)
	return result
}
