package eldr

import "common"
import gfx "graphics"

vec2 :: common.vec2
vec3 :: common.vec3
Vertex :: common.Vertex
Image :: common.Image

Texture :: gfx.Texture
VertexInputBindingDescription :: gfx.Vertex_Input_Binding_Description
VertexInputAttributeDescription :: gfx.Vertex_Input_Attribute_Description
VertexInputDescription :: gfx.Vertex_Input_Description

Model :: struct {
	vbo:      gfx.Buffer,
	ebo:      gfx.Buffer,
	vertices: []Vertex,
	indices:  []u16,
}
