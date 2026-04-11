const std = @import("std");
const vma = @import("tamga_vulkan_bridge");
const rg = @import("tamga_vulkan_bridge");
const c = @import("vulkan_c").c;
// SDL types are imported via a local @cImport since SDL headers are only used in this module.
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
});

// ---- private modules ----
const lighting = @import("_vk3d_lighting.zig");
const descriptors = @import("_vk3d_descriptors.zig");
const pipeline = @import("_vk3d_pipeline.zig");
const resources = @import("_vk3d_resources.zig");
const rendergraph = @import("_vk3d_rendergraph.zig");

// ---- re-export public types from private modules ----
pub const LightData = lighting.LightData;
pub const CameraUBO = descriptors.CameraUBO;
pub const MaterialUBOData = descriptors.MaterialUBOData;
pub const MeshBuffers = resources.MeshBuffers;
pub const Texture = resources.Texture;
pub const Material = resources.Material;

// ---- resource ID types ----
// Lightweight typed indices into the renderer's internal slot maps.
// Created by Renderer methods, passed back to draw/destroy calls.

pub const MeshId = struct { id: u32 };
pub const TextureId = struct { id: u32 };
pub const MaterialId = struct { id: u32 };

const MAX_FRAMES_IN_FLIGHT: u32 = 2;

// ---- error types for bridge ----

pub const VkBridgeError = error{VulkanFailed};

// ---- Vulkan context (internal state) ----

