const std = @import("std");
// vulkan_c is the shared @cImport wrapper. Access types via the .c field.
const c = @import("vulkan_c").c;

const MAX_FRAMES_IN_FLIGHT: u32 = 2;

// ---- VMA opaque types ----
// VMA is compiled separately in vma_impl.cpp. We declare its C API here
// as extern functions rather than @cInclude-ing the header (which is C++ and
// cannot be included via @cImport).

const VmaAllocator = *anyopaque;
pub const VmaAllocation = *anyopaque;
const VmaPool = *anyopaque;

// VMA allocation create flags
const VMA_ALLOCATION_CREATE_MAPPED_BIT: u32 = 0x00000004;
const VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT: u32 = 0x00000400;

// VMA memory usage (auto policy — VMA 3.x)
const VMA_MEMORY_USAGE_AUTO: u32 = 7;

// VMA allocator create flags
const VMA_ALLOCATOR_CREATE_FLAG_BITS_MAX_ENUM: u32 = 0x7FFFFFFF;

// Buffer usage flags (Vulkan)
const VK_BUFFER_USAGE_TRANSFER_SRC_BIT: u32 = 0x00000001;
const VK_BUFFER_USAGE_TRANSFER_DST_BIT: u32 = 0x00000002;
const VK_BUFFER_USAGE_VERTEX_BUFFER_BIT: u32 = 0x00000080;
const VK_BUFFER_USAGE_INDEX_BUFFER_BIT: u32 = 0x00000100;
const VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT: u32 = 0x00000010;
const VK_BUFFER_USAGE_STORAGE_BUFFER_BIT: u32 = 0x00000020;

// ---- VMA C struct definitions ----
// These must exactly match the C structs in vk_mem_alloc.h.

const VmaVulkanFunctions = extern struct {
    vkGetInstanceProcAddr: c.PFN_vkGetInstanceProcAddr = null,
    vkGetDeviceProcAddr: c.PFN_vkGetDeviceProcAddr = null,
    vkGetPhysicalDeviceProperties: ?*const anyopaque = null,
    vkGetPhysicalDeviceMemoryProperties: ?*const anyopaque = null,
    vkAllocateMemory: ?*const anyopaque = null,
    vkFreeMemory: ?*const anyopaque = null,
    vkMapMemory: ?*const anyopaque = null,
    vkUnmapMemory: ?*const anyopaque = null,
    vkFlushMappedMemoryRanges: ?*const anyopaque = null,
    vkInvalidateMappedMemoryRanges: ?*const anyopaque = null,
    vkBindBufferMemory: ?*const anyopaque = null,
    vkBindImageMemory: ?*const anyopaque = null,
    vkGetBufferMemoryRequirements: ?*const anyopaque = null,
    vkGetImageMemoryRequirements: ?*const anyopaque = null,
    vkCreateBuffer: ?*const anyopaque = null,
    vkDestroyBuffer: ?*const anyopaque = null,
    vkCreateImage: ?*const anyopaque = null,
    vkDestroyImage: ?*const anyopaque = null,
    vkCmdCopyBuffer: ?*const anyopaque = null,
    vkGetBufferMemoryRequirements2KHR: ?*const anyopaque = null,
    vkGetImageMemoryRequirements2KHR: ?*const anyopaque = null,
    vkBindBufferMemory2KHR: ?*const anyopaque = null,
    vkBindImageMemory2KHR: ?*const anyopaque = null,
    vkGetPhysicalDeviceMemoryProperties2KHR: ?*const anyopaque = null,
    vkGetDeviceBufferMemoryRequirements: ?*const anyopaque = null,
    vkGetDeviceImageMemoryRequirements: ?*const anyopaque = null,
    vkGetMemoryWin32HandleKHR: ?*const anyopaque = null,
};

