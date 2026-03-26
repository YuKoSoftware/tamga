const std = @import("std");
const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
});

const MAX_FRAMES_IN_FLIGHT: u32 = 2;

// ---- render graph ----
//
// Godot-inspired declarative pass system. For the clear-screen scope, this
// manages a single graphics pass. The data structures are designed so adding
// geometry passes, compute passes, and multi-pass pipelines later requires
// no refactoring of the graph infrastructure.

const RenderGraph = struct {
    current_image_index: u32 = 0,

    fn init() RenderGraph {
        return RenderGraph{};
    }

    fn execute(
        self: *RenderGraph,
        command_buffer: c.VkCommandBuffer,
        render_pass: c.VkRenderPass,
        framebuffer: c.VkFramebuffer,
        extent: c.VkExtent2D,
        clear_color: c.VkClearValue,
    ) void {
        _ = self;

        const render_pass_info = c.VkRenderPassBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .pNext = null,
            .renderPass = render_pass,
            .framebuffer = framebuffer,
            .renderArea = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = extent,
            },
            .clearValueCount = 1,
            .pClearValues = &clear_color,
        };

        c.vkCmdBeginRenderPass(command_buffer, &render_pass_info, c.VK_SUBPASS_CONTENTS_INLINE);
        // clear-screen: the clear is performed by the render pass load op
        // future: execute registered pass callbacks here
        c.vkCmdEndRenderPass(command_buffer);
    }
};

// ---- error types for bridge ----

const VkBridgeError = error{VulkanFailed};

// ---- Vulkan context (internal state) ----

const VulkanContext = struct {
    instance: c.VkInstance = null,
    debug_messenger: c.VkDebugUtilsMessengerEXT = null,
    surface: c.VkSurfaceKHR = null,
    physical_device: c.VkPhysicalDevice = null,
    device: c.VkDevice = null,
    graphics_queue: c.VkQueue = null,
    present_queue: c.VkQueue = null,
    graphics_family: u32 = 0,
    present_family: u32 = 0,

    // swapchain
    swapchain: c.VkSwapchainKHR = null,
    swapchain_images: [8]c.VkImage = [_]c.VkImage{null} ** 8,
    swapchain_views: [8]c.VkImageView = [_]c.VkImageView{null} ** 8,
    swapchain_image_count: u32 = 0,
    swapchain_format: c.VkFormat = c.VK_FORMAT_UNDEFINED,
    swapchain_extent: c.VkExtent2D = .{ .width = 0, .height = 0 },

    // render pass + framebuffers
    render_pass: c.VkRenderPass = null,
    framebuffers: [8]c.VkFramebuffer = [_]c.VkFramebuffer{null} ** 8,

    // commands
    command_pool: c.VkCommandPool = null,
    command_buffers: [8]c.VkCommandBuffer = [_]c.VkCommandBuffer{null} ** 8,

    // sync (double-buffered)
    image_available: [MAX_FRAMES_IN_FLIGHT]c.VkSemaphore = [_]c.VkSemaphore{null} ** MAX_FRAMES_IN_FLIGHT,
    render_finished: [MAX_FRAMES_IN_FLIGHT]c.VkSemaphore = [_]c.VkSemaphore{null} ** MAX_FRAMES_IN_FLIGHT,
    in_flight_fences: [MAX_FRAMES_IN_FLIGHT]c.VkFence = [_]c.VkFence{null} ** MAX_FRAMES_IN_FLIGHT,
    current_frame: u32 = 0,

    // SDL window handle
    sdl_window: ?*c.SDL_Window = null,
    debug_mode: bool = false,

    // render graph
    graph: RenderGraph = RenderGraph.init(),

    // clear color
    clear_color: c.VkClearValue = .{ .color = .{ .float32 = [4]f32{ 0.0, 0.0, 0.0, 1.0 } } },

    // state
    framebuffer_resized: bool = false,
};

