// VMA implementation translation unit.
// This file is compiled once to produce the VMA implementation.
// All other files that use VMA include only the header (without VMA_IMPLEMENTATION).
//
// VMA_STATIC_VULKAN_FUNCTIONS 0: Do not use statically linked Vulkan functions.
// VMA_DYNAMIC_VULKAN_FUNCTIONS 1: Load Vulkan functions dynamically at runtime via vkGetInstanceProcAddr.
// This matches the dynamic loading pattern used in tamga_vk3d.zig.
#define VMA_IMPLEMENTATION
#define VMA_STATIC_VULKAN_FUNCTIONS 0
#define VMA_DYNAMIC_VULKAN_FUNCTIONS 1
#include "libs/vk_mem_alloc.h"
