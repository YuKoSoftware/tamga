const std = @import("std");
const vma = @import("tamga_vulkan");
const c = @import("vulkan_c").c;
const anchor = @import("tamga_vk3d.zig");
const VulkanContext = anchor.VulkanContext;
const VkBridgeError = anchor.VkBridgeError;
const descriptors = @import("_vk3d_descriptors.zig");

// stb_image: single-header C library for PNG/JPG/BMP texture loading.
// Implementation is compiled via stb_image_impl.c (added as a C source via #cimport source:).
// Using extern declarations avoids the @cImport path-resolution issue in the generated bridge:
// the bridge file lives in .orh-cache/generated/ and cannot resolve relative "libs/stb_image.h".
const stbi = struct {
    pub extern fn stbi_load(filename: [*:0]const u8, x: *c_int, y: *c_int, comp: *c_int, req_comp: c_int) ?[*]u8;
    pub extern fn stbi_image_free(retval_from_stbi_load: ?[*]u8) void;
    pub extern fn stbi_failure_reason() [*:0]const u8;
};

// ---- MeshBuffers ----
// GPU vertex + index buffers for a mesh, allocated via VMA.

pub const MeshBuffers = struct {
    vertex_buffer: c.VkBuffer,
    vertex_allocation: vma.VmaAllocation,
    index_buffer: c.VkBuffer,
    index_allocation: vma.VmaAllocation,
    index_count: u32,
};

// ---- Texture ----
// GPU image + view + sampler, loaded from a file via stb_image.
// Created via Renderer.createTexture, destroyed via Renderer.destroyTexture.

pub const Texture = struct {
    image: c.VkImage,
    view: c.VkImageView,
    sampler: c.VkSampler,
    allocation: vma.VmaAllocation,
    width: u32,
    height: u32,
};

// ---- Material ----
// Descriptor set binding MaterialUBO (diffuse color, specular, shininess) and a Texture.
// Created via Renderer.createMaterial, destroyed via Renderer.destroyMaterial.

pub const Material = struct {
    descriptor_set: c.VkDescriptorSet,
    material_ubo: vma.BufferAlloc,
    material_mapped: [*]u8,
    texture: *const Texture,
};

// ---- one-shot command buffer submit helper ----

pub fn submitOneShot(ctx: *VulkanContext, cmd: c.VkCommandBuffer) void {
    _ = c.vkEndCommandBuffer(cmd);

    const submit_info = c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .pNext = null,
        .waitSemaphoreCount = 0,
        .pWaitSemaphores = null,
        .pWaitDstStageMask = null,
        .commandBufferCount = 1,
        .pCommandBuffers = &cmd,
        .signalSemaphoreCount = 0,
        .pSignalSemaphores = null,
    };

    _ = c.vkQueueSubmit(ctx.graphics_queue, 1, &submit_info, null);
    _ = c.vkQueueWaitIdle(ctx.graphics_queue);
    c.vkFreeCommandBuffers(ctx.device, ctx.command_pool, 1, &cmd);
}

pub fn beginOneShot(ctx: *VulkanContext) ?c.VkCommandBuffer {
    const alloc_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = ctx.command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };

    var cmd: c.VkCommandBuffer = null;
    if (c.vkAllocateCommandBuffers(ctx.device, &alloc_info, &cmd) != c.VK_SUCCESS) return null;

    const begin_info = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        .pInheritanceInfo = null,
    };
    _ = c.vkBeginCommandBuffer(cmd, &begin_info);
    return cmd;
}

// ---- image layout transition ----

