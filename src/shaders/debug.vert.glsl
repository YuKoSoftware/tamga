#version 450

// Simplified vertex format for debug geometry (lines, AABBs)
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec4 inColor;

// Push constants — per-draw model matrix (D-10)
layout(push_constant) uniform PushConstants {
    mat4 model;
} pc;

// Set 0, Binding 0 — camera UBO, per-frame (same layout as mesh shaders)
layout(set = 0, binding = 0) uniform CameraUBO {
    mat4 view;
    mat4 proj;
    vec3 viewPos;
} camera;

// Output to fragment shader
layout(location = 0) out vec4 fragColor;

void main() {
    gl_Position = camera.proj * camera.view * pc.model * vec4(inPosition, 1.0);
    fragColor   = inColor;
}
