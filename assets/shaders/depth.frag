#version 450

#include "gen_types.h"

layout(location = 0) in vec2 fragTexCoord;
layout(location = 0) out vec4 outColor;

float LinearizeDepth(float depth, float near_plane, float far_plane) {
	float z = depth * 2.0 - 1.0; // Back to NDC 
	return (2.0 * near_plane * far_plane) / (far_plane + near_plane - z * (far_plane - near_plane));
}

void main() {
	float near_plane = 1.0;
	float far_plane = 16.5;
	float depth = texture(uGlobalTextures2D[getMtrlPostprocessing().texture], fragTexCoord).r;
	// depth = LinearizeDepth(depth, near_plane, far_plane);
	outColor = vec4(vec3(depth / far_plane), 1);



	// float depth = texture(uGlobalTextures2D[getPostprocessingMaterial().texture], fragTexCoord).r;
	// outColor = vec4(vec3(depth), 1);


	// if (depth > 0.995) {
	// 	depth = 1;
	// } else {
	// 	depth = 0;
	// }

	// float nearPlane = 0.01;
	// float farPlane = 100;
	// float linearDepth = nearPlane * farPlane / (farPlane + depth * (farPlane - nearPlane));
	// outColor = vec4(vec3(linearDepth), 1);
}
