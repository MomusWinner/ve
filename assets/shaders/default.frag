#version 450

#include "defines/bindless.h"

layout(location = 0) in vec2 fragTexCoord;

layout(location = 0) out vec4 outColor;
// layout(binding = 1) uniform sampler2D texSampler;

void main() {
	// outColor = vec4(fragColor, 1.0);

	outColor = texture(uGlobalTextures2D[getMaterial().texture], fragTexCoord);
	// outColor = texture(uGlobalTextures2D[0], fragTexCoord);// * PushConstants.color;
	// outColor = vec4(1.0, 1.0, 1.0, 1.0);
}