pub fn transitionImageLayout(
    cmd: c.VkCommandBuffer,
    image: c.VkImage,
    old_layout: c.VkImageLayout,
    new_layout: c.VkImageLayout,
    src_stage: c.VkPipelineStageFlags,
    dst_stage: c.VkPipelineStageFlags,
    src_access: c.VkAccessFlags,
    dst_access: c.VkAccessFlags,
) void {
    const barrier = c.VkImageMemoryBarrier{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .pNext = null,
        .srcAccessMask = src_access,
        .dstAccessMask = dst_access,
        .oldLayout = old_layout,
        .newLayout = new_layout,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    c.vkCmdPipelineBarrier(cmd, src_stage, dst_stage, 0, 0, null, 0, null, 1, &barrier);
}

// ---- mesh buffer management ----

pub fn createMeshBuffers(
    ctx: *VulkanContext,
    vertices: [*]const u8,
    vertex_byte_size: u32,
    indices: [*]const u32,
    index_count: u32,
) anyerror!MeshBuffers {
    const index_byte_size: u32 = index_count * @sizeOf(u32);

    // Vertex buffer: GPU-local, requires staging upload
    const vertex_usage: u32 = 0x00000080 | 0x00000002; // VERTEX_BUFFER | TRANSFER_DST
    const vertex_alloc = try ctx.vma_ctx.createBuffer(vertex_byte_size, vertex_usage, true);

    // Index buffer: GPU-local, requires staging upload
    const index_usage: u32 = 0x00000100 | 0x00000002; // INDEX_BUFFER | TRANSFER_DST
    const index_alloc = try ctx.vma_ctx.createBuffer(index_byte_size, index_usage, true);

    // Upload vertex data via staging ring
    const vert_region = try ctx.vma_ctx.stagingWrite(vertices, vertex_byte_size);

    // Upload index data via staging ring
    const idx_bytes: [*]const u8 = @ptrCast(indices);
    const index_region = try ctx.vma_ctx.stagingWrite(idx_bytes, index_byte_size);

    // Record copy commands in a one-shot command buffer
    const cmd = beginOneShot(ctx) orelse return VkBridgeError.VulkanFailed;

    // Copy vertex data
    const vert_copy = c.VkBufferCopy{
        .srcOffset = vert_region.offset,
        .dstOffset = 0,
        .size = vertex_byte_size,
    };
    c.vkCmdCopyBuffer(cmd, vert_region.buffer, vertex_alloc.buffer, 1, &vert_copy);

    // Copy index data
    const index_copy = c.VkBufferCopy{
        .srcOffset = index_region.offset,
        .dstOffset = 0,
        .size = index_byte_size,
    };
    c.vkCmdCopyBuffer(cmd, index_region.buffer, index_alloc.buffer, 1, &index_copy);

    submitOneShot(ctx, cmd);

    return MeshBuffers{
        .vertex_buffer = vertex_alloc.buffer,
        .vertex_allocation = vertex_alloc.allocation,
        .index_buffer = index_alloc.buffer,
        .index_allocation = index_alloc.allocation,
        .index_count = index_count,
    };
}

// ---- texture creation and destruction ----

pub fn textureLoad(ctx: *VulkanContext, path: [*:0]const u8) anyerror!Texture {
    // Load image via stb_image, forcing RGBA (4 channels)
    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;
    const pixels = stbi.stbi_load(path, &width, &height, &channels, 4);
    if (pixels == null) {
        std.debug.print("[TamgaVK3D] stbi_load failed: {s}\n", .{path});
        return VkBridgeError.VulkanFailed;
    }
    defer stbi.stbi_image_free(pixels);

    const w: u32 = @intCast(width);
    const h: u32 = @intCast(height);
    const image_size: u32 = w * h * 4;

    // Write pixel data to staging ring
    const staging_region = try ctx.vma_ctx.stagingWrite(@ptrCast(pixels), image_size);

    // Create device-local VkImage via VMA (TRANSFER_DST | SAMPLED, R8G8B8A8_SRGB)
    const image_usage: c.VkImageUsageFlags = c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT;
    const image_alloc = try ctx.vma_ctx.createImage(w, h, c.VK_FORMAT_R8G8B8A8_SRGB, image_usage, true);

    // Transition: UNDEFINED -> TRANSFER_DST_OPTIMAL, then copy, then SHADER_READ_ONLY_OPTIMAL
    const cmd = beginOneShot(ctx) orelse return VkBridgeError.VulkanFailed;

    transitionImageLayout(
        cmd,
        image_alloc.image,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        c.VK_PIPELINE_STAGE_TRANSFER_BIT,
        0,
        c.VK_ACCESS_TRANSFER_WRITE_BIT,
    );

    const buffer_image_copy = c.VkBufferImageCopy{
        .bufferOffset = staging_region.offset,
        .bufferRowLength = 0,
        .bufferImageHeight = 0,
        .imageSubresource = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .mipLevel = 0,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
        .imageExtent = .{ .width = w, .height = h, .depth = 1 },
    };
    c.vkCmdCopyBufferToImage(
        cmd,
        staging_region.buffer,
        image_alloc.image,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        1,
        &buffer_image_copy,
    );

    transitionImageLayout(
        cmd,
        image_alloc.image,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        c.VK_PIPELINE_STAGE_TRANSFER_BIT,
        c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        c.VK_ACCESS_TRANSFER_WRITE_BIT,
        c.VK_ACCESS_SHADER_READ_BIT,
    );

    submitOneShot(ctx, cmd);

    // Create VkImageView (R8G8B8A8_SRGB, COLOR aspect)
    const view_info = c.VkImageViewCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .image = image_alloc.image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = c.VK_FORMAT_R8G8B8A8_SRGB,
        .components = .{
            .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
        },
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    var view: c.VkImageView = null;
    if (c.vkCreateImageView(ctx.device, &view_info, null, &view) != c.VK_SUCCESS) {
        ctx.vma_ctx.destroyImage(image_alloc.image, image_alloc.allocation);
        return VkBridgeError.VulkanFailed;
    }

    // Create VkSampler (LINEAR filter, REPEAT address mode)
    const sampler_info = c.VkSamplerCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .magFilter = c.VK_FILTER_LINEAR,
        .minFilter = c.VK_FILTER_LINEAR,
        .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
        .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .mipLodBias = 0.0,
        .anisotropyEnable = c.VK_FALSE,
        .maxAnisotropy = 1.0,
        .compareEnable = c.VK_FALSE,
        .compareOp = c.VK_COMPARE_OP_ALWAYS,
        .minLod = 0.0,
        .maxLod = 0.0,
        .borderColor = c.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
        .unnormalizedCoordinates = c.VK_FALSE,
    };

    var sampler: c.VkSampler = null;
    if (c.vkCreateSampler(ctx.device, &sampler_info, null, &sampler) != c.VK_SUCCESS) {
        c.vkDestroyImageView(ctx.device, view, null);
        ctx.vma_ctx.destroyImage(image_alloc.image, image_alloc.allocation);
        return VkBridgeError.VulkanFailed;
    }

    return Texture{
        .image = image_alloc.image,
        .view = view,
        .sampler = sampler,
        .allocation = image_alloc.allocation,
        .width = w,
        .height = h,
    };
}

