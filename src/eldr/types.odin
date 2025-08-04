package eldr

import "common"
import gfx "graphic"

vec2 :: common.vec2
vec3 :: common.vec3
Vertex :: common.Vertex
Image :: common.Image

Texture :: gfx.Texture
VertexInputBindingDescription :: gfx.VertexInputBindingDescription
VertexInputAttributeDescription :: gfx.VertexInputAttributeDescription
VertexInputDescription :: gfx.VertexInputDescription

Model :: struct {
	vbo:      gfx.Buffer,
	ebo:      gfx.Buffer,
	vertices: []Vertex,
	indices:  []u16,
}
