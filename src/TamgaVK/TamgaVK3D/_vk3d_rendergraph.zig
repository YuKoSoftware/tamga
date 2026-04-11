const std = @import("std");
const c = @import("vulkan_c").c;
const anchor = @import("tamga_vk3d.zig");
const VulkanContext = anchor.VulkanContext;
const pipeline = @import("_vk3d_pipeline.zig");

const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
});

// ---- draw call list ----
//
// draw() collects draw calls into a list. The render graph's forward pass
// callback iterates this list to record Vulkan commands. This allows the
// graph to control pass begin/end and insert barriers between passes.

pub const MAX_DRAW_CALLS: u32 = 256;

pub const DrawCall = struct {
    vertex_buffer: c.VkBuffer,
    index_buffer: c.VkBuffer,
    index_count: u32,
    material_descriptor_set: c.VkDescriptorSet,
    model_matrix: [16]f32,
};

// ---- depth prepass callback ----
// Called by the render graph. Renders all geometry depth-only (no color, no materials).

pub fn depthPrepassCallback(cmd: c.VkCommandBuffer, user_data: ?*anyopaque) void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(user_data orelse return));
    const frame = ctx.current_frame;

    const viewport = c.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(ctx.swapchain_extent.width),
        .height = @floatFromInt(ctx.swapchain_extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    const scissor = c.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = ctx.swapchain_extent,
    };
    c.vkCmdSetViewport(cmd, 0, 1, &viewport);
    c.vkCmdSetScissor(cmd, 0, 1, &scissor);

    // Bind depth pipeline and camera descriptor set (set 0 only — no materials needed)
    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.depth_pipeline);
    c.vkCmdBindDescriptorSets(
        cmd,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        ctx.pipeline_layout,
        0,
        1,
        &ctx.descriptor_sets_0[frame],
        0,
        null,
    );

    // Iterate draw list — vertex/index + model matrix push constant, no material binding
    var i: u32 = 0;
    while (i < ctx.draw_count) : (i += 1) {
        const dc = &ctx.draw_list[i];
        const offset: u64 = 0;
        c.vkCmdBindVertexBuffers(cmd, 0, 1, &dc.vertex_buffer, &offset);
        c.vkCmdBindIndexBuffer(cmd, dc.index_buffer, 0, c.VK_INDEX_TYPE_UINT32);
        c.vkCmdPushConstants(cmd, ctx.pipeline_layout, c.VK_SHADER_STAGE_VERTEX_BIT, 0, 64, &dc.model_matrix);
        c.vkCmdDrawIndexed(cmd, dc.index_count, 1, 0, 0, 0);
    }
}

// ---- forward pass callback ----
// Called by the render graph during execute(). Records all queued draw calls.

pub fn forwardPassCallback(cmd: c.VkCommandBuffer, user_data: ?*anyopaque) void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(user_data orelse return));
    const frame = ctx.current_frame;

    // Dynamic viewport and scissor
    const viewport = c.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(ctx.swapchain_extent.width),
        .height = @floatFromInt(ctx.swapchain_extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    const scissor = c.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = ctx.swapchain_extent,
    };
    c.vkCmdSetViewport(cmd, 0, 1, &viewport);
    c.vkCmdSetScissor(cmd, 0, 1, &scissor);

    // Bind forward pipeline and per-frame descriptor set (set 0: camera + lights)
    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.pipeline);
    c.vkCmdBindDescriptorSets(
        cmd,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        ctx.pipeline_layout,
        0,
        1,
        &ctx.descriptor_sets_0[frame],
        0,
        null,
    );

    // Execute queued draw calls
    var i: u32 = 0;
    while (i < ctx.draw_count) : (i += 1) {
        const dc = &ctx.draw_list[i];

        // Bind material descriptor set (set 1)
        c.vkCmdBindDescriptorSets(
            cmd,
            c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            ctx.pipeline_layout,
            1,
            1,
            &dc.material_descriptor_set,
            0,
            null,
        );

        const offset: u64 = 0;
        c.vkCmdBindVertexBuffers(cmd, 0, 1, &dc.vertex_buffer, &offset);
        c.vkCmdBindIndexBuffer(cmd, dc.index_buffer, 0, c.VK_INDEX_TYPE_UINT32);
        c.vkCmdPushConstants(cmd, ctx.pipeline_layout, c.VK_SHADER_STAGE_VERTEX_BIT, 0, 64, &dc.model_matrix);
        c.vkCmdDrawIndexed(cmd, dc.index_count, 1, 0, 0, 0);
    }
}

// ---- render graph setup ----
// Builds the render graph with a single forward pass.
// Called from Renderer.create and recreateSwapchain.