// ---- instance creation ----

fn makeVersion(major: u32, minor: u32, patch: u32) u32 {
    return (major << 22) | (minor << 12) | patch;
}

fn validationLayerAvailable() bool {
    var layer_count: u32 = 0;
    _ = c.vkEnumerateInstanceLayerProperties(&layer_count, null);
    if (layer_count == 0) return false;

    var layers: [64]c.VkLayerProperties = undefined;
    var count: u32 = @min(layer_count, 64);
    _ = c.vkEnumerateInstanceLayerProperties(&count, &layers);

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const name: [*c]const u8 = &layers[i].layerName;
        if (std.mem.orderZ(u8, name, "VK_LAYER_KHRONOS_validation") == .eq) {
            return true;
        }
    }
    return false;
}

fn createInstance(ctx: *VulkanContext) c.VkResult {
    const app_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext = null,
        .pApplicationName = "Tamga",
        .applicationVersion = makeVersion(1, 0, 0),
        .pEngineName = "Tamga Vulkan",
        .engineVersion = makeVersion(1, 0, 0),
        .apiVersion = makeVersion(1, 0, 0),
    };

    // get SDL-required extensions
    var sdl_ext_count: u32 = 0;
    const sdl_exts = c.SDL_Vulkan_GetInstanceExtensions(&sdl_ext_count);

    // build extension list: SDL extensions + debug utils (if debug)
    var extensions: [16][*c]const u8 = undefined;
    var ext_count: u32 = 0;

    if (sdl_exts != null) {
        var i: u32 = 0;
        while (i < sdl_ext_count and i < 14) : (i += 1) {
            extensions[ext_count] = sdl_exts[i];
            ext_count += 1;
        }
    }

    // only enable validation if layers are actually installed
    const use_validation = ctx.debug_mode and validationLayerAvailable();

    if (use_validation) {
        extensions[ext_count] = c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME;
        ext_count += 1;
    }

    const validation_layer: [*c]const u8 = "VK_LAYER_KHRONOS_validation";
    const layer_count: u32 = if (use_validation) 1 else 0;

    const create_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .pApplicationInfo = &app_info,
        .enabledLayerCount = layer_count,
        .ppEnabledLayerNames = if (use_validation) &[_][*c]const u8{validation_layer} else null,
        .enabledExtensionCount = ext_count,
        .ppEnabledExtensionNames = &extensions,
    };

    return c.vkCreateInstance(&create_info, null, &ctx.instance);
}

// ---- debug messenger ----

fn debugCallback(
    severity: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
    _: c.VkDebugUtilsMessageTypeFlagsEXT,
    callback_data: ?*const c.VkDebugUtilsMessengerCallbackDataEXT,
    _: ?*anyopaque,
) callconv(.c) c.VkBool32 {
    if (callback_data) |data| {
        if (data.pMessage) |msg| {
            const prefix = if (severity >= c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT)
                "[VULKAN ERROR] "
            else if (severity >= c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT)
                "[VULKAN WARN]  "
            else
                "[VULKAN INFO]  ";
            std.debug.print("{s}{s}\n", .{ prefix, msg });
        }
    }
    return c.VK_FALSE;
}

fn setupDebugMessenger(ctx: *VulkanContext) c.VkResult {
    if (!ctx.debug_mode) return c.VK_SUCCESS;

    const create_info = c.VkDebugUtilsMessengerCreateInfoEXT{
        .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .pNext = null,
        .flags = 0,
        .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
        .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
        .pfnUserCallback = &debugCallback,
        .pUserData = null,
    };

    const func_ptr = @as(?*const fn (c.VkInstance, *const c.VkDebugUtilsMessengerCreateInfoEXT, ?*const c.VkAllocationCallbacks, *c.VkDebugUtilsMessengerEXT) callconv(.c) c.VkResult, @ptrCast(c.vkGetInstanceProcAddr(ctx.instance, "vkCreateDebugUtilsMessengerEXT")));

    if (func_ptr) |createFn| {
        return createFn(ctx.instance, &create_info, null, &ctx.debug_messenger);
    }
    return c.VK_ERROR_EXTENSION_NOT_PRESENT;
}

