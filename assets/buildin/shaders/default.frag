#version 450

#include "buildin:gen_types.h"
#include "buildin:defines/helper.h"

layout(location = 0) in vec2 fragTexCoord;
layout(location = 1) in vec4 fragColor;

layout(location = 0) out vec4 outColor;


void main() {
	if (!HANDLE_VALID(getMtrlBase().texture)) {
		outColor = getMtrlBase().color;
	}
	else {
		outColor = texture(uGlobalTextures2D[getMtrlBase().texture], fragTexCoord);
	}
}
