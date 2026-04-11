const std = @import("std");
const anchor = @import("tamga_vk3d.zig");
const VulkanContext = anchor.VulkanContext;

// ---- Light constants ----

pub const MAX_LIGHTS: u32 = 256;
pub const MAX_DIR_LIGHTS: u32 = 4;
pub const MAX_POINT_LIGHTS: u32 = 126;
pub const MAX_SPOT_LIGHTS: u32 = 126;

pub const LIGHT_TYPE_DIRECTIONAL: f32 = 0.0;
pub const LIGHT_TYPE_POINT: f32 = 1.0;
pub const LIGHT_TYPE_SPOT: f32 = 2.0;

// ---- Light data (std430 layout, matches mesh.frag.glsl LightSSBO) ----
// Unified light struct: type field distinguishes directional/point/spot.
// 80 bytes per light (5 x vec4).

pub const LightData = extern struct {
    position_range: [4]f32 = [_]f32{0.0} ** 4, // xyz = position, w = range
    direction_type: [4]f32 = [_]f32{0.0} ** 4, // xyz = direction, w = type (0/1/2)
    color: [4]f32 = [_]f32{0.0} ** 4, // rgb = color, w unused
    attenuation: [4]f32 = [4]f32{ 1.0, 0.0, 0.0, 0.0 }, // constant, linear, quadratic, unused
    spot_params: [4]f32 = [_]f32{0.0} ** 4, // cos(inner), cos(outer), unused, unused
};

// SSBO header (16 bytes, matches shader layout)
pub const LightSSBOHeader = extern struct {
    num_lights: i32 = 0,
    _pad: [3]i32 = [_]i32{0} ** 3,
};

// flushLightSSBO packs the pending per-type light arrays into the flat SSBO.
// Layout: [header (16 bytes)] [dir lights] [point lights] [spot lights]
pub fn flushLightSSBO(ctx: *VulkanContext, frame: u32) void {
    const mapped = ctx.light_mapped[frame];
    const header_size = @sizeOf(LightSSBOHeader);
    const light_size = @sizeOf(LightData);
    var offset: u32 = 0;

    // Copy directional lights
    var i: u32 = 0;
    while (i < ctx.num_dir_lights) : (i += 1) {
        const dst_start = header_size + offset * light_size;
        @memcpy(mapped[dst_start .. dst_start + light_size], std.mem.asBytes(&ctx.pending_dir_lights[i]));
        offset += 1;
    }

    // Copy point lights
    i = 0;
    while (i < ctx.num_point_lights) : (i += 1) {
        const dst_start = header_size + offset * light_size;
        @memcpy(mapped[dst_start .. dst_start + light_size], std.mem.asBytes(&ctx.pending_point_lights[i]));
        offset += 1;
    }

    // Copy spot lights
    i = 0;
    while (i < ctx.num_spot_lights) : (i += 1) {
        const dst_start = header_size + offset * light_size;
        @memcpy(mapped[dst_start .. dst_start + light_size], std.mem.asBytes(&ctx.pending_spot_lights[i]));
        offset += 1;
    }

    // Write header
    const header = LightSSBOHeader{ .num_lights = @intCast(offset) };
    @memcpy(mapped[0..header_size], std.mem.asBytes(&header));
}