fn destroyDebugMessenger(ctx: *VulkanContext) void {
    if (!ctx.debug_mode or ctx.debug_messenger == null) return;

    const func_ptr = @as(?*const fn (c.VkInstance, c.VkDebugUtilsMessengerEXT, ?*const c.VkAllocationCallbacks) callconv(.c) void, @ptrCast(c.vkGetInstanceProcAddr(ctx.instance, "vkDestroyDebugUtilsMessengerEXT")));

    if (func_ptr) |destroyFn| {
        destroyFn(ctx.instance, ctx.debug_messenger, null);
    }
}

// ---- surface creation ----

fn createSurface(ctx: *VulkanContext) bool {
    return c.SDL_Vulkan_CreateSurface(ctx.sdl_window.?, ctx.instance, null, &ctx.surface);
}

// ---- physical device selection ----

fn findQueueFamilies(device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, graphics_family: *u32, present_family: *u32) bool {
    var queue_family_count: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

    var families: [32]c.VkQueueFamilyProperties = undefined;
    var count: u32 = @min(queue_family_count, 32);
    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &count, &families);

    var found_graphics = false;
    var found_present = false;

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        if (families[i].queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            graphics_family.* = i;
            found_graphics = true;
        }

        var present_support: c.VkBool32 = c.VK_FALSE;
        _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(device, i, surface, &present_support);
        if (present_support == c.VK_TRUE) {
            present_family.* = i;
            found_present = true;
        }

        if (found_graphics and found_present) return true;
    }
    return false;
}

fn deviceSupportsSwapchain(device: c.VkPhysicalDevice) bool {
    var ext_count: u32 = 0;
    _ = c.vkEnumerateDeviceExtensionProperties(device, null, &ext_count, null);

    var extensions: [256]c.VkExtensionProperties = undefined;
    var count: u32 = @min(ext_count, 256);
    _ = c.vkEnumerateDeviceExtensionProperties(device, null, &count, &extensions);

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const name: [*c]const u8 = &extensions[i].extensionName;
        if (std.mem.orderZ(u8, name, c.VK_KHR_SWAPCHAIN_EXTENSION_NAME) == .eq) {
            return true;
        }
    }
    return false;
}

fn pickPhysicalDevice(ctx: *VulkanContext) bool {
    var device_count: u32 = 0;
    _ = c.vkEnumeratePhysicalDevices(ctx.instance, &device_count, null);
    if (device_count == 0) return false;

    var devices: [8]c.VkPhysicalDevice = [_]c.VkPhysicalDevice{null} ** 8;
    var count: u32 = @min(device_count, 8);
    _ = c.vkEnumeratePhysicalDevices(ctx.instance, &count, &devices);

    // first pass: prefer discrete GPU
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        var props: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(devices[i], &props);

        if (props.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU and
            deviceSupportsSwapchain(devices[i]) and
            findQueueFamilies(devices[i], ctx.surface, &ctx.graphics_family, &ctx.present_family))
        {
            ctx.physical_device = devices[i];
            return true;
        }
    }

    // second pass: any suitable device
    i = 0;
    while (i < count) : (i += 1) {
        if (deviceSupportsSwapchain(devices[i]) and
            findQueueFamilies(devices[i], ctx.surface, &ctx.graphics_family, &ctx.present_family))
        {
            ctx.physical_device = devices[i];
            return true;
        }
    }

    return false;
}

// ---- logical device ----