const VmaAllocatorCreateInfo = extern struct {
    flags: u32 = 0,
    physicalDevice: c.VkPhysicalDevice = null,
    device: c.VkDevice = null,
    preferredLargeHeapBlockSize: c.VkDeviceSize = 0,
    pAllocationCallbacks: ?*const c.VkAllocationCallbacks = null,
    pDeviceMemoryCallbacks: ?*const anyopaque = null,
    pHeapSizeLimit: ?*const c.VkDeviceSize = null,
    pVulkanFunctions: ?*const VmaVulkanFunctions = null,
    instance: c.VkInstance = null,
    vulkanApiVersion: u32 = 0,
    pTypeExternalMemoryHandleTypes: ?*const anyopaque = null,
};

const VmaAllocationCreateInfo = extern struct {
    flags: u32 = 0,
    usage: u32 = 0,
    requiredFlags: c.VkMemoryPropertyFlags = 0,
    preferredFlags: c.VkMemoryPropertyFlags = 0,
    memoryTypeBits: u32 = 0,
    pool: ?VmaPool = null,
    pUserData: ?*anyopaque = null,
    priority: f32 = 0.0,
    minAlignment: c.VkDeviceSize = 0,
};

const VmaAllocationInfo = extern struct {
    memoryType: u32 = 0,
    deviceMemory: c.VkDeviceMemory = null,
    offset: c.VkDeviceSize = 0,
    size: c.VkDeviceSize = 0,
    pMappedData: ?*anyopaque = null,
    pUserData: ?*anyopaque = null,
    pName: ?[*:0]const u8 = null,
};

// ---- VMA extern function declarations ----
// Implemented in vma_impl.cpp, linked via the build system.

extern "c" fn vmaCreateAllocator(pCreateInfo: *const VmaAllocatorCreateInfo, pAllocator: **anyopaque) c.VkResult;
extern "c" fn vmaDestroyAllocator(allocator: VmaAllocator) void;
extern "c" fn vmaCreateBuffer(
    allocator: VmaAllocator,
    pBufferCreateInfo: *const c.VkBufferCreateInfo,
    pAllocationCreateInfo: *const VmaAllocationCreateInfo,
    pBuffer: *c.VkBuffer,
    pAllocation: **anyopaque,
    pAllocationInfo: ?*VmaAllocationInfo,
) c.VkResult;
extern "c" fn vmaDestroyBuffer(allocator: VmaAllocator, buffer: c.VkBuffer, allocation: VmaAllocation) void;
extern "c" fn vmaCreateImage(
    allocator: VmaAllocator,
    pImageCreateInfo: *const c.VkImageCreateInfo,
    pAllocationCreateInfo: *const VmaAllocationCreateInfo,
    pImage: *c.VkImage,
    pAllocation: **anyopaque,
    pAllocationInfo: ?*VmaAllocationInfo,
) c.VkResult;
extern "c" fn vmaDestroyImage(allocator: VmaAllocator, image: c.VkImage, allocation: VmaAllocation) void;
extern "c" fn vmaMapMemory(allocator: VmaAllocator, allocation: VmaAllocation, ppData: *?*anyopaque) c.VkResult;
extern "c" fn vmaUnmapMemory(allocator: VmaAllocator, allocation: VmaAllocation) void;
extern "c" fn vmaGetAllocationInfo(allocator: VmaAllocator, allocation: VmaAllocation, pAllocationInfo: *VmaAllocationInfo) void;

// ---- Error types ----

const VmaError = error{VmaFailed};

// ---- Buffer allocation result ----

pub const BufferAlloc = extern struct {
    buffer: c.VkBuffer,
    allocation: VmaAllocation,
};

// ---- Image allocation result ----

pub const ImageAlloc = extern struct {
    image: c.VkImage,
    allocation: VmaAllocation,
};

// ---- Staging region ----
// Describes a region in the ring buffer after a stagingWrite call.

pub const StagingRegion = extern struct {
    buffer: c.VkBuffer,
    offset: u32,
    size: u32,
};

// ---- VmaContext ----
// Holds the VMA allocator handle, the 16MB ring buffer staging area,
// and associated state.

