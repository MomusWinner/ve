#version 450

#include "buildin:defines/bindless.h"

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;
layout(location = 2) in vec3 inNormal;
layout(location = 3) in vec4 inColor;

layout(location = 0) out vec2 fragTexCoord;
layout(location = 1) out vec4 fragColor;

void main() {
	gl_Position = getModel() * vec4(inPosition, 1.0);
	fragTexCoord = inTexCoord;
	fragColor = inColor;
}
