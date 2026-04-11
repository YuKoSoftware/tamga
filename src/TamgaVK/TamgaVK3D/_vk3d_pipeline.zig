const std = @import("std");
const vma = @import("tamga_vulkan");
const c = @import("vulkan_c").c;
const anchor = @import("tamga_vk3d.zig");
const VulkanContext = anchor.VulkanContext;
const VkBridgeError = anchor.VkBridgeError;

// ---- depth format selection ----

pub fn findDepthFormat(physical_device: c.VkPhysicalDevice) c.VkFormat {
    // Try formats in order of preference: D32 pure, D32 with stencil, D24 with stencil
    // Per VK3-16: cross-vendor compatible selection
    const candidates = [_]c.VkFormat{
        c.VK_FORMAT_D32_SFLOAT,
        c.VK_FORMAT_D32_SFLOAT_S8_UINT,
        c.VK_FORMAT_D24_UNORM_S8_UINT,
    };

    for (candidates) |format| {
        var props: c.VkFormatProperties = undefined;
        c.vkGetPhysicalDeviceFormatProperties(physical_device, format, &props);
        if (props.optimalTilingFeatures & c.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT != 0) {
            return format;
        }
    }

    // Fallback — should not happen on any modern GPU
    return c.VK_FORMAT_D32_SFLOAT;
}

// getMaxUsableSampleCount returns the highest sample count supported for both
// color and depth attachments, capped at VK_SAMPLE_COUNT_4_BIT per VK3-16
// (general cross-vendor performance optimization — 4x is the sweet spot for
// quality/performance on all hardware tiers).
pub fn getMaxUsableSampleCount(physical_device: c.VkPhysicalDevice) c.VkSampleCountFlagBits {
    var props: c.VkPhysicalDeviceProperties = undefined;
    c.vkGetPhysicalDeviceProperties(physical_device, &props);

    const counts = props.limits.framebufferColorSampleCounts &
        props.limits.framebufferDepthSampleCounts;

    // Check 4x first (our cap per VK3-16), then fall back to lower counts
    if (counts & c.VK_SAMPLE_COUNT_4_BIT != 0) return c.VK_SAMPLE_COUNT_4_BIT;
    if (counts & c.VK_SAMPLE_COUNT_2_BIT != 0) return c.VK_SAMPLE_COUNT_2_BIT;
    return c.VK_SAMPLE_COUNT_1_BIT;
}

// ---- depth resources ----

pub fn createDepthResources(ctx: *VulkanContext) anyerror!void {
    ctx.depth_format = findDepthFormat(ctx.physical_device);

    // Create depth image via VMA with MSAA sample count.
    // SAMPLED_BIT: compute shader reads depth for cluster light culling.
    const image_alloc = try ctx.vma_ctx.createImageWithSamples(
        ctx.swapchain_extent.width,
        ctx.swapchain_extent.height,
        ctx.depth_format,
        c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT,
        true, // gpu_only: device-local
        ctx.msaa_samples,
    );

    ctx.depth_image = image_alloc.image;
    ctx.depth_allocation = image_alloc.allocation;

    // Create image view with DEPTH aspect
    const view_info = c.VkImageViewCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .image = ctx.depth_image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = ctx.depth_format,
        .components = .{
            .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
        },
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    const result = c.vkCreateImageView(ctx.device, &view_info, null, &ctx.depth_image_view);
    if (result != c.VK_SUCCESS) return VkBridgeError.VulkanFailed;
}

pub fn destroyDepthResources(ctx: *VulkanContext) void {
    if (ctx.depth_image_view != null) {
        c.vkDestroyImageView(ctx.device, ctx.depth_image_view, null);
        ctx.depth_image_view = null;
    }
    if (ctx.depth_image != null) {
        ctx.vma_ctx.destroyImage(ctx.depth_image, ctx.depth_allocation);
        ctx.depth_image = null;
    }
}