fn createLogicalDevice(ctx: *VulkanContext) c.VkResult {
    const queue_priority: f32 = 1.0;

    // if graphics and present are the same family, only create one queue
    var queue_create_infos: [2]c.VkDeviceQueueCreateInfo = undefined;
    var queue_count: u32 = 1;

    queue_create_infos[0] = c.VkDeviceQueueCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .queueFamilyIndex = ctx.graphics_family,
        .queueCount = 1,
        .pQueuePriorities = &queue_priority,
    };

    if (ctx.graphics_family != ctx.present_family) {
        queue_create_infos[1] = c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueFamilyIndex = ctx.present_family,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        };
        queue_count = 2;
    }

    const device_features = std.mem.zeroes(c.VkPhysicalDeviceFeatures);
    const swapchain_ext: [*c]const u8 = c.VK_KHR_SWAPCHAIN_EXTENSION_NAME;

    const create_info = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .queueCreateInfoCount = queue_count,
        .pQueueCreateInfos = &queue_create_infos,
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = &[_][*c]const u8{swapchain_ext},
        .pEnabledFeatures = &device_features,
    };

    const result = c.vkCreateDevice(ctx.physical_device, &create_info, null, &ctx.device);
    if (result != c.VK_SUCCESS) return result;

    c.vkGetDeviceQueue(ctx.device, ctx.graphics_family, 0, &ctx.graphics_queue);
    c.vkGetDeviceQueue(ctx.device, ctx.present_family, 0, &ctx.present_queue);

    return c.VK_SUCCESS;
}

// ---- swapchain ----

fn chooseSwapSurfaceFormat(formats: []const c.VkSurfaceFormatKHR) c.VkSurfaceFormatKHR {
    for (formats) |format| {
        if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and
            format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
        {
            return format;
        }
    }
    return formats[0];
}

fn chooseSwapPresentMode(modes: []const c.VkPresentModeKHR) c.VkPresentModeKHR {
    for (modes) |mode| {
        if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) return mode;
    }
    return c.VK_PRESENT_MODE_FIFO_KHR;
}

