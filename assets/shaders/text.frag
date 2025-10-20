#version 450

#include "defines/bindless.h"

layout(location = 0) in vec2 fragTexCoord;
layout(location = 1) in vec4 fragColor;

layout(location = 0) out vec4 outColor;

void main() {
	float a = texture(uGlobalTextures2D[getMaterial().texture], fragTexCoord).r; 
	outColor = vec4(a) * fragColor;

	// if (a < 0.8) {
	// 	discard;
	// }
	// outColor = vec4(0.5, 0.5, 0.5, 1.0);
}
