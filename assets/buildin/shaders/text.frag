#version 450

#include "buildin:gen_types.h"

layout(location = 0) in vec2 fragTexCoord;
layout(location = 1) in vec4 fragColor;

layout(location = 0) out vec4 outColor;

void main() {
	float a = texture(uGlobalTextures2D[getBaseMaterial().texture], fragTexCoord).r; 
	outColor = vec4(a) * fragColor;
}