pub const VmaContext = struct {
    allocator: VmaAllocator,

    // 16MB ring buffer staging area, persistently mapped
    staging_buffer: c.VkBuffer,
    staging_allocation: VmaAllocation,
    staging_mapped: [*]u8,
    staging_size: u32 = 16 * 1024 * 1024,
    staging_offset: u32 = 0,

    // Fences guarding ring buffer regions (one per frame in flight)
    staging_fences: [MAX_FRAMES_IN_FLIGHT]c.VkFence = [_]c.VkFence{null} ** MAX_FRAMES_IN_FLIGHT,

    pub fn create(instance: c.VkInstance, physical_device: c.VkPhysicalDevice, device: c.VkDevice) anyerror!VmaContext {
        // VMA requires dynamic function loading — provide vkGetInstanceProcAddr and
        // vkGetDeviceProcAddr so it can resolve everything else at runtime.
        const vk_fns = VmaVulkanFunctions{
            .vkGetInstanceProcAddr = c.vkGetInstanceProcAddr,
            .vkGetDeviceProcAddr = c.vkGetDeviceProcAddr,
        };

        const allocator_info = VmaAllocatorCreateInfo{
            .flags = 0,
            .physicalDevice = physical_device,
            .device = device,
            .instance = instance,
            .vulkanApiVersion = (@as(u32, 1) << 22) | (@as(u32, 0) << 12) | 0, // Vulkan 1.0
            .pVulkanFunctions = &vk_fns,
        };

        var raw_allocator: *anyopaque = undefined;
        const result = vmaCreateAllocator(&allocator_info, &raw_allocator);
        if (result != c.VK_SUCCESS) return VmaError.VmaFailed;

        const allocator: VmaAllocator = raw_allocator;

        // Create the 16MB staging ring buffer:
        //   - HOST_ACCESS_SEQUENTIAL_WRITE: CPU writes sequentially (ring pattern)
        //   - MAPPED_BIT: persistent mapping (no map/unmap per upload)
        //   - TRANSFER_SRC: used as copy source for GPU uploads
        const staging_size_bytes: u64 = 16 * 1024 * 1024;
        const staging_buf_info = c.VkBufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .size = staging_size_bytes,
            .usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        };
        const staging_alloc_info = VmaAllocationCreateInfo{
            .flags = VMA_ALLOCATION_CREATE_MAPPED_BIT | VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
            .usage = VMA_MEMORY_USAGE_AUTO,
        };

        var staging_buffer: c.VkBuffer = null;
        var staging_allocation_raw: *anyopaque = undefined;
        var staging_alloc_result_info: VmaAllocationInfo = .{};

        const staging_result = vmaCreateBuffer(
            allocator,
            &staging_buf_info,
            &staging_alloc_info,
            &staging_buffer,
            &staging_allocation_raw,
            &staging_alloc_result_info,
        );
        if (staging_result != c.VK_SUCCESS) {
            vmaDestroyAllocator(allocator);
            return VmaError.VmaFailed;
        }

        const staging_allocation: VmaAllocation = staging_allocation_raw;

        // The persistently mapped pointer is in pMappedData due to MAPPED_BIT
        const mapped_ptr = staging_alloc_result_info.pMappedData orelse {
            vmaDestroyBuffer(allocator, staging_buffer, staging_allocation);
            vmaDestroyAllocator(allocator);
            return VmaError.VmaFailed;
        };

        return VmaContext{
            .allocator = allocator,
            .staging_buffer = staging_buffer,
            .staging_allocation = staging_allocation,
            .staging_mapped = @ptrCast(mapped_ptr),
            .staging_size = 16 * 1024 * 1024,
            .staging_offset = 0,
        };
    }

    pub fn destroy(self: *VmaContext) void {
        vmaDestroyBuffer(self.allocator, self.staging_buffer, self.staging_allocation);
        vmaDestroyAllocator(self.allocator);
    }

    // createBuffer creates a GPU buffer with VMA suballocation.
    // gpu_only = true: VMA_MEMORY_USAGE_AUTO with GPU_ONLY preference (device-local, no CPU access)
    // gpu_only = false: VMA_MEMORY_USAGE_AUTO with HOST_ACCESS preference (e.g. UBOs, readback)
    pub fn createBuffer(self: *VmaContext, size: u64, usage: u32, gpu_only: bool) anyerror!BufferAlloc {
        const buf_info = c.VkBufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .size = size,
            .usage = usage,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        };

        const alloc_flags: u32 = if (gpu_only) 0 else VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;
        const alloc_info = VmaAllocationCreateInfo{
            .flags = alloc_flags,
            .usage = VMA_MEMORY_USAGE_AUTO,
        };

        var buffer: c.VkBuffer = null;
        var allocation_raw: *anyopaque = undefined;

        const result = vmaCreateBuffer(self.allocator, &buf_info, &alloc_info, &buffer, &allocation_raw, null);
        if (result != c.VK_SUCCESS) return VmaError.VmaFailed;

        return BufferAlloc{
            .buffer = buffer,
            .allocation = allocation_raw,
        };
    }

    pub fn destroyBuffer(self: *VmaContext, buffer: c.VkBuffer, allocation: VmaAllocation) void {
        vmaDestroyBuffer(self.allocator, buffer, allocation);
    }

    // mapBuffer maps a host-accessible buffer into CPU address space.
    // Only valid for buffers created with gpu_only = false.
    // Returns a byte pointer to the mapped memory or null on failure.
    pub fn mapBuffer(self: *VmaContext, allocation: VmaAllocation) ?[*]u8 {
        var mapped_raw: ?*anyopaque = null;
        const result = vmaMapMemory(self.allocator, allocation, &mapped_raw);
        if (result != c.VK_SUCCESS) return null;
        return @ptrCast(mapped_raw.?);
    }

    // unmapBuffer unmaps a previously mapped buffer allocation.
    pub fn unmapBuffer(self: *VmaContext, allocation: VmaAllocation) void {
        vmaUnmapMemory(self.allocator, allocation);
    }

    // stagingWrite copies data into the ring buffer at the current offset.
    // Returns the buffer and byte offset where the data was written — the caller
    // uses this in a vkCmdCopyBuffer to transfer to a device-local buffer.
    //
    // Ring wrap: if the data fits within remaining space, write at current offset.
    // If not, wrap to 0 (caller is responsible for ensuring prior frame GPU work
    // using the wrapped region has completed via fence before calling again).
    //
    // If data is larger than the entire staging buffer (rare — large mesh upload),
    // a one-shot allocation is used and a debug warning is printed.
    pub fn stagingWrite(self: *VmaContext, data: [*]const u8, size: u32) anyerror!StagingRegion {
        // One-shot fallback for data larger than the ring buffer
        if (size > self.staging_size) {
            std.debug.print("[TamgaVMA] Warning: stagingWrite size {} exceeds ring buffer {}. Using one-shot allocation.\n", .{ size, self.staging_size });
            const alloc = try self.createBuffer(
                size,
                VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                false,
            );
            // Map, write, unmap for one-shot
            var mapped_raw: ?*anyopaque = null;
            const map_result = vmaMapMemory(self.allocator, alloc.allocation, &mapped_raw);
            if (map_result != c.VK_SUCCESS) {
                vmaDestroyBuffer(self.allocator, alloc.buffer, alloc.allocation);
                return VmaError.VmaFailed;
            }
            const dest: [*]u8 = @ptrCast(mapped_raw.?);
            @memcpy(dest[0..size], data[0..size]);
            vmaUnmapMemory(self.allocator, alloc.allocation);
            return StagingRegion{
                .buffer = alloc.buffer,
                .offset = 0,
                .size = size,
            };
        }

        // Ring wrap: if remaining space is insufficient, wrap to beginning
        if (self.staging_offset + size > self.staging_size) {
            self.staging_offset = 0;
        }

        const write_offset = self.staging_offset;
        const dest = self.staging_mapped + write_offset;
        @memcpy(dest[0..size], data[0..size]);

        self.staging_offset += size;
        // Align to 256 bytes (Vulkan minStorageBufferOffsetAlignment / minUniformBufferOffsetAlignment)
        const alignment: u32 = 256;
        const remainder = self.staging_offset % alignment;
        if (remainder != 0) {
            self.staging_offset += alignment - remainder;
        }
        if (self.staging_offset > self.staging_size) {
            self.staging_offset = self.staging_size;
        }

        return StagingRegion{
            .buffer = self.staging_buffer,
            .offset = write_offset,
            .size = size,
        };
    }

    // createImage creates a GPU image with VMA suballocation.
    // gpu_only images are device-local (optimal for sampling).
    pub fn createImage(
        self: *VmaContext,
        width: u32,
        height: u32,
        format: c.VkFormat,
        usage: c.VkImageUsageFlags,
        gpu_only: bool,
    ) anyerror!ImageAlloc {
        return self.createImageWithSamples(width, height, format, usage, gpu_only, c.VK_SAMPLE_COUNT_1_BIT);
    }

    // createImageWithSamples creates a GPU image with a specified MSAA sample count.
    // Use this for MSAA color and depth attachments.
    pub fn createImageWithSamples(
        self: *VmaContext,
        width: u32,
        height: u32,
        format: c.VkFormat,
        usage: c.VkImageUsageFlags,
        gpu_only: bool,
        samples: c.VkSampleCountFlagBits,
    ) anyerror!ImageAlloc {
        const image_info = c.VkImageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .imageType = c.VK_IMAGE_TYPE_2D,
            .format = format,
            .extent = .{ .width = width, .height = height, .depth = 1 },
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = samples,
            .tiling = if (gpu_only) c.VK_IMAGE_TILING_OPTIMAL else c.VK_IMAGE_TILING_LINEAR,
            .usage = usage,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        };

        const alloc_info = VmaAllocationCreateInfo{
            .flags = 0,
            .usage = VMA_MEMORY_USAGE_AUTO,
        };

        var image: c.VkImage = null;
        var allocation_raw: *anyopaque = undefined;

        const result = vmaCreateImage(self.allocator, &image_info, &alloc_info, &image, &allocation_raw, null);
        if (result != c.VK_SUCCESS) return VmaError.VmaFailed;

        return ImageAlloc{
            .image = image,
            .allocation = allocation_raw,
        };
    }

    pub fn destroyImage(self: *VmaContext, image: c.VkImage, allocation: VmaAllocation) void {
        vmaDestroyImage(self.allocator, image, allocation);
    }
};

