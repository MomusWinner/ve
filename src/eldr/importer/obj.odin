package importer

import "../common/"

import "core:fmt"
import "core:io"
import "core:log"
import "core:os"
import "core:strconv"
import "core:strings"

vec2 :: common.vec2
vec3 :: common.vec3

Vertex :: common.Vertex

@(private)
_hash :: proc(a: int, b: int, c: int) -> u32 {
	seed: u32 = 0x9747b28
	multiplier: u32 = 0xcc9e2d51
	rot2: u32 = 13
	mix_const: u32 = 0x1b873593

	mix :: proc(k: u32) -> u32 {
		rot1: u32 = 15
		val := k * 0xcc9e2d51
		val = (val << rot1) | (val >> (32 - rot1))
		return 0x1b873593 * val
	}

	k1: u32 = mix(cast(u32)a)
	k2: u32 = mix(cast(u32)b)
	k3: u32 = mix(cast(u32)c)

	h := seed ~ k1
	h = (h << rot2) | (h >> (32 - rot2))
	h = h * 5 + 0xe6546b64
	h ~= k2

	h = (h << rot2) | (h >> (32 - rot2))
	h = h * 5 + 0xe6546b64
	h ~= k3

	h ~= h >> 16
	h *= 0x85ebca6b
	h ~= h >> 13
	h *= 0xc2b2ae35
	h ~= h >> 16

	return h
}

Mesh :: struct {
	name:     string,
	vertices: []Vertex,
	indices:  []u16,
}

import_obj :: proc(path: string, allocator := context.allocator) -> ([]Mesh, bool) {
	parse_f :: proc(s: string) -> (pos: int, tex_coord: int, norm: int) {
		indexes := strings.split(s, "/", context.temp_allocator)
		pos = -1 + strconv.atoi(indexes[0])
		tex_coord = -1 + strconv.atoi(indexes[1])
		norm = -1 + strconv.atoi(indexes[2])
		return
	}

	data, ok := common.read_file(path, context.temp_allocator)
	if !ok {
		log.errorf("Couldn't load file by path: %s", path)
		return nil, false
	}

	data_string := string(data)

	meshes := make([dynamic]Mesh, context.allocator)

	name := ""
	vertices := make([dynamic]Vertex, context.allocator)
	indices := make([dynamic]u16, context.allocator)

	index_by_vertex: map[u32]u16 = make(map[u32]u16, context.temp_allocator)

	pos := make([dynamic]vec3, context.temp_allocator)
	norm := make([dynamic]vec3, context.temp_allocator)
	texCoord := make([dynamic]vec2, context.temp_allocator)

	for line in strings.split_lines_iterator(&data_string) {
		elements := strings.split(line, " ", context.temp_allocator)
		if elements[0] == "o" {
			if name != "" {
				append(&meshes, Mesh{name = elements[1], vertices = vertices[:], indices = indices[:]})
				clear(&vertices)
				clear(&indices)
			}
			name = elements[1]
		}
		if elements[0] == "v" {
			x := cast(f32)strconv.atof(elements[1])
			y := cast(f32)strconv.atof(elements[2])
			z := cast(f32)strconv.atof(elements[3])
			append(&pos, vec3{x, y, z})
		}
		if elements[0] == "vn" {
			x := cast(f32)strconv.atof(elements[1])
			y := cast(f32)strconv.atof(elements[2])
			z := cast(f32)strconv.atof(elements[3])
			append(&norm, vec3{x, y, z})
		}
		if elements[0] == "vt" {
			u := cast(f32)strconv.atof(elements[1])
			v := cast(f32)strconv.atof(elements[2])
			append(&texCoord, vec2{u, v})
		}

		// f v/vt/vn
		if elements[0] == "f" {
			values := elements[1:]
			length := len(values)
			if (length >= 3) {
				line_indices := make([]u16, length, context.temp_allocator)
				for i in 0 ..< length {
					p, t, n := parse_f(values[i])
					hash := _hash(p, t, n)
					index, ok := index_by_vertex[hash]
					if !ok {
						append(&vertices, Vertex{position = pos[p], tex_coord = texCoord[t], normal = norm[n]})
						index = cast(u16)len(vertices) - 1
						index_by_vertex[hash] = index
					}
					line_indices[i] = index
				}
				for i := 1; i < length - 1; i += 1 {
					append(&indices, line_indices[0])
					append(&indices, line_indices[i])
					append(&indices, line_indices[i + 1])
				}
			} else {
				panic("incorrect cout of elements in \"f\"")
			}}
	}
	append(&meshes, Mesh{name = name, vertices = vertices[:], indices = indices[:]})

	return meshes[:], true
}


_info :: proc(vertices: []Vertex, indices: []u16) {
	fmt.printfln("--------------------------------")
	fmt.printfln("Vertices")
	for i in 0 ..< len(vertices) {
		if (i % 2 == 0) {
			fmt.println()
		}
		fmt.printf(" | %f %f %f | ;", vertices[i].position, vertices[i].tex_coord, vertices[i].normal)
	}
	fmt.println()

	fmt.printfln("--------------------------------")
	fmt.printf("indices")

	for i in 0 ..< len(indices) {
		if (i % 3 == 0) {
			fmt.println()
		}
		fmt.printf("%d", indices[i])
	}
}
