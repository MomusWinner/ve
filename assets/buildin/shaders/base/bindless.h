#ifndef BUILDIN_BINDLESS_H
#define BUILDIN_BINDLESS_H

#extension GL_EXT_nonuniform_qualifier : enable

#define BindlessDescriptorSet 0

#define BindlessUniformBinding 0
#define BindlessStorageBinding 1
#define BindlessSamplerBinding 2
#define BindlessComputeBinding 3

#define GetLayoutVariableName(Name) u##Name##Register

// Register unifrom buffer
#define RegisterUniform(Name, Struct) \
	layout(std140, set = BindlessDescriptorSet, binding = BindlessUniformBinding) \
	uniform Name Struct \
	GetLayoutVariableName(Name)[]

// Register storage buffer
#define RegisterBuffer(Layout, BufferAccess, Name, Struct) \
	layout(Layout, set = BindlessDescriptorSet, binding = BindlessStorageBinding) \
	BufferAccess buffer Name Struct GetLayoutVariableName(Name)[]

#define GetResource(Name, Index) \
    GetLayoutVariableName(Name)[Index]

RegisterUniform(DummyUniform, {uint ignore; });
RegisterBuffer(std430, readonly, DummyBuffer, { uint ignore; });

layout(set = BindlessDescriptorSet, binding = BindlessSamplerBinding) \
    uniform sampler2D uGlobalTextures2D[];

layout(set = BindlessDescriptorSet, binding = BindlessSamplerBinding) \
    uniform samplerCube uGlobalTexturesCube[];


const uint MAX_SLOT_COUNT = 10;

layout( push_constant ) uniform constants {
	mat4 model;
	uint camera;
	uint material;
	uint reserve0;
	uint reserve1;
	uint reserve2;
	uint reserve3;
	uint[MAX_SLOT_COUNT] slots;
} PushConstants;

#define gHandle(slot) PushConstants.slots[slot]

RegisterUniform(Model, {
	mat4 model;
});

#define getModel() PushConstants.model

RegisterUniform(Camera, {
	mat4 view;
	mat4 projection;
	vec3 position;
	float pad0;
});

#define getCameraByHandle(index) GetResource(Camera, index)

#define getCamera() getCameraByHandle(PushConstants.camera)

// HELPERS
//
const uint INVALID_RESOURCE_HANDLE = ~0u;

#define isHandleValid(handle)\
	(handle != INVALID_RESOURCE_INDEX)

#endif