pub fn textureFree(ctx: *VulkanContext, tex: *Texture) void {
    if (tex.sampler != null) c.vkDestroySampler(ctx.device, tex.sampler, null);
    if (tex.view != null) c.vkDestroyImageView(ctx.device, tex.view, null);
    ctx.vma_ctx.destroyImage(tex.image, tex.allocation);
}

// createDefaultTexture creates a 1x1 white RGBA texture for materials with no texture assigned.
pub fn textureCreateDefault(ctx: *VulkanContext) anyerror!Texture {
    // 1x1 white pixel: R=255, G=255, B=255, A=255
    var pixels = [4]u8{ 255, 255, 255, 255 };
    const staging_region = try ctx.vma_ctx.stagingWrite(&pixels, 4);

    const image_usage: c.VkImageUsageFlags = c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT;
    const image_alloc = try ctx.vma_ctx.createImage(1, 1, c.VK_FORMAT_R8G8B8A8_SRGB, image_usage, true);

    const cmd = beginOneShot(ctx) orelse return VkBridgeError.VulkanFailed;

    transitionImageLayout(
        cmd,
        image_alloc.image,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        c.VK_PIPELINE_STAGE_TRANSFER_BIT,
        0,
        c.VK_ACCESS_TRANSFER_WRITE_BIT,
    );

    const buffer_image_copy = c.VkBufferImageCopy{
        .bufferOffset = staging_region.offset,
        .bufferRowLength = 0,
        .bufferImageHeight = 0,
        .imageSubresource = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .mipLevel = 0,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
        .imageExtent = .{ .width = 1, .height = 1, .depth = 1 },
    };
    c.vkCmdCopyBufferToImage(
        cmd,
        staging_region.buffer,
        image_alloc.image,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        1,
        &buffer_image_copy,
    );

    transitionImageLayout(
        cmd,
        image_alloc.image,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        c.VK_PIPELINE_STAGE_TRANSFER_BIT,
        c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        c.VK_ACCESS_TRANSFER_WRITE_BIT,
        c.VK_ACCESS_SHADER_READ_BIT,
    );

    submitOneShot(ctx, cmd);

    const view_info = c.VkImageViewCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .image = image_alloc.image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = c.VK_FORMAT_R8G8B8A8_SRGB,
        .components = .{
            .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
        },
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    var view: c.VkImageView = null;
    if (c.vkCreateImageView(ctx.device, &view_info, null, &view) != c.VK_SUCCESS) {
        ctx.vma_ctx.destroyImage(image_alloc.image, image_alloc.allocation);
        return VkBridgeError.VulkanFailed;
    }

    const sampler_info = c.VkSamplerCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .magFilter = c.VK_FILTER_NEAREST,
        .minFilter = c.VK_FILTER_NEAREST,
        .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_NEAREST,
        .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .mipLodBias = 0.0,
        .anisotropyEnable = c.VK_FALSE,
        .maxAnisotropy = 1.0,
        .compareEnable = c.VK_FALSE,
        .compareOp = c.VK_COMPARE_OP_ALWAYS,
        .minLod = 0.0,
        .maxLod = 0.0,
        .borderColor = c.VK_BORDER_COLOR_INT_OPAQUE_WHITE,
        .unnormalizedCoordinates = c.VK_FALSE,
    };

    var sampler: c.VkSampler = null;
    if (c.vkCreateSampler(ctx.device, &sampler_info, null, &sampler) != c.VK_SUCCESS) {
        c.vkDestroyImageView(ctx.device, view, null);
        ctx.vma_ctx.destroyImage(image_alloc.image, image_alloc.allocation);
        return VkBridgeError.VulkanFailed;
    }

    return Texture{
        .image = image_alloc.image,
        .view = view,
        .sampler = sampler,
        .allocation = image_alloc.allocation,
        .width = 1,
        .height = 1,
    };
}

