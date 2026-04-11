const std = @import("std");
const vma = @import("tamga_vulkan");
const c = @import("vulkan_c").c;
const anchor = @import("tamga_vk3d.zig");
const VulkanContext = anchor.VulkanContext;
const lighting = @import("_vk3d_lighting.zig");

const MAX_FRAMES_IN_FLIGHT: u32 = 2;
const VkBridgeError = anchor.VkBridgeError;

// ---- CameraUBO (std140 layout, 144 bytes) ----
// view: 64 bytes, proj: 64 bytes, view_pos: 12 bytes, _pad: 4 bytes

pub const CameraUBO = extern struct {
    view: [16]f32,
    proj: [16]f32,
    view_pos: [3]f32,
    _pad: f32 = 0.0,
};

// ---- MaterialUBOData (std140 layout, matches mesh.frag.glsl exactly) ----
// diffuseColor vec4 (16) + specular f32 (4) + shininess f32 (4) + pad (8) = 32 bytes

pub const MaterialUBOData = extern struct {
    diffuse_color: [4]f32 = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
    specular: f32 = 0.5,
    shininess: f32 = 32.0,
    _pad: [2]f32 = [_]f32{0.0} ** 2,
};

// ---- descriptor set layouts ----

pub fn createDescriptorSetLayouts(ctx: *VulkanContext) c.VkResult {
    // Set 0 (per-frame): binding 0 = CameraUBO, binding 1 = LightSSBO
    // Accessible from VERTEX + FRAGMENT + COMPUTE (shared between graphics and compute passes)
    {
        const bindings = [2]c.VkDescriptorSetLayoutBinding{
            .{
                .binding = 0,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = 1,
                .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT | c.VK_SHADER_STAGE_COMPUTE_BIT,
                .pImmutableSamplers = null,
            },
            .{
                .binding = 1,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .descriptorCount = 1,
                .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT | c.VK_SHADER_STAGE_COMPUTE_BIT,
                .pImmutableSamplers = null,
            },
        };

        const layout_info = c.VkDescriptorSetLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .bindingCount = 2,
            .pBindings = &bindings,
        };

        const result = c.vkCreateDescriptorSetLayout(ctx.device, &layout_info, null, &ctx.descriptor_set_layout_0);
        if (result != c.VK_SUCCESS) return result;
    }

    // Set 1 (per-material): binding 0 = MaterialUBO (FRAGMENT), binding 1 = sampler2D (FRAGMENT)
    {
        const bindings = [2]c.VkDescriptorSetLayoutBinding{
            .{
                .binding = 0,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = 1,
                .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                .pImmutableSamplers = null,
            },
            .{
                .binding = 1,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .descriptorCount = 1,
                .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                .pImmutableSamplers = null,
            },
        };

        const layout_info = c.VkDescriptorSetLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .bindingCount = 2,
            .pBindings = &bindings,
        };

        const result = c.vkCreateDescriptorSetLayout(ctx.device, &layout_info, null, &ctx.descriptor_set_layout_1);
        if (result != c.VK_SUCCESS) return result;
    }

    return c.VK_SUCCESS;
}

// ---- UBO management ----

pub fn createUBOs(ctx: *VulkanContext) anyerror!void {
    const ubo_usage: u32 = 0x00000010; // VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT
    const ssbo_usage: u32 = 0x00000020; // VK_BUFFER_USAGE_STORAGE_BUFFER_BIT

    // Light SSBO size: header (16 bytes) + MAX_LIGHTS * LightData (80 bytes each)
    ctx.light_ssbo_size = @sizeOf(lighting.LightSSBOHeader) + lighting.MAX_LIGHTS * @sizeOf(lighting.LightData);

    var i: u32 = 0;
    while (i < MAX_FRAMES_IN_FLIGHT) : (i += 1) {
        // Camera UBO — host-visible + persistently mapped
        const cam_alloc = try ctx.vma_ctx.createBuffer(@sizeOf(CameraUBO), ubo_usage, false);
        ctx.camera_ubos[i] = cam_alloc;
        ctx.camera_mapped[i] = ctx.vma_ctx.mapBuffer(cam_alloc.allocation) orelse return VkBridgeError.VulkanFailed;

        // Light SSBO — host-visible + persistently mapped
        const light_alloc = try ctx.vma_ctx.createBuffer(ctx.light_ssbo_size, ssbo_usage, false);
        ctx.light_ssbos[i] = light_alloc;
        ctx.light_mapped[i] = ctx.vma_ctx.mapBuffer(light_alloc.allocation) orelse return VkBridgeError.VulkanFailed;

        // Zero the SSBO (no lights active by default)
        const header = lighting.LightSSBOHeader{};
        @memcpy(ctx.light_mapped[i][0..@sizeOf(lighting.LightSSBOHeader)], std.mem.asBytes(&header));
    }

    ctx.ubos_initialized = true;
}