fn chooseSwapExtent(capabilities: *const c.VkSurfaceCapabilitiesKHR, window: *c.SDL_Window) c.VkExtent2D {
    if (capabilities.currentExtent.width != 0xFFFFFFFF) {
        return capabilities.currentExtent;
    }

    var w: c_int = 0;
    var h: c_int = 0;
    _ = c.SDL_GetWindowSizeInPixels(window, &w, &h);

    return .{
        .width = std.math.clamp(@as(u32, @intCast(w)), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
        .height = std.math.clamp(@as(u32, @intCast(h)), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
    };
}

fn createSwapchain(ctx: *VulkanContext) c.VkResult {
    var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
    _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(ctx.physical_device, ctx.surface, &capabilities);

    // formats
    var format_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(ctx.physical_device, ctx.surface, &format_count, null);
    var formats: [16]c.VkSurfaceFormatKHR = undefined;
    var fc: u32 = @min(format_count, 16);
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(ctx.physical_device, ctx.surface, &fc, &formats);

    // present modes
    var mode_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(ctx.physical_device, ctx.surface, &mode_count, null);
    var modes: [8]c.VkPresentModeKHR = undefined;
    var mc: u32 = @min(mode_count, 8);
    _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(ctx.physical_device, ctx.surface, &mc, &modes);

    const surface_format = chooseSwapSurfaceFormat(formats[0..fc]);
    const present_mode = chooseSwapPresentMode(modes[0..mc]);
    const extent = chooseSwapExtent(&capabilities, ctx.sdl_window.?);

    var image_count = capabilities.minImageCount + 1;
    if (capabilities.maxImageCount > 0 and image_count > capabilities.maxImageCount) {
        image_count = capabilities.maxImageCount;
    }
    image_count = @min(image_count, 8);

    const same_family = ctx.graphics_family == ctx.present_family;
    const families = [2]u32{ ctx.graphics_family, ctx.present_family };

    const create_info = c.VkSwapchainCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .pNext = null,
        .flags = 0,
        .surface = ctx.surface,
        .minImageCount = image_count,
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = if (same_family) c.VK_SHARING_MODE_EXCLUSIVE else c.VK_SHARING_MODE_CONCURRENT,
        .queueFamilyIndexCount = if (same_family) 0 else 2,
        .pQueueFamilyIndices = if (same_family) null else &families,
        .preTransform = capabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = present_mode,
        .clipped = c.VK_TRUE,
        .oldSwapchain = null,
    };

    const result = c.vkCreateSwapchainKHR(ctx.device, &create_info, null, &ctx.swapchain);
    if (result != c.VK_SUCCESS) return result;

    ctx.swapchain_format = surface_format.format;
    ctx.swapchain_extent = extent;

    // get swapchain images
    var actual_count: u32 = 0;
    _ = c.vkGetSwapchainImagesKHR(ctx.device, ctx.swapchain, &actual_count, null);
    ctx.swapchain_image_count = @min(actual_count, 8);
    _ = c.vkGetSwapchainImagesKHR(ctx.device, ctx.swapchain, &ctx.swapchain_image_count, &ctx.swapchain_images);

    // create image views
    var vi: u32 = 0;
    while (vi < ctx.swapchain_image_count) : (vi += 1) {
        const view_info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = ctx.swapchain_images[vi],
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

        const vr = c.vkCreateImageView(ctx.device, &view_info, null, &ctx.swapchain_views[vi]);
        if (vr != c.VK_SUCCESS) return vr;
    }

    return c.VK_SUCCESS;
}

// ---- render pass ----

fn createRenderPass(ctx: *VulkanContext) c.VkResult {
    const color_attachment = c.VkAttachmentDescription{
        .flags = 0,
        .format = ctx.swapchain_format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
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

    const subpass = c.VkSubpassDescription{
        .flags = 0,
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .inputAttachmentCount = 0,
        .pInputAttachments = null,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_ref,
        .pResolveAttachments = null,
        .pDepthStencilAttachment = null,
        .preserveAttachmentCount = 0,
        .pPreserveAttachments = null,
    };

    const dependency = c.VkSubpassDependency{
        .srcSubpass = c.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .dependencyFlags = 0,
    };

    const render_pass_info = c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .attachmentCount = 1,
        .pAttachments = &color_attachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
    };

    return c.vkCreateRenderPass(ctx.device, &render_pass_info, null, &ctx.render_pass);
}

// ---- framebuffers ----

fn createFramebuffers(ctx: *VulkanContext) c.VkResult {
    var i: u32 = 0;
    while (i < ctx.swapchain_image_count) : (i += 1) {
        const fb_info = c.VkFramebufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .renderPass = ctx.render_pass,
            .attachmentCount = 1,
            .pAttachments = &[_]c.VkImageView{ctx.swapchain_views[i]},
            .width = ctx.swapchain_extent.width,
            .height = ctx.swapchain_extent.height,
            .layers = 1,
        };

        const result = c.vkCreateFramebuffer(ctx.device, &fb_info, null, &ctx.framebuffers[i]);
        if (result != c.VK_SUCCESS) return result;
    }
    return c.VK_SUCCESS;
}

// ---- command pool + buffers ----

fn createCommandPool(ctx: *VulkanContext) c.VkResult {
    const pool_info = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .pNext = null,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = ctx.graphics_family,
    };

    var result = c.vkCreateCommandPool(ctx.device, &pool_info, null, &ctx.command_pool);
    if (result != c.VK_SUCCESS) return result;

    const alloc_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = ctx.command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = ctx.swapchain_image_count,
    };

    result = c.vkAllocateCommandBuffers(ctx.device, &alloc_info, &ctx.command_buffers);
    return result;
}

// ---- sync objects ----