// ---- MSAA color attachment ----

pub fn createMsaaColorResources(ctx: *VulkanContext) anyerror!void {
    // TRANSIENT_ATTACHMENT: GPU can use tile memory — never needs to be written to system RAM
    // COLOR_ATTACHMENT: needed for use as render target before resolve
    const usage = c.VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

    const image_alloc = try ctx.vma_ctx.createImageWithSamples(
        ctx.swapchain_extent.width,
        ctx.swapchain_extent.height,
        ctx.swapchain_format,
        usage,
        true, // gpu_only: device-local
        ctx.msaa_samples,
    );

    ctx.msaa_color_image = image_alloc.image;
    ctx.msaa_color_allocation = image_alloc.allocation;

    const view_info = c.VkImageViewCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .image = ctx.msaa_color_image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = ctx.swapchain_format,
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

    const result = c.vkCreateImageView(ctx.device, &view_info, null, &ctx.msaa_color_view);
    if (result != c.VK_SUCCESS) return VkBridgeError.VulkanFailed;
}

pub fn destroyMsaaColorResources(ctx: *VulkanContext) void {
    if (ctx.msaa_color_view != null) {
        c.vkDestroyImageView(ctx.device, ctx.msaa_color_view, null);
        ctx.msaa_color_view = null;
    }
    if (ctx.msaa_color_image != null) {
        ctx.vma_ctx.destroyImage(ctx.msaa_color_image, ctx.msaa_color_allocation);
        ctx.msaa_color_image = null;
    }
}

// ---- render pass (with depth attachment) ----

pub fn createRenderPass(ctx: *VulkanContext) c.VkResult {
    // Attachment [0]: MSAA color — rendered to, not stored (resolved to swapchain)
    const msaa_color_attachment = c.VkAttachmentDescription{
        .flags = 0,
        .format = ctx.swapchain_format,
        .samples = ctx.msaa_samples,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    // Attachment [1]: MSAA depth — loaded from depth prepass, read-only.
    // Uses READ_ONLY_OPTIMAL: compatible with both depth testing and shader sampling.
    const depth_attachment = c.VkAttachmentDescription{
        .flags = 0,
        .format = ctx.depth_format,
        .samples = ctx.msaa_samples,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL,
        .finalLayout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL,
    };

    // Attachment [2]: Resolve / swapchain — receives resolved output, must be stored
    const resolve_attachment = c.VkAttachmentDescription{
        .flags = 0,
        .format = ctx.swapchain_format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };

    const color_ref = c.VkAttachmentReference{
        .attachment = 0,
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    const depth_ref = c.VkAttachmentReference{
        .attachment = 1,
        .layout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL,
    };

    const resolve_ref = c.VkAttachmentReference{
        .attachment = 2,
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    const subpass = c.VkSubpassDescription{
        .flags = 0,
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .inputAttachmentCount = 0,
        .pInputAttachments = null,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_ref,
        .pResolveAttachments = &resolve_ref,
        .pDepthStencilAttachment = &depth_ref,
        .preserveAttachmentCount = 0,
        .pPreserveAttachments = null,
    };

    // Dependency: color output and depth tests must complete before rendering
    const dependency = c.VkSubpassDependency{
        .srcSubpass = c.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
            c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
        .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
            c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
        .srcAccessMask = 0,
        .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT |
            c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        .dependencyFlags = 0,
    };

    const attachments = [3]c.VkAttachmentDescription{
        msaa_color_attachment,
        depth_attachment,
        resolve_attachment,
    };

    const render_pass_info = c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .attachmentCount = 3,
        .pAttachments = &attachments,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
    };

    return c.vkCreateRenderPass(ctx.device, &render_pass_info, null, &ctx.render_pass);
}

// ---- depth prepass render pass ----

pub fn createDepthRenderPass(ctx: *VulkanContext) c.VkResult {
    // Single attachment: depth (CLEAR + STORE, no color)
    const depth_attachment = c.VkAttachmentDescription{
        .flags = 0,
        .format = ctx.depth_format,
        .samples = ctx.msaa_samples,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    };

    const depth_ref = c.VkAttachmentReference{
        .attachment = 0,
        .layout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    };

    const subpass = c.VkSubpassDescription{
        .flags = 0,
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .inputAttachmentCount = 0,
        .pInputAttachments = null,
        .colorAttachmentCount = 0,
        .pColorAttachments = null,
        .pResolveAttachments = null,
        .pDepthStencilAttachment = &depth_ref,
        .preserveAttachmentCount = 0,
        .pPreserveAttachments = null,
    };

    const dependency = c.VkSubpassDependency{
        .srcSubpass = c.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
        .dstStageMask = c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
        .srcAccessMask = 0,
        .dstAccessMask = c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        .dependencyFlags = 0,
    };

    const render_pass_info = c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .attachmentCount = 1,
        .pAttachments = &[1]c.VkAttachmentDescription{depth_attachment},
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
    };

    return c.vkCreateRenderPass(ctx.device, &render_pass_info, null, &ctx.depth_render_pass);
}

// ---- depth prepass framebuffers ----

pub fn createDepthFramebuffers(ctx: *VulkanContext) c.VkResult {
    // All depth framebuffers use the same depth image view (depth buffer is shared)
    var i: u32 = 0;
    while (i < ctx.swapchain_image_count) : (i += 1) {
        const fb_info = c.VkFramebufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .renderPass = ctx.depth_render_pass,
            .attachmentCount = 1,
            .pAttachments = &[1]c.VkImageView{ctx.depth_image_view},
            .width = ctx.swapchain_extent.width,
            .height = ctx.swapchain_extent.height,
            .layers = 1,
        };

        const result = c.vkCreateFramebuffer(ctx.device, &fb_info, null, &ctx.depth_framebuffers[i]);
        if (result != c.VK_SUCCESS) return result;
    }
    return c.VK_SUCCESS;
}