pub fn destroyUBOs(ctx: *VulkanContext) void {
    if (!ctx.ubos_initialized) return;
    var i: u32 = 0;
    while (i < MAX_FRAMES_IN_FLIGHT) : (i += 1) {
        ctx.vma_ctx.unmapBuffer(ctx.camera_ubos[i].allocation);
        ctx.vma_ctx.destroyBuffer(ctx.camera_ubos[i].buffer, ctx.camera_ubos[i].allocation);
        ctx.vma_ctx.unmapBuffer(ctx.light_ssbos[i].allocation);
        ctx.vma_ctx.destroyBuffer(ctx.light_ssbos[i].buffer, ctx.light_ssbos[i].allocation);
    }
    ctx.ubos_initialized = false;
}

// ---- descriptor pool and per-frame sets ----

pub fn createDescriptorPool(ctx: *VulkanContext) c.VkResult {
    // Size the pool generously to avoid VK_ERROR_OUT_OF_POOL_MEMORY
    const pool_sizes = [3]c.VkDescriptorPoolSize{
        .{
            .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 16,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 8,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 64,
        },
    };

    const pool_info = c.VkDescriptorPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .maxSets = MAX_FRAMES_IN_FLIGHT + 16,
        .poolSizeCount = 3,
        .pPoolSizes = &pool_sizes,
    };

    return c.vkCreateDescriptorPool(ctx.device, &pool_info, null, &ctx.descriptor_pool);
}

pub fn allocatePerFrameDescriptorSets(ctx: *VulkanContext) c.VkResult {
    var layouts: [MAX_FRAMES_IN_FLIGHT]c.VkDescriptorSetLayout = [_]c.VkDescriptorSetLayout{null} ** MAX_FRAMES_IN_FLIGHT;
    var i: u32 = 0;
    while (i < MAX_FRAMES_IN_FLIGHT) : (i += 1) {
        layouts[i] = ctx.descriptor_set_layout_0;
    }

    const alloc_info = c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = null,
        .descriptorPool = ctx.descriptor_pool,
        .descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
        .pSetLayouts = &layouts,
    };

    const result = c.vkAllocateDescriptorSets(ctx.device, &alloc_info, &ctx.descriptor_sets_0);
    if (result != c.VK_SUCCESS) return result;

    // Write camera UBO and light SSBO bindings for each frame
    i = 0;
    while (i < MAX_FRAMES_IN_FLIGHT) : (i += 1) {
        const cam_buf_info = c.VkDescriptorBufferInfo{
            .buffer = ctx.camera_ubos[i].buffer,
            .offset = 0,
            .range = @sizeOf(CameraUBO),
        };

        const light_buf_info = c.VkDescriptorBufferInfo{
            .buffer = ctx.light_ssbos[i].buffer,
            .offset = 0,
            .range = ctx.light_ssbo_size,
        };

        const writes = [2]c.VkWriteDescriptorSet{
            .{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = null,
                .dstSet = ctx.descriptor_sets_0[i],
                .dstBinding = 0,
                .dstArrayElement = 0,
                .descriptorCount = 1,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .pImageInfo = null,
                .pBufferInfo = &cam_buf_info,
                .pTexelBufferView = null,
            },
            .{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = null,
                .dstSet = ctx.descriptor_sets_0[i],
                .dstBinding = 1,
                .dstArrayElement = 0,
                .descriptorCount = 1,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .pImageInfo = null,
                .pBufferInfo = &light_buf_info,
                .pTexelBufferView = null,
            },
        };

        c.vkUpdateDescriptorSets(ctx.device, 2, &writes, 0, null);
    }

    return c.VK_SUCCESS;
}
