package graphics

concat :: proc(a: []$T, b: []T) -> []T {
	result := make([]T, len(a) + len(b))
	copy(result, a)
	copy(result[len(a):], b)
	return result
}
