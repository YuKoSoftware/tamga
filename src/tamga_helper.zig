// Zig sidecar for the main/tamga_test module.
// Provides helper bridge functions for test_vulkan.orh — raw float arrays
// for vertices, indices, and matrices that cannot be expressed as literals in Orhon.

const std = @import("std");

// ---- Triangle mesh data ----
// Standard D-05 vertex format: vec3 pos, vec3 normal, vec2 uv, vec4 color = 48 bytes
// Three CCW vertices forming a triangle in the XY plane.

const triangle_vertices = [3 * 12]f32{
    // Vertex 0: bottom-left (red)
    // pos          normal          uv       color
    -0.5, -0.5, 0.0,  0.0, 0.0, 1.0,  0.0, 0.0,  1.0, 0.0, 0.0, 1.0,
    // Vertex 1: bottom-right (green)
     0.5, -0.5, 0.0,  0.0, 0.0, 1.0,  1.0, 0.0,  0.0, 1.0, 0.0, 1.0,
    // Vertex 2: top-center (blue)
     0.0,  0.5, 0.0,  0.0, 0.0, 1.0,  0.5, 1.0,  0.0, 0.0, 1.0, 1.0,
};

const triangle_indices = [3]u32{ 0, 1, 2 };

// ---- Identity matrix (column-major) ----

const identity_matrix = [16]f32{
    1.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0,
    0.0, 0.0, 0.0, 1.0,
};

// ---- Camera data ----
// Camera at (0, 0, 3) looking at origin, up = (0, 1, 0).
// View matrix = look-at: translation by -eye along Z axis.

const camera_pos = [3]f32{ 0.0, 0.0, 3.0 };

// View matrix: camera at (0,0,3), looking at origin.
// Row-major representation (Zig), but stored column-major for Vulkan/GLSL.
// For a camera at Z=3 looking toward -Z: translate by (0, 0, -3).
const view_matrix = [16]f32{
    1.0, 0.0,  0.0, 0.0, // column 0
    0.0, 1.0,  0.0, 0.0, // column 1
    0.0, 0.0,  1.0, 0.0, // column 2
    0.0, 0.0, -3.0, 1.0, // column 3: translation
};

// Perspective projection matrix for 800x600, FOV=45deg, near=0.1, far=100.
// Vulkan NDC: Y-axis flipped vs OpenGL (proj[5] is negative).
// f = 1/tan(fovY/2) = 1/tan(pi/8) ≈ 2.4142
// aspect = 800/600 ≈ 1.3333
// proj[0] = f/aspect ≈ 1.8106
// proj[5] = -f ≈ -2.4142    (Vulkan Y flip)
// proj[10] = far/(near-far) = 100/(-99.9) ≈ -1.001001
// proj[14] = near*far/(near-far) = 10/(-99.9) ≈ -0.100100
// proj[11] = -1
const proj_matrix = [16]f32{
    1.8106, 0.0,      0.0,       0.0, // column 0
    0.0,   -2.4142,   0.0,       0.0, // column 1
    0.0,    0.0,     -1.001001,  -1.0, // column 2 (proj[11]=-1 for perspective divide)
    0.0,    0.0,     -0.100100,   0.0, // column 3
};

// ---- Bridge export functions ----
// Called from test_vulkan.orh via `bridge func` declarations.

pub fn getTriangleVertices() usize {
    return @intFromPtr(&triangle_vertices);
}

pub fn getTriangleIndices() usize {
    return @intFromPtr(&triangle_indices);
}

pub fn getViewMatrix() usize {
    return @intFromPtr(&view_matrix);
}

pub fn getProjMatrix() usize {
    return @intFromPtr(&proj_matrix);
}

pub fn getCameraPos() usize {
    return @intFromPtr(&camera_pos);
}

pub fn getIdentityMatrix() usize {
    return @intFromPtr(&identity_matrix);
}
