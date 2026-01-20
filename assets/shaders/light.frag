#version 450

#include "gen_types.h"
#include "buildin:defines/helper.h"

layout(location = 0) in vec2 fragTexCoord;
layout(location = 1) in vec4 fragColor;
layout(location = 2) in vec3 fragNormal;
layout(location = 3) in vec3 fragPos;
layout(location = 4) in vec4 fragPosLightSpace;

layout(location = 0) out vec4 outColor;

#define getShadowMap() uGlobalTextures2D[getUboLight(getMtrlLight().light_data).shadow] 

float textureProj(vec4 shadowCoord, vec2 off) {
	float shadow = 0;

	float dist = texture(getShadowMap(), shadowCoord.xy + off).r;

	if (dist  < shadowCoord.z) {
		shadow = 1;
	}

	if (shadowCoord.z > 1.0) {
		shadow = 0;
	}
	
	return shadow;
}

float filterPCF(vec4 sc) {
	ivec2 texDim = textureSize(getShadowMap(), 0);
	float scale = 1;
	float dx = scale * 1.0 / float(texDim.x);
	float dy = scale * 1.0 / float(texDim.y);

	float shadowFactor = 0.0;
	int count = 0;
	int range = 2;
	
	for (int x = -range; x <= range; x++) {
		for (int y = -range; y <= range; y++) {
			shadowFactor += textureProj(sc, vec2(dx*x, dy*y));
			count++;
		}
	}

	return shadowFactor / count;
}

void main() {
	// float shadow = textureProj(fragPosLightSpace / fragPosLightSpace.w, vec2(0.0,0.0));
	float shadow = filterPCF(fragPosLightSpace / fragPosLightSpace.w);

	vec3 color = getMtrlLight().diffuse;
	vec3 normal = normalize(fragNormal);
	vec3 lightColor = getUboLight(getMtrlLight().light_data).color;
	vec3 ambient = getMtrlLight().ambient * lightColor;
	// diffuse
	vec3 lightDir = normalize(-getUboLight(getMtrlLight().light_data).direction);
	float diff = max(dot(lightDir, normal), 0.0);
	vec3 diffuse = diff * lightColor;
	// specular
	vec3 viewDir = normalize(getMtrlLight().view_pos - fragPos);
	float spec = 0.0;
	vec3 halfwayDir = normalize(lightDir + viewDir);
	spec = pow(max(dot(normal, halfwayDir), 0.0), 64.0);
	vec3 specular = spec * lightColor;
	// calculate shadow
	vec3 lighting = (ambient + (1.0 - shadow) * (diffuse + specular)) * color;
	outColor = vec4(lighting, 1);
}