// ---- Bridge-exported functions ----
// These are the functions the Orhon bridge calls. The bridge passes Vulkan handles
// as *anyopaque (Ptr(u8) on the Orhon side) — cast to the appropriate Vulkan types here.

pub export fn vma_create(
    instance: *anyopaque,
    physical_device: *anyopaque,
    device: *anyopaque,
    out_ctx: **VmaContext,
) c.VkResult {
    const vk_instance: c.VkInstance = @ptrCast(instance);
    const vk_phys: c.VkPhysicalDevice = @ptrCast(physical_device);
    const vk_device: c.VkDevice = @ptrCast(device);

    const ctx = std.heap.page_allocator.create(VmaContext) catch return c.VK_ERROR_OUT_OF_HOST_MEMORY;
    ctx.* = VmaContext.create(vk_instance, vk_phys, vk_device) catch {
        std.heap.page_allocator.destroy(ctx);
        return c.VK_ERROR_INITIALIZATION_FAILED;
    };
    out_ctx.* = ctx;
    return c.VK_SUCCESS;
}

pub export fn vma_destroy(ctx: *VmaContext) void {
    ctx.destroy();
    std.heap.page_allocator.destroy(ctx);
}

pub export fn vma_create_buffer(
    ctx: *VmaContext,
    size: u64,
    usage: u32,
    gpu_only: bool,
    out_buffer: *?*anyopaque,
    out_allocation: *?*anyopaque,
) c.VkResult {
    const result = ctx.createBuffer(size, usage, gpu_only) catch return c.VK_ERROR_INITIALIZATION_FAILED;
    out_buffer.* = @ptrCast(result.buffer);
    out_allocation.* = @ptrCast(result.allocation);
    return c.VK_SUCCESS;
}