// ---- framebuffers (color + depth) ----

pub fn createFramebuffers(ctx: *VulkanContext) c.VkResult {
    var i: u32 = 0;
    while (i < ctx.swapchain_image_count) : (i += 1) {
        // 3 attachments: [0] MSAA color, [1] MSAA depth, [2] resolve/swapchain
        const attachments = [3]c.VkImageView{
            ctx.msaa_color_view,
            ctx.depth_image_view,
            ctx.swapchain_views[i],
        };

        const fb_info = c.VkFramebufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .renderPass = ctx.render_pass,
            .attachmentCount = 3,
            .pAttachments = &attachments,
            .width = ctx.swapchain_extent.width,
            .height = ctx.swapchain_extent.height,
            .layers = 1,
        };

        const result = c.vkCreateFramebuffer(ctx.device, &fb_info, null, &ctx.framebuffers[i]);
        if (result != c.VK_SUCCESS) return result;
    }
    return c.VK_SUCCESS;
}

// ---- .spv shader loading ----

pub fn loadShaderModule(device: c.VkDevice, path: [*:0]const u8) ?c.VkShaderModule {
    const file = std.fs.cwd().openFileZ(path, .{}) catch |err| {
        std.debug.print("[TamgaVK3D] Failed to open shader: {s} ({any})\n", .{ path, err });
        return null;
    };
    defer file.close();

    const file_size = file.getEndPos() catch return null;
    if (file_size == 0 or file_size > 1024 * 1024) return null;

    const allocator = std.heap.page_allocator;
    const buf = allocator.alloc(u8, file_size) catch return null;
    defer allocator.free(buf);

    const bytes_read = file.readAll(buf) catch return null;
    if (bytes_read != file_size) return null;

    const shader_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = file_size,
        .pCode = @ptrCast(@alignCast(buf.ptr)),
    };

    var shader_module: c.VkShaderModule = null;
    const result = c.vkCreateShaderModule(device, &shader_info, null, &shader_module);
    if (result != c.VK_SUCCESS) return null;

    return shader_module;
}