fn createSyncObjects(ctx: *VulkanContext) c.VkResult {
    const sem_info = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
    };

    const fence_info = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .pNext = null,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };

    var i: u32 = 0;
    while (i < MAX_FRAMES_IN_FLIGHT) : (i += 1) {
        var result = c.vkCreateSemaphore(ctx.device, &sem_info, null, &ctx.image_available[i]);
        if (result != c.VK_SUCCESS) return result;

        result = c.vkCreateSemaphore(ctx.device, &sem_info, null, &ctx.render_finished[i]);
        if (result != c.VK_SUCCESS) return result;

        result = c.vkCreateFence(ctx.device, &fence_info, null, &ctx.in_flight_fences[i]);
        if (result != c.VK_SUCCESS) return result;
    }

    return c.VK_SUCCESS;
}

// ---- swapchain cleanup + recreation ----

fn cleanupSwapchain(ctx: *VulkanContext) void {
    var i: u32 = 0;
    while (i < ctx.swapchain_image_count) : (i += 1) {
        if (ctx.framebuffers[i] != null) {
            c.vkDestroyFramebuffer(ctx.device, ctx.framebuffers[i], null);
            ctx.framebuffers[i] = null;
        }
        if (ctx.swapchain_views[i] != null) {
            c.vkDestroyImageView(ctx.device, ctx.swapchain_views[i], null);
            ctx.swapchain_views[i] = null;
        }
    }
    if (ctx.swapchain != null) {
        c.vkDestroySwapchainKHR(ctx.device, ctx.swapchain, null);
        ctx.swapchain = null;
    }
}

fn recreateSwapchain(ctx: *VulkanContext) bool {
    // handle minimized window
    var w: c_int = 0;
    var h: c_int = 0;
    _ = c.SDL_GetWindowSizeInPixels(ctx.sdl_window.?, &w, &h);
    if (w == 0 or h == 0) return false;

    _ = c.vkDeviceWaitIdle(ctx.device);

    cleanupSwapchain(ctx);

    if (createSwapchain(ctx) != c.VK_SUCCESS) return false;
    if (createFramebuffers(ctx) != c.VK_SUCCESS) return false;

    return true;
}

// ---- bridge: Renderer struct ----