pub export fn vma_destroy_buffer(ctx: *VmaContext, buffer: *anyopaque, allocation: *anyopaque) void {
    const vk_buffer: c.VkBuffer = @ptrCast(buffer);
    const vma_alloc: VmaAllocation = @ptrCast(allocation);
    ctx.destroyBuffer(vk_buffer, vma_alloc);
}

pub export fn vma_staging_write(
    ctx: *VmaContext,
    data: *const anyopaque,
    size: u32,
    out_buffer: *?*anyopaque,
    out_offset: *u32,
) c.VkResult {
    const data_ptr: [*]const u8 = @ptrCast(data);
    const region = ctx.stagingWrite(data_ptr, size) catch return c.VK_ERROR_INITIALIZATION_FAILED;
    out_buffer.* = @ptrCast(region.buffer);
    out_offset.* = region.offset;
    return c.VK_SUCCESS;
}

// ---- Render Graph ----
//
// Ordered pass execution with automatic barrier insertion.
// The graph manages a sequence of graphics and compute passes. Between passes,
// image and buffer memory barriers are inserted. The graph is built once at
// renderer init and rebuilt on swapchain resize — not per-frame.
//
// Usage:
//   var graph = RenderGraph.init();
//   const pass0 = graph.addGraphicsPass(.{ .render_pass = rp, ... });
//   graph.addImageBarrier(pass0, .{ .image = depth_img, ... });
//   // per frame:
//   graph.setPassUserData(pass0, @ptrCast(ctx));
//   graph.execute(cmd, image_index);