pub fn buildRenderGraph(ctx: *VulkanContext) void {
    ctx.graph.reset();

    // Pass 0: depth prepass — depth-only, populates depth buffer
    const depth_clear = [1]c.VkClearValue{
        .{ .depthStencil = .{ .depth = 1.0, .stencil = 0 } },
    };
    const depth_pass = ctx.graph.addGraphicsPass(.{
        .render_pass = ctx.depth_render_pass,
        .framebuffers = &ctx.depth_framebuffers,
        .extent = ctx.swapchain_extent,
        .clear_values = depth_clear[0..],
        .execute_fn = &depthPrepassCallback,
        .user_data = null, // set per-frame in endFrame
    });

    // Barrier: depth writes from prepass must be visible to forward pass depth reads
    ctx.graph.addImageBarrier(depth_pass, .{
        .image = ctx.depth_image,
        .old_layout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        .new_layout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        .src_stage = c.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
        .dst_stage = c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
        .src_access = c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        .dst_access = c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT,
        .aspect_mask = c.VK_IMAGE_ASPECT_DEPTH_BIT,
    });

    // Pass 1: forward shading — color + depth read (EQUAL test, zero overdraw)
    const fwd_clear = [3]c.VkClearValue{
        ctx.clear_color,
        .{ .depthStencil = .{ .depth = 1.0, .stencil = 0 } }, // unused (LOAD)
        ctx.clear_color, // unused (DONT_CARE)
    };
    _ = ctx.graph.addGraphicsPass(.{
        .render_pass = ctx.render_pass,
        .framebuffers = &ctx.framebuffers,
        .extent = ctx.swapchain_extent,
        .clear_values = fwd_clear[0..],
        .execute_fn = &forwardPassCallback,
        .user_data = null, // set per-frame in endFrame
    });
}

// ---- swapchain cleanup + recreation ----

pub fn cleanupSwapchain(ctx: *VulkanContext) void {
    // Destroy in reverse creation order:
    // 1. Framebuffers (forward + depth prepass)
    var i: u32 = 0;
    while (i < ctx.swapchain_image_count) : (i += 1) {
        if (ctx.framebuffers[i] != null) {
            c.vkDestroyFramebuffer(ctx.device, ctx.framebuffers[i], null);
            ctx.framebuffers[i] = null;
        }
        if (ctx.depth_framebuffers[i] != null) {
            c.vkDestroyFramebuffer(ctx.device, ctx.depth_framebuffers[i], null);
            ctx.depth_framebuffers[i] = null;
        }
    }

    // 2. MSAA color image + view (VMA free)
    pipeline.destroyMsaaColorResources(ctx);

    // 3. Depth image + view (VMA free)
    pipeline.destroyDepthResources(ctx);

    // 4. Swapchain image views
    i = 0;
    while (i < ctx.swapchain_image_count) : (i += 1) {
        if (ctx.swapchain_views[i] != null) {
            c.vkDestroyImageView(ctx.device, ctx.swapchain_views[i], null);
            ctx.swapchain_views[i] = null;
        }
    }

    // 5. Swapchain
    if (ctx.swapchain != null) {
        c.vkDestroySwapchainKHR(ctx.device, ctx.swapchain, null);
        ctx.swapchain = null;
    }
}

pub fn recreateSwapchain(ctx: *VulkanContext) bool {
    // handle minimized window
    var w: c_int = 0;
    var h: c_int = 0;
    _ = sdl.SDL_GetWindowSizeInPixels(ctx.sdl_window.?, &w, &h);
    if (w == 0 or h == 0) return false;

    _ = c.vkDeviceWaitIdle(ctx.device);

    const old_format = ctx.swapchain_format;
    cleanupSwapchain(ctx);

    // 1. Recreate swapchain + image views (updates swapchain_format and swapchain_extent)
    if (anchor.createSwapchain(ctx) != c.VK_SUCCESS) return false;

    // Handle format change: recreate render passes and pipelines if format changed (rare)
    if (ctx.swapchain_format != old_format) {
        if (ctx.render_pass != null) {
            c.vkDestroyRenderPass(ctx.device, ctx.render_pass, null);
            ctx.render_pass = null;
        }
        if (ctx.depth_render_pass != null) {
            c.vkDestroyRenderPass(ctx.device, ctx.depth_render_pass, null);
            ctx.depth_render_pass = null;
        }
        if (ctx.pipeline != null) {
            c.vkDestroyPipeline(ctx.device, ctx.pipeline, null);
            ctx.pipeline = null;
        }
        if (ctx.depth_pipeline != null) {
            c.vkDestroyPipeline(ctx.device, ctx.depth_pipeline, null);
            ctx.depth_pipeline = null;
        }
        if (pipeline.createDepthRenderPass(ctx) != c.VK_SUCCESS) return false;
        if (pipeline.createRenderPass(ctx) != c.VK_SUCCESS) return false;
        pipeline.createGraphicsPipeline(ctx) catch return false;
        pipeline.createDepthPipeline(ctx) catch return false;
    }

    // 2. Recreate depth resources with MSAA sample count and new extent
    pipeline.createDepthResources(ctx) catch return false;

    // 3. Recreate MSAA color resources with new extent
    pipeline.createMsaaColorResources(ctx) catch return false;

    // 4. Recreate depth prepass framebuffers
    if (pipeline.createDepthFramebuffers(ctx) != c.VK_SUCCESS) return false;

    // 5. Recreate forward framebuffers with 3 attachments
    if (pipeline.createFramebuffers(ctx) != c.VK_SUCCESS) return false;

    // 6. Rebuild render graph with new extent and framebuffers
    buildRenderGraph(ctx);

    return true;
}