// ---- depth prepass pipeline ----

pub fn createDepthPipeline(ctx: *VulkanContext) anyerror!void {
    const vert_module = loadShaderModule(ctx.device, "assets/shaders/depth.vert.spv") orelse {
        std.debug.print("[TamgaVK3D] Failed to load depth.vert.spv\n", .{});
        return VkBridgeError.VulkanFailed;
    };
    defer c.vkDestroyShaderModule(ctx.device, vert_module, null);

    const frag_module = loadShaderModule(ctx.device, "assets/shaders/depth.frag.spv") orelse {
        std.debug.print("[TamgaVK3D] Failed to load depth.frag.spv\n", .{});
        return VkBridgeError.VulkanFailed;
    };
    defer c.vkDestroyShaderModule(ctx.device, frag_module, null);

    const shader_stages = [2]c.VkPipelineShaderStageCreateInfo{
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vert_module,
            .pName = "main",
            .pSpecializationInfo = null,
        },
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = frag_module,
            .pName = "main",
            .pSpecializationInfo = null,
        },
    };

    // Same vertex input as forward pipeline (D-05 format)
    const vertex_binding = c.VkVertexInputBindingDescription{
        .binding = 0,
        .stride = 48,
        .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
    };

    const vertex_attributes = [4]c.VkVertexInputAttributeDescription{
        .{ .location = 0, .binding = 0, .format = c.VK_FORMAT_R32G32B32_SFLOAT, .offset = 0 },
        .{ .location = 1, .binding = 0, .format = c.VK_FORMAT_R32G32B32_SFLOAT, .offset = 12 },
        .{ .location = 2, .binding = 0, .format = c.VK_FORMAT_R32G32_SFLOAT, .offset = 24 },
        .{ .location = 3, .binding = 0, .format = c.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = 32 },
    };

    const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &vertex_binding,
        .vertexAttributeDescriptionCount = 4,
        .pVertexAttributeDescriptions = &vertex_attributes,
    };

    const input_assembly = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = c.VK_FALSE,
    };

    const dynamic_states = [2]c.VkDynamicState{
        c.VK_DYNAMIC_STATE_VIEWPORT,
        c.VK_DYNAMIC_STATE_SCISSOR,
    };

    const dynamic_state_info = c.VkPipelineDynamicStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .dynamicStateCount = 2,
        .pDynamicStates = &dynamic_states,
    };

    const viewport_state = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .viewportCount = 1,
        .pViewports = null,
        .scissorCount = 1,
        .pScissors = null,
    };

    const rasterizer = c.VkPipelineRasterizationStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = c.VK_FALSE,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .cullMode = c.VK_CULL_MODE_BACK_BIT,
        .frontFace = c.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .depthBiasEnable = c.VK_FALSE,
        .depthBiasConstantFactor = 0.0,
        .depthBiasClamp = 0.0,
        .depthBiasSlopeFactor = 0.0,
        .lineWidth = 1.0,
    };

    const multisampling = c.VkPipelineMultisampleStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .rasterizationSamples = ctx.msaa_samples,
        .sampleShadingEnable = c.VK_FALSE,
        .minSampleShading = 0.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = c.VK_FALSE,
        .alphaToOneEnable = c.VK_FALSE,
    };

    // Depth test LESS + write enabled (populate depth buffer)
    const depth_stencil = c.VkPipelineDepthStencilStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .depthTestEnable = c.VK_TRUE,
        .depthWriteEnable = c.VK_TRUE,
        .depthCompareOp = c.VK_COMPARE_OP_LESS,
        .depthBoundsTestEnable = c.VK_FALSE,
        .stencilTestEnable = c.VK_FALSE,
        .front = std.mem.zeroes(c.VkStencilOpState),
        .back = std.mem.zeroes(c.VkStencilOpState),
        .minDepthBounds = 0.0,
        .maxDepthBounds = 1.0,
    };

    // No color attachments — depth-only pass
    const color_blending = c.VkPipelineColorBlendStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .logicOpEnable = c.VK_FALSE,
        .logicOp = c.VK_LOGIC_OP_COPY,
        .attachmentCount = 0,
        .pAttachments = null,
        .blendConstants = [4]f32{ 0.0, 0.0, 0.0, 0.0 },
    };

    const pipeline_info = c.VkGraphicsPipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stageCount = 2,
        .pStages = &shader_stages,
        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly,
        .pTessellationState = null,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = &depth_stencil,
        .pColorBlendState = &color_blending,
        .pDynamicState = &dynamic_state_info,
        .layout = ctx.pipeline_layout,
        .renderPass = ctx.depth_render_pass,
        .subpass = 0,
        .basePipelineHandle = null,
        .basePipelineIndex = -1,
    };

    const result = c.vkCreateGraphicsPipelines(ctx.device, null, 1, &pipeline_info, null, &ctx.depth_pipeline);
    if (result != c.VK_SUCCESS) return VkBridgeError.VulkanFailed;
}

