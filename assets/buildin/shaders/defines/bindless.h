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


layout( push_constant ) uniform constants {
	uint camera;
	uint model;
	uint material;
} PushConstants;


// layout(set = 1, binding = 0) uniform DrawParameters {
//   uint meshTransforms;
//   uint pointLights;
//   uint camera;
//   // Don't forget the padding
//   uint texture;
// } uDrawParameters;

// RegisterUniform(Transform, {
//     mat4 model;
//     mat4 view;
//     mat4 proj;
// });
//
// #define getTransform() GetResource(Transform, 0) // TODO


RegisterUniform(Model, {
    mat4 model;
});

#define getModel() GetResource(Model, PushConstants.model)

RegisterUniform(Material, {
	vec4 color;
	uint texture;
	// uint pad0; // TODO:
	// uint pad1;
	// uint pad2;
});

#define getMaterial() GetResource(Material, PushConstants.material)

RegisterUniform(Camera, {
    mat4 view;
    mat4 projection;
});

#define getCamera() GetResource(Camera, PushConstants.camera)