// ---- material creation and destruction ----

pub fn materialCreate(
    ctx: *VulkanContext,
    diffuse_r: f32,
    diffuse_g: f32,
    diffuse_b: f32,
    diffuse_a: f32,
    specular: f32,
    shininess: f32,
    texture: *const Texture,
) anyerror!Material {
    const ubo_usage: u32 = 0x00000010; // VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT

    // Allocate material UBO (host-visible, persistently mapped)
    const mat_alloc = try ctx.vma_ctx.createBuffer(@sizeOf(descriptors.MaterialUBOData), ubo_usage, false);
    const mat_mapped = ctx.vma_ctx.mapBuffer(mat_alloc.allocation) orelse {
        ctx.vma_ctx.destroyBuffer(mat_alloc.buffer, mat_alloc.allocation);
        return VkBridgeError.VulkanFailed;
    };

    // Write initial MaterialUBO data
    const ubo_data = descriptors.MaterialUBOData{
        .diffuse_color = [4]f32{ diffuse_r, diffuse_g, diffuse_b, diffuse_a },
        .specular = specular,
        .shininess = shininess,
    };
    @memcpy(mat_mapped[0..@sizeOf(descriptors.MaterialUBOData)], std.mem.asBytes(&ubo_data));

    // Allocate descriptor set from pool using Set 1 layout (MaterialUBO + sampler)
    const alloc_info = c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = null,
        .descriptorPool = ctx.descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &ctx.descriptor_set_layout_1,
    };

    var desc_set: c.VkDescriptorSet = null;
    if (c.vkAllocateDescriptorSets(ctx.device, &alloc_info, &desc_set) != c.VK_SUCCESS) {
        ctx.vma_ctx.unmapBuffer(mat_alloc.allocation);
        ctx.vma_ctx.destroyBuffer(mat_alloc.buffer, mat_alloc.allocation);
        return VkBridgeError.VulkanFailed;
    }

    // Write descriptor set: binding 0 = MaterialUBO, binding 1 = texture sampler+view
    const buf_info = c.VkDescriptorBufferInfo{
        .buffer = mat_alloc.buffer,
        .offset = 0,
        .range = @sizeOf(descriptors.MaterialUBOData),
    };

    const img_info = c.VkDescriptorImageInfo{
        .sampler = texture.sampler,
        .imageView = texture.view,
        .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    };

    const writes = [2]c.VkWriteDescriptorSet{
        .{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .pNext = null,
            .dstSet = desc_set,
            .dstBinding = 0,
            .dstArrayElement = 0,
            .descriptorCount = 1,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .pImageInfo = null,
            .pBufferInfo = &buf_info,
            .pTexelBufferView = null,
        },
        .{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .pNext = null,
            .dstSet = desc_set,
            .dstBinding = 1,
            .dstArrayElement = 0,
            .descriptorCount = 1,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImageInfo = &img_info,
            .pBufferInfo = null,
            .pTexelBufferView = null,
        },
    };

    c.vkUpdateDescriptorSets(ctx.device, 2, &writes, 0, null);

    return Material{
        .descriptor_set = desc_set,
        .material_ubo = mat_alloc,
        .material_mapped = mat_mapped,
        .texture = texture,
    };
}