const RG_MAX_PASSES: u32 = 8;
const RG_MAX_CLEAR_VALUES: u32 = 4;
const RG_MAX_IMAGE_BARRIERS: u32 = 4;
const RG_MAX_BUFFER_BARRIERS: u32 = 4;

// Callback invoked during pass execution. Records draw/dispatch commands.
pub const ExecuteFn = *const fn (cmd: c.VkCommandBuffer, user_data: ?*anyopaque) void;

// Configuration for adding a graphics (rasterization) pass.
pub const GraphicsPassConfig = struct {
    render_pass: c.VkRenderPass,
    framebuffers: *const [8]c.VkFramebuffer,
    extent: c.VkExtent2D,
    clear_values: []const c.VkClearValue,
    execute_fn: ExecuteFn,
    user_data: ?*anyopaque = null,
};

// Configuration for adding a compute (dispatch) pass.
pub const ComputePassConfig = struct {
    execute_fn: ExecuteFn,
    user_data: ?*anyopaque = null,
};

// Image memory barrier between passes.
pub const ImageBarrier = struct {
    image: c.VkImage,
    old_layout: c.VkImageLayout,
    new_layout: c.VkImageLayout,
    src_stage: c.VkPipelineStageFlags,
    dst_stage: c.VkPipelineStageFlags,
    src_access: c.VkAccessFlags,
    dst_access: c.VkAccessFlags,
    aspect_mask: c.VkImageAspectFlags = c.VK_IMAGE_ASPECT_COLOR_BIT,
};

// Buffer memory barrier between passes.
pub const BufferBarrier = struct {
    buffer: c.VkBuffer,
    size: c.VkDeviceSize = std.math.maxInt(u64), // VK_WHOLE_SIZE
    offset: c.VkDeviceSize = 0,
    src_stage: c.VkPipelineStageFlags,
    dst_stage: c.VkPipelineStageFlags,
    src_access: c.VkAccessFlags,
    dst_access: c.VkAccessFlags,
};

const PassType = enum { graphics, compute };

const Pass = struct {
    pass_type: PassType = .graphics,
    // Graphics pass fields
    render_pass: c.VkRenderPass = null,
    framebuffers: ?*const [8]c.VkFramebuffer = null,
    extent: c.VkExtent2D = .{ .width = 0, .height = 0 },
    clear_values: [RG_MAX_CLEAR_VALUES]c.VkClearValue = undefined,
    clear_value_count: u32 = 0,
    // Common
    execute_fn: ?ExecuteFn = null,
    user_data: ?*anyopaque = null,
};