pub const Renderer = struct {
    ctx: VulkanContext,

    pub fn create(window_handle: @import("tamga_sdl3_bridge.zig").WindowHandle, debug_mode: bool) anyerror!Renderer {
        var ctx = VulkanContext{};
        // WindowHandle is now a plain *anyopaque pointer (type alias).
        ctx.sdl_window = @ptrCast(@alignCast(window_handle));
        ctx.debug_mode = debug_mode;

        // instance
        if (createInstance(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // debug messenger (non-fatal — silently skip if validation layers unavailable)
        _ = setupDebugMessenger(&ctx);

        // surface
        if (!createSurface(&ctx)) {
            return VkBridgeError.VulkanFailed;
        }

        // physical device
        if (!pickPhysicalDevice(&ctx)) {
            return VkBridgeError.VulkanFailed;
        }

        // logical device
        if (createLogicalDevice(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // swapchain
        if (createSwapchain(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // render pass
        if (createRenderPass(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // framebuffers
        if (createFramebuffers(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // command pool + buffers
        if (createCommandPool(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // sync objects
        if (createSyncObjects(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        return Renderer{ .ctx = ctx };
    }

    pub fn destroy(self: *Renderer) void {
        _ = c.vkDeviceWaitIdle(self.ctx.device);

        var i: u32 = 0;
        while (i < MAX_FRAMES_IN_FLIGHT) : (i += 1) {
            if (self.ctx.render_finished[i] != null) c.vkDestroySemaphore(self.ctx.device, self.ctx.render_finished[i], null);
            if (self.ctx.image_available[i] != null) c.vkDestroySemaphore(self.ctx.device, self.ctx.image_available[i], null);
            if (self.ctx.in_flight_fences[i] != null) c.vkDestroyFence(self.ctx.device, self.ctx.in_flight_fences[i], null);
        }

        if (self.ctx.command_pool != null) c.vkDestroyCommandPool(self.ctx.device, self.ctx.command_pool, null);

        cleanupSwapchain(&self.ctx);

        if (self.ctx.render_pass != null) c.vkDestroyRenderPass(self.ctx.device, self.ctx.render_pass, null);
        if (self.ctx.device != null) c.vkDestroyDevice(self.ctx.device, null);

        destroyDebugMessenger(&self.ctx);

        if (self.ctx.surface != null) c.vkDestroySurfaceKHR(self.ctx.instance, self.ctx.surface, null);
        if (self.ctx.instance != null) c.vkDestroyInstance(self.ctx.instance, null);
    }

    pub fn beginFrame(self: *Renderer) bool {
        const ctx = &self.ctx;
        const frame = ctx.current_frame;

        // wait for previous frame using this slot to finish
        _ = c.vkWaitForFences(ctx.device, 1, &ctx.in_flight_fences[frame], c.VK_TRUE, std.math.maxInt(u64));

        // acquire next swapchain image
        var image_index: u32 = 0;
        const result = c.vkAcquireNextImageKHR(
            ctx.device,
            ctx.swapchain,
            std.math.maxInt(u64),
            ctx.image_available[frame],
            null,
            &image_index,
        );

        if (result == c.VK_ERROR_OUT_OF_DATE_KHR) {
            if (!recreateSwapchain(ctx)) return false;
            return false;
        }
        if (result != c.VK_SUCCESS and result != c.VK_SUBOPTIMAL_KHR) return false;

        _ = c.vkResetFences(ctx.device, 1, &ctx.in_flight_fences[frame]);

        // reset and begin command buffer
        _ = c.vkResetCommandBuffer(ctx.command_buffers[frame], 0);

        const begin_info = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .pNext = null,
            .flags = 0,
            .pInheritanceInfo = null,
        };
        _ = c.vkBeginCommandBuffer(ctx.command_buffers[frame], &begin_info);

        // execute render graph (records render pass + barriers into command buffer)
        ctx.graph.execute(
            ctx.command_buffers[frame],
            ctx.render_pass,
            ctx.framebuffers[image_index],
            ctx.swapchain_extent,
            ctx.clear_color,
        );

        // store image index for endFrame
        ctx.graph.current_image_index = image_index;

        return true;
    }

    pub fn endFrame(self: *Renderer) void {
        const ctx = &self.ctx;
        const frame = ctx.current_frame;
        const image_index = ctx.graph.current_image_index;

        _ = c.vkEndCommandBuffer(ctx.command_buffers[frame]);

        // submit
        const wait_stage: u32 = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        const submit_info = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .pNext = null,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &ctx.image_available[frame],
            .pWaitDstStageMask = &wait_stage,
            .commandBufferCount = 1,
            .pCommandBuffers = &ctx.command_buffers[frame],
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &ctx.render_finished[frame],
        };

        _ = c.vkQueueSubmit(ctx.graphics_queue, 1, &submit_info, ctx.in_flight_fences[frame]);

        // present
        const present_info = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .pNext = null,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &ctx.render_finished[frame],
            .swapchainCount = 1,
            .pSwapchains = &ctx.swapchain,
            .pImageIndices = &image_index,
            .pResults = null,
        };

        const result = c.vkQueuePresentKHR(ctx.present_queue, &present_info);

        if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR or ctx.framebuffer_resized) {
            ctx.framebuffer_resized = false;
            _ = recreateSwapchain(ctx);
        }

        ctx.current_frame = (frame + 1) % MAX_FRAMES_IN_FLIGHT;
    }

    pub fn setClearColor(self: *Renderer, r: f32, g: f32, b: f32, a: f32) void {
        self.ctx.clear_color = .{ .color = .{ .float32 = [4]f32{ r, g, b, a } } };
    }
};
