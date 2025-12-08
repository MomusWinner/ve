#version 450

#include "buildin:defines/bindless.h"
#include "buildin:defines/helper.h"

layout(location = 0) in vec2 fragTexCoord;
layout(location = 1) in vec4 fragColor;

layout(location = 0) out vec4 outColor;
// layout(binding = 1) uniform sampler2D texSampler;


void main() {
	if (!HANDLE_VALID(getMaterial().texture)) {
		outColor = getMaterial().color;
	}
	else {
		outColor = texture(uGlobalTextures2D[getMaterial().texture], fragTexCoord);
	}
	// outColor = texture(uGlobalTextures2D[getMaterial().texture], fragTexCoord);

	// outColor = texture(uGlobalTextures2D[0], fragTexCoord);// * PushConstants.color;
	// outColor = vec4(1.0, 1.0, 1.0, 1.0);
}
