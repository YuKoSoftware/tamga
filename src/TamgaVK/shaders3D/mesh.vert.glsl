#version 450

// Vertex inputs — fixed standard vertex format (D-05)
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inUV;
layout(location = 3) in vec4 inColor;

// Push constants — per-draw model matrix (D-10, max 64 bytes)
layout(push_constant) uniform PushConstants {
    mat4 model;
} pc;

// Set 0, Binding 0 — camera UBO, per-frame (Pattern 3)
layout(set = 0, binding = 0) uniform CameraUBO {
    mat4 view;
    mat4 proj;
    vec3 viewPos;
} camera;

// Outputs to fragment shader
layout(location = 0) out vec3 worldPos;
layout(location = 1) out vec3 worldNormal;
layout(location = 2) out vec2 fragUV;
layout(location = 3) out vec4 fragColor;

void main() {
    vec4 worldPosition = pc.model * vec4(inPosition, 1.0);

    gl_Position = camera.proj * camera.view * worldPosition;

    worldPos    = vec3(worldPosition);
    worldNormal = mat3(transpose(inverse(pc.model))) * inNormal;
    fragUV      = inUV;
    fragColor   = inColor;
}
