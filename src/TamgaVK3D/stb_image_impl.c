// C translation unit for tamga_vk3d native dependencies.
// Compiled via #cimport source: in tamga_vk3d.orh.

// stb_image: PNG/JPG texture loading
#define STB_IMAGE_IMPLEMENTATION
#include "libs/stb_image.h"

// Embedded SPIR-V shader bytecode (generated from src/shaders/*.spv)
#include "shaders_spv.c"
