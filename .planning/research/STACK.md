# Technology Stack

**Project:** Tamga Framework
**Researched:** 2026-03-25
**Confidence:** MEDIUM — core choices verified from existing codebase and well-established ecosystem knowledge; specific version pins on SDL3/Vulkan verified from project source; GUI and audio backend recommendations based on C library ecosystem patterns (training data, LOW-MEDIUM confidence, flagged below)

---

## Recommended Stack

### Platform Layer

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| SDL3 | 3.x (system) | Window creation, input, Vulkan surface, timing | Already implemented and working in the codebase (`tamga_sdl3`). SDL3 is a complete rewrite of SDL2 — unified event model, better Vulkan integration (`SDL_Vulkan_CreateSurface`, `SDL_Vulkan_GetInstanceExtensions`), first-class gamepad support. The `#linkC "SDL3"` directive works confirmed by bugs.txt. |
| SDL3_mixer | 3.x (system) | Audio mixing, WAV/OGG playback | Part of the SDL3 family. Handles WAV (sound effects) and OGG (music streaming) in one library. Eliminates the need to write a custom audio mixer, which is deep DSP territory not appropriate for a framework bootstrap. Alternative: raw `SDL_AudioStream` from SDL3 core (no extra dep, but requires manual OGG decoding). |

**SDL3 audio decision point (HIGH importance):**
SDL3 includes a rebuilt audio subsystem (`SDL_AudioStream`, `SDL_OpenAudioDeviceStream`) in its core. For WAV loading `SDL_LoadWAV` is built in. For OGG streaming, you need either SDL3_mixer (C lib, Zig bridge) or stb_vorbis (single-header C, simpler bridge). SDL3_mixer adds dependency weight but handles channel mixing and volume control out of the box. **Recommendation: use SDL3 core for WAV + stb_vorbis for OGG**, avoiding SDL3_mixer entirely. This keeps the bridge smaller and gives direct control over the audio graph when adding spatial audio later.

---

### Graphics API

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Vulkan | 1.0 minimum (target 1.2+) | GPU rendering backend for both 2D and 3D renderers | Already used in `tamga_vk3d`. The `#linkC "vulkan"` directive is confirmed working. Targeting 1.0 feature set as done in the prototype ensures maximum hardware compatibility. Vulkan 1.2 promoted many critical extensions (buffer device address, descriptor indexing) to core — consider `apiVersion = makeVersion(1, 2, 0)` in the VkApplicationInfo once the renderers need bindless. |
| VMA (Vulkan Memory Allocator) | 3.x | GPU memory allocation | Raw `vkAllocateMemory` per-buffer is the #1 Vulkan performance pitfall. VMA batches suballocations, handles alignment, and supports defragmentation. It is a single-header C library — one `.zig` sidecar file bridges it with no external build complexity. Every production Vulkan renderer uses this or an equivalent. |
| SPIR-V (offline compiled shaders) | — | Shader format | Shaders compiled offline with `glslangValidator` or `glslc` to `.spv` files, loaded at runtime. No runtime shader compilation needed. Ship `.spv` bytecode in the binary or alongside it. |

---

### Audio Backend

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| SDL3 core audio | 3.x | WAV loading, audio device management, mixing | `SDL_LoadWAV`, `SDL_OpenAudioDeviceStream`, `SDL_AudioStream` are in SDL3 core with no extra dependency. Already available via the existing `tamga_sdl3` bridge. Add `INIT_AUDIO` flag (already declared in the bridge). |
| stb_vorbis | 1.22+ | OGG Vorbis decoding for music streaming | Single-header C library. No build system integration needed — `@cInclude("stb_vorbis.c")` in the audio `.zig` sidecar with `#define STB_VORBIS_IMPLEMENTATION`. Gives streaming decode (feed chunks to `SDL_AudioStream`) without loading entire OGG into memory. Industry standard for game audio OGG decoding. |

**Confidence: MEDIUM** — SDL3 audio API verified from existing bridge declarations (`INIT_AUDIO` flag present). stb_vorbis is well-established (used by countless game engines) but specific version from training data only, not freshly verified.

