#version 450

#include "defines/bindless.h"

layout(location = 0) in vec2 fragTexCoord;
layout(location = 0) out vec4 outColor;

void main() {
	outColor = texture(uGlobalTextures2D[getMaterial().texture], fragTexCoord) * vec4(1, 1, 1, 0.1);
}