const Transition = struct {
    image_barriers: [RG_MAX_IMAGE_BARRIERS]ImageBarrier = undefined,
    image_count: u32 = 0,
    buffer_barriers: [RG_MAX_BUFFER_BARRIERS]BufferBarrier = undefined,
    buffer_count: u32 = 0,
};

pub const RenderGraph = struct {
    passes: [RG_MAX_PASSES]Pass = [_]Pass{.{}} ** RG_MAX_PASSES,
    pass_count: u32 = 0,
    // transitions[i] runs AFTER pass[i] completes
    transitions: [RG_MAX_PASSES]Transition = [_]Transition{.{}} ** RG_MAX_PASSES,

    pub fn init() RenderGraph {
        return .{};
    }

    // Add a graphics (rasterization) pass. Returns the pass index.
    pub fn addGraphicsPass(self: *RenderGraph, config: GraphicsPassConfig) u32 {
        if (self.pass_count >= RG_MAX_PASSES) return self.pass_count -| 1;
        const idx = self.pass_count;
        var pass = &self.passes[idx];
        pass.pass_type = .graphics;
        pass.render_pass = config.render_pass;
        pass.framebuffers = config.framebuffers;
        pass.extent = config.extent;
        pass.execute_fn = config.execute_fn;
        pass.user_data = config.user_data;
        const count: u32 = @intCast(@min(config.clear_values.len, RG_MAX_CLEAR_VALUES));
        var ci: u32 = 0;
        while (ci < count) : (ci += 1) {
            pass.clear_values[ci] = config.clear_values[ci];
        }
        pass.clear_value_count = count;
        self.pass_count += 1;
        return idx;
    }

    // Add a compute (dispatch) pass. Returns the pass index.
    pub fn addComputePass(self: *RenderGraph, config: ComputePassConfig) u32 {
        if (self.pass_count >= RG_MAX_PASSES) return self.pass_count -| 1;
        const idx = self.pass_count;
        var pass = &self.passes[idx];
        pass.pass_type = .compute;
        pass.execute_fn = config.execute_fn;
        pass.user_data = config.user_data;
        self.pass_count += 1;
        return idx;
    }

    // Add an image memory barrier after the specified pass.
    pub fn addImageBarrier(self: *RenderGraph, after_pass: u32, barrier: ImageBarrier) void {
        if (after_pass >= self.pass_count) return;
        var t = &self.transitions[after_pass];
        if (t.image_count >= RG_MAX_IMAGE_BARRIERS) return;
        t.image_barriers[t.image_count] = barrier;
        t.image_count += 1;
    }

    // Add a buffer memory barrier after the specified pass.
    pub fn addBufferBarrier(self: *RenderGraph, after_pass: u32, barrier: BufferBarrier) void {
        if (after_pass >= self.pass_count) return;
        var t = &self.transitions[after_pass];
        if (t.buffer_count >= RG_MAX_BUFFER_BARRIERS) return;
        t.buffer_barriers[t.buffer_count] = barrier;
        t.buffer_count += 1;
    }

    // Update clear values for a graphics pass (e.g. when clear color changes).
    pub fn updatePassClearValues(self: *RenderGraph, pass_index: u32, clear_values: []const c.VkClearValue) void {
        if (pass_index >= self.pass_count) return;
        var pass = &self.passes[pass_index];
        if (pass.pass_type != .graphics) return;
        const count: u32 = @intCast(@min(clear_values.len, RG_MAX_CLEAR_VALUES));
        var ci: u32 = 0;
        while (ci < count) : (ci += 1) {
            pass.clear_values[ci] = clear_values[ci];
        }
        pass.clear_value_count = count;
    }

    // Update extent for a graphics pass (e.g. on swapchain resize).
    pub fn updatePassExtent(self: *RenderGraph, pass_index: u32, extent: c.VkExtent2D) void {
        if (pass_index >= self.pass_count) return;
        self.passes[pass_index].extent = extent;
    }

    // Set user_data for a pass callback. Call before execute() each frame.
    pub fn setPassUserData(self: *RenderGraph, pass_index: u32, user_data: ?*anyopaque) void {
        if (pass_index >= self.pass_count) return;
        self.passes[pass_index].user_data = user_data;
    }

    // Execute all passes in order with barriers between them.
    pub fn execute(self: *RenderGraph, cmd: c.VkCommandBuffer, image_index: u32) void {
        var i: u32 = 0;
        while (i < self.pass_count) : (i += 1) {
            const pass = &self.passes[i];
            switch (pass.pass_type) {
                .graphics => executeGraphicsPass(cmd, pass, image_index),
                .compute => executeComputePass(cmd, pass),
            }
            self.insertTransition(cmd, i);
        }
    }

    // Clear all passes and barriers. Call before rebuilding the graph.
    pub fn reset(self: *RenderGraph) void {
        self.pass_count = 0;
        self.transitions = [_]Transition{.{}} ** RG_MAX_PASSES;
    }

    fn executeGraphicsPass(cmd: c.VkCommandBuffer, pass: *const Pass, image_index: u32) void {
        const fb = pass.framebuffers orelse return;
        const rp_info = c.VkRenderPassBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .pNext = null,
            .renderPass = pass.render_pass,
            .framebuffer = fb[image_index],
            .renderArea = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = pass.extent,
            },
            .clearValueCount = pass.clear_value_count,
            .pClearValues = &pass.clear_values,
        };
        c.vkCmdBeginRenderPass(cmd, &rp_info, c.VK_SUBPASS_CONTENTS_INLINE);
        if (pass.execute_fn) |func| func(cmd, pass.user_data);
        c.vkCmdEndRenderPass(cmd);
    }

    fn executeComputePass(cmd: c.VkCommandBuffer, pass: *const Pass) void {
        if (pass.execute_fn) |func| func(cmd, pass.user_data);
    }

    fn insertTransition(self: *const RenderGraph, cmd: c.VkCommandBuffer, pass_index: u32) void {
        const t = &self.transitions[pass_index];
        if (t.image_count == 0 and t.buffer_count == 0) return;

        var vk_img: [RG_MAX_IMAGE_BARRIERS]c.VkImageMemoryBarrier = undefined;
        var src_stage: c.VkPipelineStageFlags = 0;
        var dst_stage: c.VkPipelineStageFlags = 0;

        var ib: u32 = 0;
        while (ib < t.image_count) : (ib += 1) {
            const b = &t.image_barriers[ib];
            vk_img[ib] = c.VkImageMemoryBarrier{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
                .pNext = null,
                .srcAccessMask = b.src_access,
                .dstAccessMask = b.dst_access,
                .oldLayout = b.old_layout,
                .newLayout = b.new_layout,
                .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                .image = b.image,
                .subresourceRange = .{
                    .aspectMask = b.aspect_mask,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };
            src_stage |= b.src_stage;
            dst_stage |= b.dst_stage;
        }

        var vk_buf: [RG_MAX_BUFFER_BARRIERS]c.VkBufferMemoryBarrier = undefined;
        var bb: u32 = 0;
        while (bb < t.buffer_count) : (bb += 1) {
            const b = &t.buffer_barriers[bb];
            vk_buf[bb] = c.VkBufferMemoryBarrier{
                .sType = c.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
                .pNext = null,
                .srcAccessMask = b.src_access,
                .dstAccessMask = b.dst_access,
                .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                .buffer = b.buffer,
                .offset = b.offset,
                .size = b.size,
            };
            src_stage |= b.src_stage;
            dst_stage |= b.dst_stage;
        }

        const img_ptr: ?[*]const c.VkImageMemoryBarrier = if (t.image_count > 0) &vk_img else null;
        const buf_ptr: ?[*]const c.VkBufferMemoryBarrier = if (t.buffer_count > 0) &vk_buf else null;

        c.vkCmdPipelineBarrier(cmd, src_stage, dst_stage, 0, 0, null, t.buffer_count, buf_ptr, t.image_count, img_ptr);
    }
};