---

### GUI Library Architecture

No C GUI library is recommended. The project requirements call for both retained and immediate mode GUI written in Orhon itself, above the renderer abstraction. The correct architecture is:

| Component | Approach | Why |
|-----------|----------|-----|
| Immediate mode GUI | Custom implementation in Orhon using the 2D renderer | Dear ImGui is the industry standard but is C++, not C — the Zig bridge handles C but C++ bindings (cimgui) add significant complexity and maintenance surface. Given that Tamga is also a language stress test, building a simple IMGUI layer in pure Orhon is the right call. |
| Retained mode GUI | Custom widget tree in Orhon | Same rationale. A retained widget tree (node hierarchy, dirty flags, layout engine) is straightforward to implement cleanly in Orhon and serves as a strong language stress test for generics and ownership. |

**If time pressure demands a C GUI bridge:**
- Use `cimgui` (C wrapper around Dear ImGui v1.91.x) via Zig bridge as a stopgap for immediate mode
- For retained mode, there is no dominant C GUI library suitable for games — Clay (single-header C, UI layout) is gaining traction in 2025 for simple cases
- **Confidence on cimgui/Clay: LOW** — based on training data, not freshly verified

---

### Supporting C Libraries (via Zig bridge sidecar)

| Library | Version | Purpose | Notes |
|---------|---------|---------|-------|
| stb_image | 2.29+ | PNG/JPG texture loading | Single-header C. One `@cInclude` in the renderer Zig sidecar. Required for any textured rendering. |
| stb_vorbis | 1.22+ | OGG decoding | As above. |
| VMA | 3.x | Vulkan memory allocation | Header-only C++, but has a C interface (`vk_mem_alloc.h`). One Zig sidecar. |
| cgltf | 1.14+ | glTF 3D model loading (future) | Single-header C. Out of scope this milestone but plan the loader module slot now. |

**Confidence: MEDIUM** — All are single-header/header-only C libraries. The Zig bridge pattern for single-header C libraries is confirmed working by the existing SDL3 bridge.

---

### Build Toolchain

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Orhon compiler | current | Primary build system | `orhon build` handles all `.orh` + `.zig` sidecar compilation. |
| Zig | 0.15.x | Transpile target, C interop layer | Required by Orhon. The `@cImport`/`@cInclude` pattern is the only way to bridge C. Confirmed working for SDL3 and Vulkan. |
| glslc (Google) | latest | Compile GLSL shaders to SPIR-V | Part of the Vulkan SDK. `glslc shader.vert -o shader.vert.spv`. Prefer over glslangValidator for better error messages. |
| Vulkan SDK | latest | Validation layers, glslc, VMA headers | Install system-wide. The `VK_LAYER_KHRONOS_validation` layer is already used in the prototype. |

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Audio | SDL3 core + stb_vorbis | SDL3_mixer | SDL3_mixer is an extra C dependency with its own bridge. SDL3 core audio is already available via the existing bridge. stb_vorbis gives more direct control. |
| Audio | SDL3 core + stb_vorbis | miniaudio | miniaudio is excellent but is a complete audio engine (larger than needed). It would also require a full new Zig bridge. The SDL3 audio subsystem is already present. |
| GPU memory | VMA | Manual vkAllocateMemory | Per-allocation calls hit the driver limit (~4096 allocations), cause fragmentation, and perform poorly. VMA is the de facto standard. |
| GUI | Custom Orhon implementation | Dear ImGui via cimgui | C++ bindings through Zig add build complexity. Dear ImGui's context model (global state) conflicts with the modular design goal. Custom implementation is a better language stress test. |
| GUI | Custom Orhon implementation | Nuklear (C IMGUI) | Single-header C, simpler bridge than cimgui, but still foreign code in the framework. Pure Orhon is preferred. |
| Shader loading | Offline SPIR-V (.spv files) | Runtime GLSL compilation via shaderc | shaderc is a large C++ library. Offline compilation is simpler, has zero runtime cost, and is what production renderers do. |
| Texture loading | stb_image (C bridge) | Pure Orhon PNG decoder | stb_image handles PNG/JPG/BMP/TGA in one header. Writing a PNG decoder in Orhon is feasible but not worth the effort for a framework. |
| Vulkan version target | 1.2 (once features needed) | 1.3 dynamic rendering | Vulkan 1.3 dynamic rendering eliminates `VkRenderPass`/`VkFramebuffer`. The prototype already has these structures — migrating mid-project is disruptive. Start with 1.0 renderpass pattern, upgrade to 1.3 dynamic rendering in a dedicated refactor phase. |