pub const VulkanContext = struct {
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

    // MSAA
    msaa_samples: c.VkSampleCountFlagBits = c.VK_SAMPLE_COUNT_1_BIT,
    msaa_color_image: c.VkImage = null,
    msaa_color_view: c.VkImageView = null,
    msaa_color_allocation: vma.VmaAllocation = undefined,

    // depth buffer
    depth_image: c.VkImage = null,
    depth_image_view: c.VkImageView = null,
    depth_allocation: vma.VmaAllocation = undefined,
    depth_format: c.VkFormat = c.VK_FORMAT_UNDEFINED,

    // render passes + framebuffers
    render_pass: c.VkRenderPass = null,
    framebuffers: [8]c.VkFramebuffer = [_]c.VkFramebuffer{null} ** 8,
    // depth prepass
    depth_render_pass: c.VkRenderPass = null,
    depth_framebuffers: [8]c.VkFramebuffer = [_]c.VkFramebuffer{null} ** 8,

    // commands
    command_pool: c.VkCommandPool = null,
    command_buffers: [8]c.VkCommandBuffer = [_]c.VkCommandBuffer{null} ** 8,

    // sync (double-buffered)
    image_available: [MAX_FRAMES_IN_FLIGHT]c.VkSemaphore = [_]c.VkSemaphore{null} ** MAX_FRAMES_IN_FLIGHT,
    render_finished: [MAX_FRAMES_IN_FLIGHT]c.VkSemaphore = [_]c.VkSemaphore{null} ** MAX_FRAMES_IN_FLIGHT,
    in_flight_fences: [MAX_FRAMES_IN_FLIGHT]c.VkFence = [_]c.VkFence{null} ** MAX_FRAMES_IN_FLIGHT,
    current_frame: u32 = 0,

    // SDL window handle
    sdl_window: ?*sdl.SDL_Window = null,
    debug_mode: bool = false,

    // render graph (tamga_render_graph library)
    graph: rg.RenderGraph = rg.RenderGraph.init(),
    graph_image_index: u32 = 0,

    // clear colors (index 0 = color, index 1 = depth)
    clear_color: c.VkClearValue = .{ .color = .{ .float32 = [4]f32{ 0.0, 0.0, 0.0, 1.0 } } },

    // draw call list (filled by draw(), consumed by forward pass callback)
    draw_list: [rendergraph.MAX_DRAW_CALLS]rendergraph.DrawCall = undefined,
    draw_count: u32 = 0,

    // state
    framebuffer_resized: bool = false,

    // VMA allocator
    vma_ctx: vma.VmaContext = undefined,
    vma_initialized: bool = false,

    // graphics pipelines
    pipeline: c.VkPipeline = null,
    depth_pipeline: c.VkPipeline = null,
    pipeline_layout: c.VkPipelineLayout = null,
    descriptor_set_layout_0: c.VkDescriptorSetLayout = null,
    descriptor_set_layout_1: c.VkDescriptorSetLayout = null,

    // descriptor pool and per-frame sets
    descriptor_pool: c.VkDescriptorPool = null,
    descriptor_sets_0: [MAX_FRAMES_IN_FLIGHT]c.VkDescriptorSet = [_]c.VkDescriptorSet{null} ** MAX_FRAMES_IN_FLIGHT,

    // UBOs (double-buffered)
    camera_ubos: [MAX_FRAMES_IN_FLIGHT]vma.BufferAlloc = undefined,
    camera_mapped: [MAX_FRAMES_IN_FLIGHT][*]u8 = undefined,
    // Light SSBOs (double-buffered) — replaces fixed-size UBO for variable light count
    light_ssbos: [MAX_FRAMES_IN_FLIGHT]vma.BufferAlloc = undefined,
    light_mapped: [MAX_FRAMES_IN_FLIGHT][*]u8 = undefined,
    light_ssbo_size: u32 = 0,
    ubos_initialized: bool = false,

    // Accumulated light state — packed into SSBO at beginFrame
    pending_dir_lights: [lighting.MAX_DIR_LIGHTS]lighting.LightData = [_]lighting.LightData{.{}} ** lighting.MAX_DIR_LIGHTS,
    pending_point_lights: [lighting.MAX_POINT_LIGHTS]lighting.LightData = [_]lighting.LightData{.{}} ** lighting.MAX_POINT_LIGHTS,
    pending_spot_lights: [lighting.MAX_SPOT_LIGHTS]lighting.LightData = [_]lighting.LightData{.{}} ** lighting.MAX_SPOT_LIGHTS,
    num_dir_lights: u32 = 0,
    num_point_lights: u32 = 0,
    num_spot_lights: u32 = 0,

    // Default 1x1 white texture — bound when a material has no texture assigned
    default_texture: Texture = undefined,
    default_texture_initialized: bool = false,

    // active command buffer (set in beginFrame, used by draw*)
    active_cmd: c.VkCommandBuffer = null,
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
    const sdl_exts = sdl.SDL_Vulkan_GetInstanceExtensions(&sdl_ext_count);

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
    // SDL_vulkan.h includes its own copy of vulkan.h, creating separate opaque types.
    // Use @ptrCast to bridge between the vulkan_c module types and SDL's cImport types.
    const sdl_instance: sdl.VkInstance = @ptrCast(ctx.instance);
    var sdl_surface: sdl.VkSurfaceKHR = null;
    const ok = sdl.SDL_Vulkan_CreateSurface(ctx.sdl_window.?, sdl_instance, null, &sdl_surface);
    ctx.surface = @ptrCast(sdl_surface);
    return ok;
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

fn chooseSwapExtent(capabilities: *const c.VkSurfaceCapabilitiesKHR, window: *sdl.SDL_Window) c.VkExtent2D {
    if (capabilities.currentExtent.width != 0xFFFFFFFF) {
        return capabilities.currentExtent;
    }

    var w: c_int = 0;
    var h: c_int = 0;
    _ = sdl.SDL_GetWindowSizeInPixels(window, &w, &h);

    return .{
        .width = std.math.clamp(@as(u32, @intCast(w)), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
        .height = std.math.clamp(@as(u32, @intCast(h)), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
    };
}

pub fn createSwapchain(ctx: *VulkanContext) c.VkResult {
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

// ---- bridge: Renderer struct ----

pub const Renderer = struct {
    ctx: VulkanContext,

    pub fn create(window_handle: @import("tamga_sdl3_bridge").WindowHandle, debug_mode: bool) anyerror!Renderer {
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

        // VMA allocator (after logical device)
        ctx.vma_ctx = vma.VmaContext.create(ctx.instance, ctx.physical_device, ctx.device) catch {
            return VkBridgeError.VulkanFailed;
        };
        ctx.vma_initialized = true;

        // MSAA sample count (after physical device selection, before resource creation)
        ctx.msaa_samples = pipeline.getMaxUsableSampleCount(ctx.physical_device);

        // swapchain
        if (createSwapchain(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // depth buffer with MSAA (requires VMA + swapchain extent + msaa_samples)
        pipeline.createDepthResources(&ctx) catch {
            return VkBridgeError.VulkanFailed;
        };

        // MSAA color attachment (requires VMA + swapchain extent + swapchain_format + msaa_samples)
        pipeline.createMsaaColorResources(&ctx) catch {
            return VkBridgeError.VulkanFailed;
        };

        // depth prepass render pass (depth-only, requires depth_format + msaa_samples)
        if (pipeline.createDepthRenderPass(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // forward render pass with 3 attachments (requires depth_format + swapchain_format + msaa_samples)
        if (pipeline.createRenderPass(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // depth prepass framebuffers (depth-only, requires depth view + depth render pass)
        if (pipeline.createDepthFramebuffers(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // forward framebuffers with 3 attachments (requires MSAA color view + depth view + render pass)
        if (pipeline.createFramebuffers(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // command pool + buffers
        if (createCommandPool(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // UBOs (requires VMA + command pool for initial staging)
        descriptors.createUBOs(&ctx) catch {
            return VkBridgeError.VulkanFailed;
        };

        // descriptor set layouts
        if (descriptors.createDescriptorSetLayouts(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // descriptor pool + per-frame sets (requires UBOs)
        if (descriptors.createDescriptorPool(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }
        if (descriptors.allocatePerFrameDescriptorSets(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // forward graphics pipeline (requires render pass + descriptor set layouts)
        pipeline.createGraphicsPipeline(&ctx) catch {
            return VkBridgeError.VulkanFailed;
        };

        // depth prepass pipeline (requires depth render pass + pipeline layout)
        pipeline.createDepthPipeline(&ctx) catch {
            return VkBridgeError.VulkanFailed;
        };

        // sync objects
        if (createSyncObjects(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // default 1x1 white texture (used for materials with no texture assigned)
        ctx.default_texture = resources.textureCreateDefault(&ctx) catch {
            return VkBridgeError.VulkanFailed;
        };
        ctx.default_texture_initialized = true;

        // build render graph (single forward pass for now)
        rendergraph.buildRenderGraph(&ctx);

        return Renderer{ .ctx = ctx };
    }

    pub fn destroy(self: *Renderer) void {
        _ = c.vkDeviceWaitIdle(self.ctx.device);

        if (self.ctx.default_texture_initialized) {
            resources.textureFree(&self.ctx, &self.ctx.default_texture);
            self.ctx.default_texture_initialized = false;
        }

        var i: u32 = 0;
        while (i < MAX_FRAMES_IN_FLIGHT) : (i += 1) {
            if (self.ctx.render_finished[i] != null) c.vkDestroySemaphore(self.ctx.device, self.ctx.render_finished[i], null);
            if (self.ctx.image_available[i] != null) c.vkDestroySemaphore(self.ctx.device, self.ctx.image_available[i], null);
            if (self.ctx.in_flight_fences[i] != null) c.vkDestroyFence(self.ctx.device, self.ctx.in_flight_fences[i], null);
        }

        if (self.ctx.depth_pipeline != null) c.vkDestroyPipeline(self.ctx.device, self.ctx.depth_pipeline, null);
        if (self.ctx.pipeline != null) c.vkDestroyPipeline(self.ctx.device, self.ctx.pipeline, null);
        if (self.ctx.pipeline_layout != null) c.vkDestroyPipelineLayout(self.ctx.device, self.ctx.pipeline_layout, null);

        if (self.ctx.descriptor_pool != null) c.vkDestroyDescriptorPool(self.ctx.device, self.ctx.descriptor_pool, null);
        if (self.ctx.descriptor_set_layout_0 != null) c.vkDestroyDescriptorSetLayout(self.ctx.device, self.ctx.descriptor_set_layout_0, null);
        if (self.ctx.descriptor_set_layout_1 != null) c.vkDestroyDescriptorSetLayout(self.ctx.device, self.ctx.descriptor_set_layout_1, null);

        descriptors.destroyUBOs(&self.ctx);

        if (self.ctx.command_pool != null) c.vkDestroyCommandPool(self.ctx.device, self.ctx.command_pool, null);

        rendergraph.cleanupSwapchain(&self.ctx);

        if (self.ctx.render_pass != null) c.vkDestroyRenderPass(self.ctx.device, self.ctx.render_pass, null);
        if (self.ctx.depth_render_pass != null) c.vkDestroyRenderPass(self.ctx.device, self.ctx.depth_render_pass, null);

        if (self.ctx.vma_initialized) {
            self.ctx.vma_ctx.destroy();
        }

        if (self.ctx.device != null) c.vkDestroyDevice(self.ctx.device, null);

        destroyDebugMessenger(&self.ctx);

        if (self.ctx.surface != null) c.vkDestroySurfaceKHR(self.ctx.instance, self.ctx.surface, null);
        if (self.ctx.instance != null) c.vkDestroyInstance(self.ctx.instance, null);
    }

    pub fn beginFrame(self: *Renderer) bool {
        const ctx = &self.ctx;
        const frame = ctx.current_frame;

        // Pack and flush pending light state to this frame's SSBO
        lighting.flushLightSSBO(ctx, frame);

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
            if (!rendergraph.recreateSwapchain(ctx)) return false;
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

        // Store image index for endFrame and reset draw list
        ctx.graph_image_index = image_index;
        ctx.draw_count = 0;
        ctx.active_cmd = ctx.command_buffers[frame];

        return true;
    }

    pub fn endFrame(self: *Renderer) void {
        const ctx = &self.ctx;
        const frame = ctx.current_frame;
        const image_index = ctx.graph_image_index;

        // Set stable context pointer for all pass callbacks and execute
        ctx.graph.setPassUserData(0, @ptrCast(ctx));
        ctx.graph.setPassUserData(1, @ptrCast(ctx));
        ctx.graph.execute(ctx.command_buffers[frame], image_index);

        ctx.active_cmd = null;
        ctx.draw_count = 0;

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
            _ = rendergraph.recreateSwapchain(ctx);
        }

        ctx.current_frame = (frame + 1) % MAX_FRAMES_IN_FLIGHT;
    }

    pub fn setClearColor(self: *Renderer, r: f32, g: f32, b: f32, a: f32) void {
        self.ctx.clear_color = .{ .color = .{ .float32 = [4]f32{ r, g, b, a } } };
        // Update the forward pass (pass 1) clear values in the render graph
        const clear_values = [3]c.VkClearValue{
            self.ctx.clear_color,
            .{ .depthStencil = .{ .depth = 1.0, .stencil = 0 } },
            self.ctx.clear_color,
        };
        self.ctx.graph.updatePassClearValues(1, clear_values[0..]);
    }

    // setCamera — bridge-callable signature: Ptr(u8) maps to *const anyopaque in Zig.
    // view: pointer to 16 f32 values (column-major mat4)
    // proj: pointer to 16 f32 values (column-major mat4)
    // view_pos: pointer to 3 f32 values (vec3)
    pub fn setCamera(self: *Renderer, view: *const anyopaque, proj: *const anyopaque, view_pos: *const anyopaque) void {
        const frame = self.ctx.current_frame;
        const view_mat: *const [16]f32 = @ptrCast(@alignCast(view));
        const proj_mat: *const [16]f32 = @ptrCast(@alignCast(proj));
        const vpos: *const [3]f32 = @ptrCast(@alignCast(view_pos));
        const ubo = CameraUBO{
            .view = view_mat.*,
            .proj = proj_mat.*,
            .view_pos = vpos.*,
        };
        @memcpy(self.ctx.camera_mapped[frame][0..@sizeOf(CameraUBO)], std.mem.asBytes(&ubo));
    }

    // draw — bridge-callable: queues a mesh for rendering with the given material and model matrix.
    // Draw calls are collected into a list and executed by the render graph's forward pass.
    pub fn draw(self: *Renderer, mesh_id: MeshId, material_id: MaterialId, model_matrix: *const anyopaque) void {
        if (self.ctx.draw_count >= rendergraph.MAX_DRAW_CALLS) return;
        const mesh = resources.getMesh(mesh_id.id) orelse return;
        const mat = resources.getMaterial(material_id.id) orelse return;
        const model_mat: *const [16]f32 = @ptrCast(@alignCast(model_matrix));
        self.ctx.draw_list[self.ctx.draw_count] = rendergraph.DrawCall{
            .vertex_buffer = mesh.vertex_buffer,
            .index_buffer = mesh.index_buffer,
            .index_count = mesh.index_count,
            .material_descriptor_set = mat.descriptor_set,
            .model_matrix = model_mat.*,
        };
        self.ctx.draw_count += 1;
    }

    // createMesh: bridge func — allocates GPU vertex + index buffers via VMA, returns a MeshId.
    // vertices: raw byte pointer to packed D-05 vertex data
    // vertex_byte_size: total byte count of vertex array
    // indices: raw byte pointer to u32 index array
    // index_count: number of u32 indices
    pub fn createMesh(self: *Renderer, vertices: *const anyopaque, vertex_byte_size: u32, indices: *const anyopaque, index_count: u32) anyerror!MeshId {
        const vert_ptr: [*]const u8 = @ptrCast(vertices);
        const idx_ptr: [*]const u32 = @ptrCast(@alignCast(indices));
        const mesh_buffers = try resources.createMeshBuffers(&self.ctx, vert_ptr, vertex_byte_size, idx_ptr, index_count);
        const slot = resources.allocMeshSlot(mesh_buffers) orelse return VkBridgeError.VulkanFailed;
        return MeshId{ .id = slot };
    }

    // destroyMesh: bridge func — releases vertex and index buffer allocations.
    pub fn destroyMesh(self: *Renderer, id: MeshId) void {
        if (resources.getMesh(id.id)) |mesh| {
            self.ctx.vma_ctx.destroyBuffer(mesh.vertex_buffer, mesh.vertex_allocation);
            self.ctx.vma_ctx.destroyBuffer(mesh.index_buffer, mesh.index_allocation);
            resources.freeMeshSlot(id.id);
        }
    }

    // loadTexture: bridge func — loads a texture from a PNG/JPG file via stb_image, returns a TextureId.
    // path: Orhon String slice ([]const u8) — converted to null-terminated for stbi_load.
    pub fn loadTexture(self: *Renderer, path: []const u8) anyerror!TextureId {
        // Convert Orhon String slice to null-terminated C string for stbi_load.
        // Use a stack buffer for paths up to 1023 bytes (covers all practical file paths).
        var path_buf: [1024]u8 = undefined;
        const len = @min(path.len, path_buf.len - 1);
        @memcpy(path_buf[0..len], path[0..len]);
        path_buf[len] = 0;
        const tex = try resources.textureLoad(&self.ctx, @ptrCast(&path_buf));
        const slot = resources.allocTextureSlot(tex) orelse return VkBridgeError.VulkanFailed;
        return TextureId{ .id = slot };
    }

    // destroyTexture: bridge func — releases texture GPU resources by ID.
    pub fn destroyTexture(self: *Renderer, id: TextureId) void {
        if (resources.getTexture(id.id)) |tex| {
            resources.textureFree(&self.ctx, tex);
            resources.freeTextureSlot(id.id);
        }
    }

    // createMaterial: bridge func — creates a material with Phong properties and a texture, returns a MaterialId.
    // diffuse_r/g/b/a: RGBA diffuse color multiplier (1,1,1,1 = texture color unmodified)
    // specular: specular intensity (0.0 = no specular, 1.0 = full)
    // shininess: Phong shininess exponent (e.g. 32.0 = moderately shiny)
    // texture_id: ID of a previously loaded texture (from loadTexture)
    pub fn createMaterial(
        self: *Renderer,
        diffuse_r: f32,
        diffuse_g: f32,
        diffuse_b: f32,
        diffuse_a: f32,
        specular: f32,
        shininess: f32,
        texture_id: TextureId,
    ) anyerror!MaterialId {
        const tex = resources.getTexture(texture_id.id) orelse return VkBridgeError.VulkanFailed;
        const mat = try resources.materialCreate(&self.ctx, diffuse_r, diffuse_g, diffuse_b, diffuse_a, specular, shininess, tex);
        const slot = resources.allocMaterialSlot(mat) orelse return VkBridgeError.VulkanFailed;
        return MaterialId{ .id = slot };
    }

    // destroyMaterial: bridge func — releases material GPU resources by ID.
    pub fn destroyMaterial(self: *Renderer, id: MaterialId) void {
        if (resources.getMaterial(id.id)) |mat| {
            resources.materialFree(&self.ctx, mat);
            resources.freeMaterialSlot(id.id);
        }
    }

    // setDirLight: sets a directional light at the given index (0..3).
    // dir_x/y/z: normalized direction the light travels (points from light source toward scene)
    // r/g/b: light color (1.0, 1.0, 1.0 = white)
    pub fn setDirLight(self: *Renderer, index: u32, dir_x: f32, dir_y: f32, dir_z: f32, r: f32, g: f32, b: f32) void {
        if (index >= lighting.MAX_DIR_LIGHTS) return;
        self.ctx.pending_dir_lights[index] = lighting.LightData{
            .direction_type = [4]f32{ dir_x, dir_y, dir_z, lighting.LIGHT_TYPE_DIRECTIONAL },
            .color = [4]f32{ r, g, b, 0.0 },
        };
    }

    // setPointLight: sets a point light at the given index (0..125).
    // pos_x/y/z: world-space position
    // r/g/b: light color
    // constant/linear/quadratic: attenuation factors (e.g. 1.0, 0.09, 0.032 for ~50 unit range)
    pub fn setPointLight(
        self: *Renderer,
        index: u32,
        pos_x: f32,
        pos_y: f32,
        pos_z: f32,
        r: f32,
        g: f32,
        b: f32,
        constant: f32,
        linear: f32,
        quadratic: f32,
    ) void {
        if (index >= lighting.MAX_POINT_LIGHTS) return;
        self.ctx.pending_point_lights[index] = lighting.LightData{
            .position_range = [4]f32{ pos_x, pos_y, pos_z, 0.0 },
            .direction_type = [4]f32{ 0.0, 0.0, 0.0, lighting.LIGHT_TYPE_POINT },
            .color = [4]f32{ r, g, b, 0.0 },
            .attenuation = [4]f32{ constant, linear, quadratic, 0.0 },
        };
    }

    // setSpotLight: sets a spot light at the given index (0..125).
    // pos_x/y/z: world-space position
    // dir_x/y/z: direction the spot light points
    // r/g/b: light color
    // inner_angle/outer_angle: cone angles in radians (cosines stored internally)
    // range: maximum light range (used for attenuation and cluster culling)
    pub fn setSpotLight(
        self: *Renderer,
        index: u32,
        pos_x: f32,
        pos_y: f32,
        pos_z: f32,
        dir_x: f32,
        dir_y: f32,
        dir_z: f32,
        r: f32,
        g: f32,
        b: f32,
        inner_angle: f32,
        outer_angle: f32,
        range: f32,
    ) void {
        if (index >= lighting.MAX_SPOT_LIGHTS) return;
        self.ctx.pending_spot_lights[index] = lighting.LightData{
            .position_range = [4]f32{ pos_x, pos_y, pos_z, range },
            .direction_type = [4]f32{ dir_x, dir_y, dir_z, lighting.LIGHT_TYPE_SPOT },
            .color = [4]f32{ r, g, b, 0.0 },
            .attenuation = [4]f32{ 1.0, 0.09, 0.032, 0.0 },
            .spot_params = [4]f32{ @cos(inner_angle), @cos(outer_angle), 0.0, 0.0 },
        };
    }

    // setLightCounts: sets how many directional, point, and spot lights are active.
    // Must be called after setting lights to activate them.
    pub fn setLightCounts(self: *Renderer, num_dir: u32, num_point: u32, num_spot: u32) void {
        self.ctx.num_dir_lights = @min(num_dir, lighting.MAX_DIR_LIGHTS);
        self.ctx.num_point_lights = @min(num_point, lighting.MAX_POINT_LIGHTS);
        self.ctx.num_spot_lights = @min(num_spot, lighting.MAX_SPOT_LIGHTS);
    }
};

