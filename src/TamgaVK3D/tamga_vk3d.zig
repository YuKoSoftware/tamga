const std = @import("std");
const vma = @import("tamga_vulkan_bridge");
const c = @import("vulkan_c").c;
// SDL types are imported via a local @cImport since SDL headers are only used in this module.
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
});
// stb_image: single-header C library for PNG/JPG/BMP texture loading.
// Implementation is compiled via stb_image_impl.c (added as a C source via #cimport source:).
// Using extern declarations avoids the @cImport path-resolution issue in the generated bridge:
// the bridge file lives in .orh-cache/generated/ and cannot resolve relative "libs/stb_image.h".
const stbi = struct {
    pub extern fn stbi_load(filename: [*:0]const u8, x: *c_int, y: *c_int, comp: *c_int, req_comp: c_int) ?[*]u8;
    pub extern fn stbi_image_free(retval_from_stbi_load: ?[*]u8) void;
    pub extern fn stbi_failure_reason() [*:0]const u8;
};

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
        clear_values: []const c.VkClearValue,
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
            .clearValueCount = @intCast(clear_values.len),
            .pClearValues = clear_values.ptr,
        };

        c.vkCmdBeginRenderPass(command_buffer, &render_pass_info, c.VK_SUBPASS_CONTENTS_INLINE);
        // render pass is now open — draw calls are recorded between beginFrame and endFrame
        // endFrame calls vkCmdEndRenderPass before submitting
    }
};

// ---- error types for bridge ----

const VkBridgeError = error{VulkanFailed};

// ---- CameraUBO (std140 layout, 144 bytes) ----
// view: 64 bytes, proj: 64 bytes, view_pos: 12 bytes, _pad: 4 bytes

pub const CameraUBO = extern struct {
    view: [16]f32,
    proj: [16]f32,
    view_pos: [3]f32,
    _pad: f32 = 0.0,
};

// ---- LightUBOData (std140 layout, matches mesh.frag.glsl exactly) ----
// DirLightData: direction vec4 (16) + color vec4 (16) = 32 bytes
// PointLightData: position vec4 (16) + color vec4 (16) + constant/linear/quadratic/pad (16) = 48 bytes
// 4 dir lights (128) + 8 point lights (384) + counts + pad (16) = 528 bytes

pub const DirLightData = extern struct {
    direction: [4]f32 = [_]f32{0.0} ** 4, // vec4, w unused
    color: [4]f32 = [_]f32{0.0} ** 4, // vec4, w unused
};

pub const PointLightData = extern struct {
    position: [4]f32 = [_]f32{0.0} ** 4, // vec4, w unused
    color: [4]f32 = [_]f32{0.0} ** 4, // vec4, w unused
    constant: f32 = 1.0,
    linear: f32 = 0.09,
    quadratic: f32 = 0.032,
    _pad: f32 = 0.0,
};

const LightUBOData = extern struct {
    dir_lights: [4]DirLightData = [_]DirLightData{.{}} ** 4,
    point_lights: [8]PointLightData = [_]PointLightData{.{}} ** 8,
    num_dir_lights: i32 = 0,
    num_point_lights: i32 = 0,
    _pad: [2]i32 = [_]i32{0} ** 2,
};

// ---- MaterialUBOData (std140 layout, matches mesh.frag.glsl exactly) ----
// diffuseColor vec4 (16) + specular f32 (4) + shininess f32 (4) + pad (8) = 32 bytes