// ---- graphics pipeline ----

pub fn createGraphicsPipeline(ctx: *VulkanContext) anyerror!void {
    // Load SPIR-V shaders from assets/shaders/
    const vert_module = loadShaderModule(ctx.device, "assets/shaders/mesh.vert.spv") orelse {
        std.debug.print("[TamgaVK3D] Failed to load mesh.vert.spv\n", .{});
        return VkBridgeError.VulkanFailed;
    };
    defer c.vkDestroyShaderModule(ctx.device, vert_module, null);

    const frag_module = loadShaderModule(ctx.device, "assets/shaders/mesh.frag.spv") orelse {
        std.debug.print("[TamgaVK3D] Failed to load mesh.frag.spv\n", .{});
        return VkBridgeError.VulkanFailed;
    };
    defer c.vkDestroyShaderModule(ctx.device, frag_module, null);

    const shader_stages = [2]c.VkPipelineShaderStageCreateInfo{
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vert_module,
            .pName = "main",
            .pSpecializationInfo = null,
        },
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = frag_module,
            .pName = "main",
            .pSpecializationInfo = null,
        },
    };

    // Vertex input: single binding, 4 attributes matching D-05 vertex format
    // stride = 48 bytes: vec3 pos (12) + vec3 normal (12) + vec2 uv (8) + vec4 color (16)
    const vertex_binding = c.VkVertexInputBindingDescription{
        .binding = 0,
        .stride = 48,
        .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
    };

    const vertex_attributes = [4]c.VkVertexInputAttributeDescription{
        .{ .location = 0, .binding = 0, .format = c.VK_FORMAT_R32G32B32_SFLOAT, .offset = 0 }, // position
        .{ .location = 1, .binding = 0, .format = c.VK_FORMAT_R32G32B32_SFLOAT, .offset = 12 }, // normal
        .{ .location = 2, .binding = 0, .format = c.VK_FORMAT_R32G32_SFLOAT, .offset = 24 }, // uv
        .{ .location = 3, .binding = 0, .format = c.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = 32 }, // color
    };

    const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &vertex_binding,
        .vertexAttributeDescriptionCount = 4,
        .pVertexAttributeDescriptions = &vertex_attributes,
    };

    const input_assembly = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = c.VK_FALSE,
    };

    // Dynamic viewport and scissor — set in beginFrame
    const dynamic_states = [2]c.VkDynamicState{
        c.VK_DYNAMIC_STATE_VIEWPORT,
        c.VK_DYNAMIC_STATE_SCISSOR,
    };

    const dynamic_state_info = c.VkPipelineDynamicStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .dynamicStateCount = 2,
        .pDynamicStates = &dynamic_states,
    };

    const viewport_state = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .viewportCount = 1,
        .pViewports = null, // dynamic
        .scissorCount = 1,
        .pScissors = null, // dynamic
    };

    const rasterizer = c.VkPipelineRasterizationStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = c.VK_FALSE,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .cullMode = c.VK_CULL_MODE_BACK_BIT,
        .frontFace = c.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .depthBiasEnable = c.VK_FALSE,
        .depthBiasConstantFactor = 0.0,
        .depthBiasClamp = 0.0,
        .depthBiasSlopeFactor = 0.0,
        .lineWidth = 1.0,
    };

    const multisampling = c.VkPipelineMultisampleStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .rasterizationSamples = ctx.msaa_samples,
        .sampleShadingEnable = if (ctx.msaa_samples != c.VK_SAMPLE_COUNT_1_BIT) c.VK_TRUE else c.VK_FALSE,
        .minSampleShading = 0.2, // subtle sub-sample shading improvement (only active when > 1x)
        .pSampleMask = null,
        .alphaToCoverageEnable = c.VK_FALSE,
        .alphaToOneEnable = c.VK_FALSE,
    };

    // Depth test EQUAL + write disabled — depth prepass already populated the buffer.
    // Only fragments at the exact prepass depth pass, giving zero overdraw.
    const depth_stencil = c.VkPipelineDepthStencilStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .depthTestEnable = c.VK_TRUE,
        .depthWriteEnable = c.VK_FALSE,
        .depthCompareOp = c.VK_COMPARE_OP_EQUAL,
        .depthBoundsTestEnable = c.VK_FALSE,
        .stencilTestEnable = c.VK_FALSE,
        .front = std.mem.zeroes(c.VkStencilOpState),
        .back = std.mem.zeroes(c.VkStencilOpState),
        .minDepthBounds = 0.0,
        .maxDepthBounds = 1.0,
    };

    const color_blend_attachment = c.VkPipelineColorBlendAttachmentState{
        .blendEnable = c.VK_TRUE,
        .srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = c.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = c.VK_BLEND_OP_ADD,
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT |
            c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
    };

    const color_blending = c.VkPipelineColorBlendStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .logicOpEnable = c.VK_FALSE,
        .logicOp = c.VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
        .blendConstants = [4]f32{ 0.0, 0.0, 0.0, 0.0 },
    };

    // Pipeline layout: 2 descriptor set layouts + push constants (model matrix 64 bytes)
    const push_constant_range = c.VkPushConstantRange{
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
        .offset = 0,
        .size = 64, // mat4 = 16 * 4 bytes
    };

    const set_layouts = [2]c.VkDescriptorSetLayout{ ctx.descriptor_set_layout_0, ctx.descriptor_set_layout_1 };

    const layout_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .setLayoutCount = 2,
        .pSetLayouts = &set_layouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_constant_range,
    };

    const layout_result = c.vkCreatePipelineLayout(ctx.device, &layout_info, null, &ctx.pipeline_layout);
    if (layout_result != c.VK_SUCCESS) return VkBridgeError.VulkanFailed;

    // Create graphics pipeline
    const pipeline_info = c.VkGraphicsPipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stageCount = 2,
        .pStages = &shader_stages,
        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly,
        .pTessellationState = null,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = &depth_stencil,
        .pColorBlendState = &color_blending,
        .pDynamicState = &dynamic_state_info,
        .layout = ctx.pipeline_layout,
        .renderPass = ctx.render_pass,
        .subpass = 0,
        .basePipelineHandle = null,
        .basePipelineIndex = -1,
    };

    const pipeline_result = c.vkCreateGraphicsPipelines(ctx.device, null, 1, &pipeline_info, null, &ctx.pipeline);
    if (pipeline_result != c.VK_SUCCESS) return VkBridgeError.VulkanFailed;
}
