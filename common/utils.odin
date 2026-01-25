package common

import "core:fmt"
import "core:os"

read_file :: proc(name: string, allocator := context.allocator) -> ([]byte, bool) {
	data, ok := os.read_entire_file(name, allocator)
	return data, ok
}

wirte_file :: proc(name: string, data: []byte) -> bool {
	return os.write_entire_file(name, data)
}

assert_not_nil :: #force_inline proc(obj: ^$T, loc := #caller_location) {
	assert(obj != nil, fmt.tprintf("%T is nil", obj), loc = loc)
}

merge :: proc(a: []$T, b: []T, allocator := context.allocator, loc := #caller_location) -> []T {
	result := make([]T, len(a) + len(b), allocator)
	copy(result, a)
	copy(result[len(a):], b)
	return result
}
