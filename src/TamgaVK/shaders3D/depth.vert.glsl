#version 450

// Vertex inputs — same layout as mesh.vert for pipeline compatibility (D-05)
// Only position is consumed; normal/UV/color declared to keep the vertex binding compatible.
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inUV;
layout(location = 3) in vec4 inColor;

// Push constants — per-draw model matrix (D-10)
layout(push_constant) uniform PushConstants {
    mat4 model;
} pc;

// Set 0, Binding 0 — camera UBO, per-frame
layout(set = 0, binding = 0) uniform CameraUBO {
    mat4 view;
    mat4 proj;
    vec3 viewPos;
} camera;

void main() {
    gl_Position = camera.proj * camera.view * pc.model * vec4(inPosition, 1.0);
}