pub fn materialFree(ctx: *VulkanContext, mat: *Material) void {
    ctx.vma_ctx.unmapBuffer(mat.material_ubo.allocation);
    ctx.vma_ctx.destroyBuffer(mat.material_ubo.buffer, mat.material_ubo.allocation);
    // descriptor set is freed with the pool — no explicit free needed
}

// ---- slot maps ----
// Fixed-size arrays keyed by u32 ID. IDs are returned to Orhon as MeshId/TextureId/MaterialId.
// Null slots mean free; allocation is a linear scan for the first free slot.

pub const MAX_MESHES: u32 = 256;
pub const MAX_TEXTURES: u32 = 256;
pub const MAX_MATERIALS: u32 = 256;

pub var mesh_slots: [MAX_MESHES]?MeshBuffers = [_]?MeshBuffers{null} ** MAX_MESHES;
pub var texture_slots: [MAX_TEXTURES]?Texture = [_]?Texture{null} ** MAX_TEXTURES;
pub var material_slots: [MAX_MATERIALS]?Material = [_]?Material{null} ** MAX_MATERIALS;

pub fn allocMeshSlot(mesh: MeshBuffers) ?u32 {
    for (&mesh_slots, 0..) |*slot, i| {
        if (slot.* == null) {
            slot.* = mesh;
            return @intCast(i);
        }
    }
    return null;
}

pub fn freeMeshSlot(id: u32) void {
    if (id < MAX_MESHES) mesh_slots[id] = null;
}

pub fn getMesh(id: u32) ?*MeshBuffers {
    if (id >= MAX_MESHES) return null;
    if (mesh_slots[id]) |*m| return m;
    return null;
}

pub fn allocTextureSlot(tex: Texture) ?u32 {
    for (&texture_slots, 0..) |*slot, i| {
        if (slot.* == null) {
            slot.* = tex;
            return @intCast(i);
        }
    }
    return null;
}

pub fn freeTextureSlot(id: u32) void {
    if (id < MAX_TEXTURES) texture_slots[id] = null;
}

pub fn getTexture(id: u32) ?*Texture {
    if (id >= MAX_TEXTURES) return null;
    if (texture_slots[id]) |*t| return t;
    return null;
}

pub fn allocMaterialSlot(mat: Material) ?u32 {
    for (&material_slots, 0..) |*slot, i| {
        if (slot.* == null) {
            slot.* = mat;
            return @intCast(i);
        }
    }
    return null;
}

pub fn freeMaterialSlot(id: u32) void {
    if (id < MAX_MATERIALS) material_slots[id] = null;
}

pub fn getMaterial(id: u32) ?*Material {
    if (id >= MAX_MATERIALS) return null;
    if (material_slots[id]) |*m| return m;
    return null;
}
