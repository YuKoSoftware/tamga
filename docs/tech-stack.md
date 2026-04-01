# Tamga — Technology Stack

## Platform Layer

| Technology | Version | Purpose |
|------------|---------|---------|
| SDL3 | 3.x (system) | Window creation, input, Vulkan surface, timing |
| SDL3 core audio | 3.x | WAV loading, audio device management, mixing |

## Graphics

| Technology | Version | Purpose |
|------------|---------|---------|
| Vulkan | 1.0 minimum (target 1.2+) | GPU rendering for both 2D and 3D |
| VMA | 3.x | GPU memory allocation (suballocation, alignment, defrag) |
| SPIR-V | offline | Shaders compiled with glslangValidator to .spv, stored in assets/shaders/ |

## Supporting C Libraries (via Zig bridge)

| Library | Version | Purpose |
|---------|---------|---------|
| stb_image | 2.29+ | PNG/JPG texture loading |
| stb_vorbis | 1.22+ | OGG Vorbis decoding for music streaming |
| VMA | 3.x | Vulkan memory allocation (C interface via vk_mem_alloc.h) |
| cgltf | 1.14+ | glTF 3D model loading (future) |

## Build Toolchain

| Technology | Version | Purpose |
|------------|---------|---------|
| Orhon compiler | current | Primary build system (`orhon build`) |
| Zig | 0.15.x | Transpile target, C interop layer |
| glslangValidator | latest | Compile GLSL shaders to SPIR-V |
| Vulkan SDK | latest | Validation layers, glslangValidator, VMA headers |

## Module-to-Library Mapping

| Orhon Module | C Libraries Used | Bridge Sidecar |
|---|---|---|
| `tamga_sdl3` | SDL3 | `tamga_sdl3.zig` |
| `tamga_vulkan` | Vulkan, VMA | `tamga_vulkan.zig` (allocator + render graph) |
| `tamga_vk3d` | Vulkan, SDL3 (surface), stb_image | `tamga_vk3d.zig` |
| `tamga_vk2d` | Vulkan, SDL3 (surface) | `tamga_vk2d.zig` (future) |
| `tamga_audio` | SDL3 audio, stb_vorbis | `tamga_audio.zig` (new) |
| `tamga_gui` | None (pure Orhon over tamga_vk2d) | None |

## Alternatives Considered

| Category | Chosen | Alternative | Why Not |
|----------|--------|-------------|---------|
| Audio | SDL3 core + stb_vorbis | SDL3_mixer | Extra C dep with own bridge; SDL3 core audio already available |
| Audio | SDL3 core + stb_vorbis | miniaudio | Complete audio engine, larger than needed; would require full new bridge |
| GPU memory | VMA | Manual vkAllocateMemory | Per-allocation calls hit driver limit (~4096), cause fragmentation |
| GUI | Custom Orhon | Dear ImGui via cimgui | C++ bindings add build complexity; global state conflicts with modular design |
| GUI | Custom Orhon | Nuklear (C IMGUI) | Foreign code; pure Orhon preferred for language stress test |
| Shaders | Offline SPIR-V (glslangValidator) | Runtime GLSL via shaderc | shaderc is large C++; offline has zero runtime cost |
| Textures | stb_image | Pure Orhon PNG decoder | stb_image handles PNG/JPG/BMP/TGA in one header |
| Vulkan version | 1.0 (upgrade to 1.2+ later) | 1.3 dynamic rendering | Prototype has VkRenderPass structures; mid-project migration disruptive |