pub const MaterialUBOData = extern struct {
    diffuse_color: [4]f32 = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
    specular: f32 = 0.5,
    shininess: f32 = 32.0,
    _pad: [2]f32 = [_]f32{0.0} ** 2,
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
    sdl_window: ?*sdl.SDL_Window = null,
    debug_mode: bool = false,

    // render graph
    graph: RenderGraph = RenderGraph.init(),

    // clear colors (index 0 = color, index 1 = depth)
    clear_color: c.VkClearValue = .{ .color = .{ .float32 = [4]f32{ 0.0, 0.0, 0.0, 1.0 } } },

    // state
    framebuffer_resized: bool = false,

    // VMA allocator
    vma_ctx: vma.VmaContext = undefined,
    vma_initialized: bool = false,

    // graphics pipeline
    pipeline: c.VkPipeline = null,
    pipeline_layout: c.VkPipelineLayout = null,
    descriptor_set_layout_0: c.VkDescriptorSetLayout = null,
    descriptor_set_layout_1: c.VkDescriptorSetLayout = null,

    // descriptor pool and per-frame sets
    descriptor_pool: c.VkDescriptorPool = null,
    descriptor_sets_0: [MAX_FRAMES_IN_FLIGHT]c.VkDescriptorSet = [_]c.VkDescriptorSet{null} ** MAX_FRAMES_IN_FLIGHT,

    // UBOs (double-buffered)
    camera_ubos: [MAX_FRAMES_IN_FLIGHT]vma.BufferAlloc = undefined,
    camera_mapped: [MAX_FRAMES_IN_FLIGHT][*]u8 = undefined,
    light_ubos: [MAX_FRAMES_IN_FLIGHT]vma.BufferAlloc = undefined,
    light_mapped: [MAX_FRAMES_IN_FLIGHT][*]u8 = undefined,
    ubos_initialized: bool = false,

    // Accumulated light state — written to UBO at next beginFrame or setLights call
    pending_lights: LightUBOData = .{},

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

// getMaxUsableSampleCount returns the highest sample count supported for both
// color and depth attachments, capped at VK_SAMPLE_COUNT_4_BIT per VK3-16
// (general cross-vendor performance optimization — 4x is the sweet spot for
// quality/performance on all hardware tiers).
fn getMaxUsableSampleCount(physical_device: c.VkPhysicalDevice) c.VkSampleCountFlagBits {
    var props: c.VkPhysicalDeviceProperties = undefined;
    c.vkGetPhysicalDeviceProperties(physical_device, &props);

    const counts = props.limits.framebufferColorSampleCounts &
        props.limits.framebufferDepthSampleCounts;

    // Check 4x first (our cap per VK3-16), then fall back to lower counts
    if (counts & c.VK_SAMPLE_COUNT_4_BIT != 0) return c.VK_SAMPLE_COUNT_4_BIT;
    if (counts & c.VK_SAMPLE_COUNT_2_BIT != 0) return c.VK_SAMPLE_COUNT_2_BIT;
    return c.VK_SAMPLE_COUNT_1_BIT;
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

// ---- depth buffer ----

fn findDepthFormat(physical_device: c.VkPhysicalDevice) c.VkFormat {
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

fn createDepthResources(ctx: *VulkanContext) anyerror!void {
    ctx.depth_format = findDepthFormat(ctx.physical_device);

    // Create depth image via VMA with MSAA sample count
    const image_alloc = try ctx.vma_ctx.createImageWithSamples(
        ctx.swapchain_extent.width,
        ctx.swapchain_extent.height,
        ctx.depth_format,
        c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
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

fn destroyDepthResources(ctx: *VulkanContext) void {
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

fn createMsaaColorResources(ctx: *VulkanContext) anyerror!void {
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

fn destroyMsaaColorResources(ctx: *VulkanContext) void {
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

fn createRenderPass(ctx: *VulkanContext) c.VkResult {
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

    // Attachment [1]: MSAA depth — rendered to, not stored
    const depth_attachment = c.VkAttachmentDescription{
        .flags = 0,
        .format = ctx.depth_format,
        .samples = ctx.msaa_samples,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
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
        .layout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
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

// ---- framebuffers (color + depth) ----

fn createFramebuffers(ctx: *VulkanContext) c.VkResult {
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

// ---- .spv shader loading ----

fn createShaderModule(device: c.VkDevice, bytecode: []const u8) ?c.VkShaderModule {
    if (bytecode.len == 0) return null;

    const shader_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = bytecode.len,
        .pCode = @ptrCast(@alignCast(bytecode.ptr)),
    };

    var shader_module: c.VkShaderModule = null;
    const result = c.vkCreateShaderModule(device, &shader_info, null, &shader_module);
    if (result != c.VK_SUCCESS) return null;

    return shader_module;
}

// Embedded SPIR-V bytecode — compiled offline, baked into the binary via shaders_spv.c.
// No filesystem access needed at runtime; binary is fully portable.
extern "c" fn get_mesh_vert_spv(out_len: *c_uint) [*]const u8;
extern "c" fn get_mesh_frag_spv(out_len: *c_uint) [*]const u8;

// ---- descriptor set layouts ----

fn createDescriptorSetLayouts(ctx: *VulkanContext) c.VkResult {
    // Set 0 (per-frame): binding 0 = CameraUBO (VERTEX | FRAGMENT), binding 1 = LightUBO (FRAGMENT)
    {
        const bindings = [2]c.VkDescriptorSetLayoutBinding{
            .{
                .binding = 0,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = 1,
                .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
                .pImmutableSamplers = null,
            },
            .{
                .binding = 1,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
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

fn createUBOs(ctx: *VulkanContext) anyerror!void {
    const ubo_usage: u32 = 0x00000010; // VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT

    var i: u32 = 0;
    while (i < MAX_FRAMES_IN_FLIGHT) : (i += 1) {
        // Camera UBO — host-visible + persistently mapped
        const cam_alloc = try ctx.vma_ctx.createBuffer(@sizeOf(CameraUBO), ubo_usage, false);
        ctx.camera_ubos[i] = cam_alloc;

        // Map camera UBO
        ctx.camera_mapped[i] = ctx.vma_ctx.mapBuffer(cam_alloc.allocation) orelse return VkBridgeError.VulkanFailed;

        // Light UBO
        const light_alloc = try ctx.vma_ctx.createBuffer(@sizeOf(LightUBOData), ubo_usage, false);
        ctx.light_ubos[i] = light_alloc;

        // Map light UBO and zero it (no lights active by default)
        ctx.light_mapped[i] = ctx.vma_ctx.mapBuffer(light_alloc.allocation) orelse return VkBridgeError.VulkanFailed;

        const default_light = LightUBOData{};
        @memcpy(ctx.light_mapped[i][0..@sizeOf(LightUBOData)], std.mem.asBytes(&default_light));
    }

    ctx.ubos_initialized = true;
}

fn destroyUBOs(ctx: *VulkanContext) void {
    if (!ctx.ubos_initialized) return;
    var i: u32 = 0;
    while (i < MAX_FRAMES_IN_FLIGHT) : (i += 1) {
        ctx.vma_ctx.unmapBuffer(ctx.camera_ubos[i].allocation);
        ctx.vma_ctx.destroyBuffer(ctx.camera_ubos[i].buffer, ctx.camera_ubos[i].allocation);
        ctx.vma_ctx.unmapBuffer(ctx.light_ubos[i].allocation);
        ctx.vma_ctx.destroyBuffer(ctx.light_ubos[i].buffer, ctx.light_ubos[i].allocation);
    }
    ctx.ubos_initialized = false;
}

// ---- descriptor pool and per-frame sets ----

fn createDescriptorPool(ctx: *VulkanContext) c.VkResult {
    // Per Pitfall 5 in research: size the pool generously to avoid VK_ERROR_OUT_OF_POOL_MEMORY
    const pool_sizes = [2]c.VkDescriptorPoolSize{
        .{
            .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 16,
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
        .poolSizeCount = 2,
        .pPoolSizes = &pool_sizes,
    };

    return c.vkCreateDescriptorPool(ctx.device, &pool_info, null, &ctx.descriptor_pool);
}

fn allocatePerFrameDescriptorSets(ctx: *VulkanContext) c.VkResult {
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

    // Write camera UBO and light UBO bindings for each frame
    i = 0;
    while (i < MAX_FRAMES_IN_FLIGHT) : (i += 1) {
        const cam_buf_info = c.VkDescriptorBufferInfo{
            .buffer = ctx.camera_ubos[i].buffer,
            .offset = 0,
            .range = @sizeOf(CameraUBO),
        };

        const light_buf_info = c.VkDescriptorBufferInfo{
            .buffer = ctx.light_ubos[i].buffer,
            .offset = 0,
            .range = @sizeOf(LightUBOData),
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
                .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .pImageInfo = null,
                .pBufferInfo = &light_buf_info,
                .pTexelBufferView = null,
            },
        };

        c.vkUpdateDescriptorSets(ctx.device, 2, &writes, 0, null);
    }

    return c.VK_SUCCESS;
}

// ---- graphics pipeline ----

fn createGraphicsPipeline(ctx: *VulkanContext) anyerror!void {
    // Create shader modules from embedded SPIR-V bytecode (baked in via shaders_spv.c)
    var vert_len: c_uint = 0;
    const vert_ptr = get_mesh_vert_spv(&vert_len);
    const vert_module = createShaderModule(ctx.device, vert_ptr[0..vert_len]) orelse {
        std.debug.print("[TamgaVK3D] Failed to create vertex shader module\n", .{});
        return VkBridgeError.VulkanFailed;
    };
    defer c.vkDestroyShaderModule(ctx.device, vert_module, null);

    var frag_len: c_uint = 0;
    const frag_ptr = get_mesh_frag_spv(&frag_len);
    const frag_module = createShaderModule(ctx.device, frag_ptr[0..frag_len]) orelse {
        std.debug.print("[TamgaVK3D] Failed to create fragment shader module\n", .{});
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

// ---- mesh buffer management ----

fn createMeshBuffers(
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

// ---- one-shot command buffer submit helper ----

fn submitOneShot(ctx: *VulkanContext, cmd: c.VkCommandBuffer) void {
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

fn beginOneShot(ctx: *VulkanContext) ?c.VkCommandBuffer {
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

fn transitionImageLayout(
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

// ---- texture creation and destruction ----

fn textureLoad(ctx: *VulkanContext, path: [*:0]const u8) anyerror!Texture {
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

fn textureFree(ctx: *VulkanContext, tex: *Texture) void {
    if (tex.sampler != null) c.vkDestroySampler(ctx.device, tex.sampler, null);
    if (tex.view != null) c.vkDestroyImageView(ctx.device, tex.view, null);
    ctx.vma_ctx.destroyImage(tex.image, tex.allocation);
}

// createDefaultTexture creates a 1x1 white RGBA texture for materials with no texture assigned.
fn textureCreateDefault(ctx: *VulkanContext) anyerror!Texture {
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

fn materialCreate(
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
    const mat_alloc = try ctx.vma_ctx.createBuffer(@sizeOf(MaterialUBOData), ubo_usage, false);
    const mat_mapped = ctx.vma_ctx.mapBuffer(mat_alloc.allocation) orelse {
        ctx.vma_ctx.destroyBuffer(mat_alloc.buffer, mat_alloc.allocation);
        return VkBridgeError.VulkanFailed;
    };

    // Write initial MaterialUBO data
    const ubo_data = MaterialUBOData{
        .diffuse_color = [4]f32{ diffuse_r, diffuse_g, diffuse_b, diffuse_a },
        .specular = specular,
        .shininess = shininess,
    };
    @memcpy(mat_mapped[0..@sizeOf(MaterialUBOData)], std.mem.asBytes(&ubo_data));

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
        .range = @sizeOf(MaterialUBOData),
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

fn materialFree(ctx: *VulkanContext, mat: *Material) void {
    ctx.vma_ctx.unmapBuffer(mat.material_ubo.allocation);
    ctx.vma_ctx.destroyBuffer(mat.material_ubo.buffer, mat.material_ubo.allocation);
    // descriptor set is freed with the pool — no explicit free needed
}

// ---- swapchain cleanup + recreation ----

fn cleanupSwapchain(ctx: *VulkanContext) void {
    // Destroy in reverse creation order:
    // 1. Framebuffers
    var i: u32 = 0;
    while (i < ctx.swapchain_image_count) : (i += 1) {
        if (ctx.framebuffers[i] != null) {
            c.vkDestroyFramebuffer(ctx.device, ctx.framebuffers[i], null);
            ctx.framebuffers[i] = null;
        }
    }

    // 2. MSAA color image + view (VMA free)
    destroyMsaaColorResources(ctx);

    // 3. Depth image + view (VMA free)
    destroyDepthResources(ctx);

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

fn recreateSwapchain(ctx: *VulkanContext) bool {
    // handle minimized window
    var w: c_int = 0;
    var h: c_int = 0;
    _ = sdl.SDL_GetWindowSizeInPixels(ctx.sdl_window.?, &w, &h);
    if (w == 0 or h == 0) return false;

    _ = c.vkDeviceWaitIdle(ctx.device);

    const old_format = ctx.swapchain_format;
    cleanupSwapchain(ctx);

    // 1. Recreate swapchain + image views (updates swapchain_format and swapchain_extent)
    if (createSwapchain(ctx) != c.VK_SUCCESS) return false;

    // Handle format change: recreate render pass and pipeline if format changed (rare)
    if (ctx.swapchain_format != old_format) {
        if (ctx.render_pass != null) {
            c.vkDestroyRenderPass(ctx.device, ctx.render_pass, null);
            ctx.render_pass = null;
        }
        if (ctx.pipeline != null) {
            c.vkDestroyPipeline(ctx.device, ctx.pipeline, null);
            ctx.pipeline = null;
        }
        if (createRenderPass(ctx) != c.VK_SUCCESS) return false;
        createGraphicsPipeline(ctx) catch return false;
    }

    // 2. Recreate depth resources with MSAA sample count and new extent
    createDepthResources(ctx) catch return false;

    // 3. Recreate MSAA color resources with new extent
    createMsaaColorResources(ctx) catch return false;

    // 4. Recreate framebuffers with 3 attachments
    if (createFramebuffers(ctx) != c.VK_SUCCESS) return false;

    return true;
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
        ctx.msaa_samples = getMaxUsableSampleCount(ctx.physical_device);

        // swapchain
        if (createSwapchain(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // depth buffer with MSAA (requires VMA + swapchain extent + msaa_samples)
        createDepthResources(&ctx) catch {
            return VkBridgeError.VulkanFailed;
        };

        // MSAA color attachment (requires VMA + swapchain extent + swapchain_format + msaa_samples)
        createMsaaColorResources(&ctx) catch {
            return VkBridgeError.VulkanFailed;
        };

        // render pass with 3 attachments (requires depth_format + swapchain_format + msaa_samples)
        if (createRenderPass(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // framebuffers with 3 attachments (requires MSAA color view + depth view + render pass)
        if (createFramebuffers(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // command pool + buffers
        if (createCommandPool(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // UBOs (requires VMA + command pool for initial staging)
        createUBOs(&ctx) catch {
            return VkBridgeError.VulkanFailed;
        };

        // descriptor set layouts
        if (createDescriptorSetLayouts(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // descriptor pool + per-frame sets (requires UBOs)
        if (createDescriptorPool(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }
        if (allocatePerFrameDescriptorSets(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // graphics pipeline (requires render pass + descriptor set layouts)
        createGraphicsPipeline(&ctx) catch {
            return VkBridgeError.VulkanFailed;
        };

        // sync objects
        if (createSyncObjects(&ctx) != c.VK_SUCCESS) {
            return VkBridgeError.VulkanFailed;
        }

        // default 1x1 white texture (used for materials with no texture assigned)
        ctx.default_texture = textureCreateDefault(&ctx) catch {
            return VkBridgeError.VulkanFailed;
        };
        ctx.default_texture_initialized = true;

        return Renderer{ .ctx = ctx };
    }

    pub fn destroy(self: *Renderer) void {
        _ = c.vkDeviceWaitIdle(self.ctx.device);

        if (self.ctx.default_texture_initialized) {
            textureFree(&self.ctx, &self.ctx.default_texture);
            self.ctx.default_texture_initialized = false;
        }

        var i: u32 = 0;
        while (i < MAX_FRAMES_IN_FLIGHT) : (i += 1) {
            if (self.ctx.render_finished[i] != null) c.vkDestroySemaphore(self.ctx.device, self.ctx.render_finished[i], null);
            if (self.ctx.image_available[i] != null) c.vkDestroySemaphore(self.ctx.device, self.ctx.image_available[i], null);
            if (self.ctx.in_flight_fences[i] != null) c.vkDestroyFence(self.ctx.device, self.ctx.in_flight_fences[i], null);
        }

        if (self.ctx.pipeline != null) c.vkDestroyPipeline(self.ctx.device, self.ctx.pipeline, null);
        if (self.ctx.pipeline_layout != null) c.vkDestroyPipelineLayout(self.ctx.device, self.ctx.pipeline_layout, null);

        if (self.ctx.descriptor_pool != null) c.vkDestroyDescriptorPool(self.ctx.device, self.ctx.descriptor_pool, null);
        if (self.ctx.descriptor_set_layout_0 != null) c.vkDestroyDescriptorSetLayout(self.ctx.device, self.ctx.descriptor_set_layout_0, null);
        if (self.ctx.descriptor_set_layout_1 != null) c.vkDestroyDescriptorSetLayout(self.ctx.device, self.ctx.descriptor_set_layout_1, null);

        destroyUBOs(&self.ctx);

        if (self.ctx.command_pool != null) c.vkDestroyCommandPool(self.ctx.device, self.ctx.command_pool, null);

        cleanupSwapchain(&self.ctx);

        if (self.ctx.render_pass != null) c.vkDestroyRenderPass(self.ctx.device, self.ctx.render_pass, null);

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

        // Flush pending light state to this frame's UBO before rendering
        @memcpy(ctx.light_mapped[frame][0..@sizeOf(LightUBOData)], std.mem.asBytes(&ctx.pending_lights));

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

        // Three clear values matching render pass attachments:
        // [0] MSAA color, [1] MSAA depth, [2] resolve (DONT_CARE load op — value unused)
        const clear_values = [3]c.VkClearValue{
            ctx.clear_color,
            .{ .depthStencil = .{ .depth = 1.0, .stencil = 0 } },
            ctx.clear_color, // unused (resolve has DONT_CARE load op)
        };

        ctx.graph.execute(
            ctx.command_buffers[frame],
            ctx.render_pass,
            ctx.framebuffers[image_index],
            ctx.swapchain_extent,
            clear_values[0..],
        );

        // Set active command buffer for draw calls
        ctx.active_cmd = ctx.command_buffers[frame];

        // Set dynamic viewport and scissor
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
        c.vkCmdSetViewport(ctx.active_cmd, 0, 1, &viewport);
        c.vkCmdSetScissor(ctx.active_cmd, 0, 1, &scissor);

        // Bind pipeline and per-frame descriptor set
        c.vkCmdBindPipeline(ctx.active_cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.pipeline);
        c.vkCmdBindDescriptorSets(
            ctx.active_cmd,
            c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            ctx.pipeline_layout,
            0, // set 0
            1,
            &ctx.descriptor_sets_0[frame],
            0,
            null,
        );

        // store image index for endFrame
        ctx.graph.current_image_index = image_index;

        return true;
    }

    pub fn endFrame(self: *Renderer) void {
        const ctx = &self.ctx;
        const frame = ctx.current_frame;
        const image_index = ctx.graph.current_image_index;

        // end the render pass opened by beginFrame → graph.execute
        c.vkCmdEndRenderPass(ctx.command_buffers[frame]);

        ctx.active_cmd = null;

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

    // draw — bridge-callable: draws a Mesh with a Material and model matrix.
    // mesh: const &Mesh (read-only borrow of the Mesh bridge struct)
    // material: const &Material (read-only borrow — descriptor set bound as Set 1)
    // model_matrix: Ptr(u8) = pointer to 16 f32 values (column-major mat4, push constant)
    pub fn draw(self: *Renderer, mesh: *const Mesh, material: *const Material, model_matrix: *const anyopaque) void {
        const cmd = self.ctx.active_cmd;
        if (cmd == null) return;

        // Bind material descriptor set (Set 1: MaterialUBO + texture sampler)
        c.vkCmdBindDescriptorSets(
            cmd,
            c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            self.ctx.pipeline_layout,
            1, // set 1
            1,
            &material.descriptor_set,
            0,
            null,
        );

        const model_mat: *const [16]f32 = @ptrCast(@alignCast(model_matrix));
        const offset: u64 = 0;
        const vb = mesh.mesh_buffers.vertex_buffer;
        c.vkCmdBindVertexBuffers(cmd, 0, 1, &vb, &offset);
        c.vkCmdBindIndexBuffer(cmd, mesh.mesh_buffers.index_buffer, 0, c.VK_INDEX_TYPE_UINT32);
        c.vkCmdPushConstants(cmd, self.ctx.pipeline_layout, c.VK_SHADER_STAGE_VERTEX_BIT, 0, 64, model_mat);
        c.vkCmdDrawIndexed(cmd, mesh.mesh_buffers.index_count, 1, 0, 0, 0);
    }

    // createMesh: bridge func — allocates GPU vertex + index buffers via VMA.
    // vertices: raw byte pointer to packed D-05 vertex data
    // vertex_byte_size: total byte count of vertex array
    // indices: raw byte pointer to u32 index array
    // index_count: number of u32 indices
    pub fn createMesh(self: *Renderer, vertices: *const anyopaque, vertex_byte_size: u32, indices: *const anyopaque, index_count: u32) anyerror!Mesh {
        const vert_ptr: [*]const u8 = @ptrCast(vertices);
        const idx_ptr: [*]const u32 = @ptrCast(@alignCast(indices));
        const buffers = try createMeshBuffers(&self.ctx, vert_ptr, vertex_byte_size, idx_ptr, index_count);
        return Mesh{ .mesh_buffers = buffers };
    }

    // destroyMesh: bridge func — releases vertex and index buffer allocations.
    pub fn destroyMesh(self: *Renderer, mesh: *const Mesh) void {
        self.ctx.vma_ctx.destroyBuffer(mesh.mesh_buffers.vertex_buffer, mesh.mesh_buffers.vertex_allocation);
        self.ctx.vma_ctx.destroyBuffer(mesh.mesh_buffers.index_buffer, mesh.mesh_buffers.index_allocation);
    }

    // loadTexture: bridge func — loads a texture from a PNG/JPG file via stb_image.
    // path: Orhon String slice ([]const u8) — converted to null-terminated for stbi_load.
    pub fn loadTexture(self: *Renderer, path: []const u8) anyerror!Texture {
        // Convert Orhon String slice to null-terminated C string for stbi_load.
        // Use a stack buffer for paths up to 1023 bytes (covers all practical file paths).
        var path_buf: [1024]u8 = undefined;
        const len = @min(path.len, path_buf.len - 1);
        @memcpy(path_buf[0..len], path[0..len]);
        path_buf[len] = 0;
        return textureLoad(&self.ctx, @ptrCast(&path_buf));
    }

    // destroyTexture: bridge func — releases texture GPU resources.
    // Takes const pointer to match bridge safety rules; casts to mutable internally.
    pub fn destroyTexture(self: *Renderer, tex: *const Texture) void {
        textureFree(&self.ctx, @constCast(tex));
    }

    // getDefaultTexture: returns a pointer to the built-in 1x1 white texture.
    // Used to create untextured materials (material color shows directly).
    pub fn getDefaultTexture(self: *Renderer) *Texture {
        return &self.ctx.default_texture;
    }

    // createMaterial: bridge func — creates a material with Phong properties and a texture.
    // diffuse_r/g/b/a: RGBA diffuse color multiplier (1,1,1,1 = texture color unmodified)
    // specular: specular intensity (0.0 = no specular, 1.0 = full)
    // shininess: Phong shininess exponent (e.g. 32.0 = moderately shiny)
    // texture: passed by value — Orhon compiler does not auto-borrow bridge structs in
    //   error-union-returning calls; value copy is safe since Texture fields are GPU handles.
    pub fn createMaterial(
        self: *Renderer,
        diffuse_r: f32,
        diffuse_g: f32,
        diffuse_b: f32,
        diffuse_a: f32,
        specular: f32,
        shininess: f32,
        texture: *const Texture,
    ) anyerror!Material {
        return materialCreate(&self.ctx, diffuse_r, diffuse_g, diffuse_b, diffuse_a, specular, shininess, texture);
    }

    // destroyMaterial: bridge func — releases material GPU resources.
    // Takes const pointer to match bridge safety rules; casts to mutable internally.
    pub fn destroyMaterial(self: *Renderer, mat: *const Material) void {
        materialFree(&self.ctx, @constCast(mat));
    }

    // setDirLight: sets a directional light at the given index (0..3).
    // The light data is accumulated and written to the UBO at the next beginFrame call.
    // dir_x/y/z: normalized direction the light travels (points from light source toward scene)
    // r/g/b: light color (1.0, 1.0, 1.0 = white)
    pub fn setDirLight(self: *Renderer, index: u32, dir_x: f32, dir_y: f32, dir_z: f32, r: f32, g: f32, b: f32) void {
        if (index >= 4) return;
        self.ctx.pending_lights.dir_lights[index] = DirLightData{
            .direction = [4]f32{ dir_x, dir_y, dir_z, 0.0 },
            .color = [4]f32{ r, g, b, 0.0 },
        };
    }

    // setPointLight: sets a point light at the given index (0..7).
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
        if (index >= 8) return;
        self.ctx.pending_lights.point_lights[index] = PointLightData{
            .position = [4]f32{ pos_x, pos_y, pos_z, 0.0 },
            .color = [4]f32{ r, g, b, 0.0 },
            .constant = constant,
            .linear = linear,
            .quadratic = quadratic,
        };
    }

    // setLightCounts: sets how many directional and point lights are active.
    // Must be called after setDirLight/setPointLight to activate the lights in the shader.
    pub fn setLightCounts(self: *Renderer, num_dir: u32, num_point: u32) void {
        self.ctx.pending_lights.num_dir_lights = @intCast(@min(num_dir, 4));
        self.ctx.pending_lights.num_point_lights = @intCast(@min(num_point, 8));

        // Write updated light data to the current frame's UBO immediately
        const frame = self.ctx.current_frame;
        @memcpy(self.ctx.light_mapped[frame][0..@sizeOf(LightUBOData)], std.mem.asBytes(&self.ctx.pending_lights));
    }
};

// ---- Mesh bridge struct ----
// Wraps MeshBuffers. Created/destroyed via Renderer.createMesh and Renderer.destroyMesh.
// Passed as const &Mesh to Renderer.draw.

pub const Mesh = struct {
    mesh_buffers: MeshBuffers,
};
