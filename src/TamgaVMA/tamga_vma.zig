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
        const image_info = c.VkImageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .imageType = c.VK_IMAGE_TYPE_2D,
            .format = format,
            .extent = .{ .width = width, .height = height, .depth = 1 },
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = c.VK_SAMPLE_COUNT_1_BIT,
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