---

## Library Placement

Since the Orhon compiler never fetches dependencies automatically (`#dep` declares, not fetches), C libraries are placed manually in `libs/`:

```
libs/
    SDL3/           # system install or manual placement
    vulkan/         # system install (from Vulkan SDK)
    stb/
        stb_image.h
        stb_vorbis.c
    VulkanMemoryAllocator/
        vk_mem_alloc.h
```

Single-header libraries (stb_*, VMA) are included directly via `@cInclude` in the `.zig` sidecar with the implementation define in the sidecar file, not in a separate `.c` file.

---

## Module-to-Library Mapping

| Orhon Module | C Libraries Used | Bridge Sidecar |
|---|---|---|
| `tamga_sdl3` | SDL3 | `tamga_sdl3.zig` (exists) |
| `tamga_vk3d` | Vulkan, SDL3 (surface), VMA | `tamga_vk3d.zig` (exists, needs VMA) |
| `tamga_vk2d` | Vulkan, SDL3 (surface), VMA, stb_image | `tamga_vk2d.zig` (new) |
| `tamga_audio` | SDL3 audio, stb_vorbis | `tamga_audio.zig` (new) |
| `tamga_gui` | None (pure Orhon over tamga_vk2d) | None |

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| SDL3 platform layer | HIGH | Working code in repository confirms SDL3 bridge, window, events, Vulkan surface |
| Vulkan 1.0 rendering | HIGH | Working prototype in repository; double-buffered swapchain, render pass, sync objects |
| VMA for GPU memory | HIGH | Industry standard, single-header C, confirmed Zig bridge pattern works for this class of library |
| stb_vorbis for OGG | MEDIUM | Single-header C pattern confirmed; stb_vorbis specifically is well-established but version not freshly verified |
| stb_image for textures | MEDIUM | Same rationale as stb_vorbis |
| SDL3 core audio for WAV | MEDIUM | `INIT_AUDIO` flag already declared in bridge; full SDL3 audio stream API not yet exercised in this codebase |
| Custom GUI in Orhon | MEDIUM | Architecturally sound; actual implementation complexity depends on Orhon language maturity (may surface compiler bugs) |
| Vulkan 1.2+ upgrade path | MEDIUM | VK 1.2 is widely supported; specific feature requirements depend on renderer design decisions not yet made |
| SPIR-V offline shaders | HIGH | Standard practice; glslc is part of the Vulkan SDK already required for validation layers |

---

## Sources

- Existing codebase: `/src/TamgaVK3D/tamga_vk3d.zig`, `/src/TamgaSDL3/tamga_sdl3.zig` — HIGH confidence (working code)
- `/docs/bugs.txt` — confirms `#linkC` directive works, SDL3 bridge functional
- CLAUDE.md — confirms Zig 0.15.x, `#dep` non-fetching model, bridge pattern constraints
- SDL3 API surface inferred from existing `tamga_sdl3.zig` (`SDL_Init`, `SDL_AudioStream` family available in SDL3 core) — MEDIUM confidence
- VMA (Vulkan Memory Allocator) — widely documented, gpuopen.com/projects/vulkenmemoryallocator — MEDIUM confidence (version not freshly checked)
- stb libraries — nothings.org/stb — MEDIUM confidence (single-header C pattern confirmed by project structure)
- Vulkan spec 1.0/1.2/1.3 feature sets — training data — MEDIUM confidence
