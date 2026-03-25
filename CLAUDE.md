# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About Orhon

Orhon is a compiled, memory-safe language that transpiles to Zig. It has ownership/borrow checking without lifetime annotations, explicit error handling without exceptions, and compile-time generics. The compiler (`orhon`) is available in PATH.

Requires Zig 0.15.x installed globally.

## Commands

```bash
orhon build             # debug build for native platform
orhon run               # build and run
orhon test              # run all test { } blocks
orhon fmt               # format all .orh files
orhon debug             # show project info: modules, files, source directory
orhon gendoc            # generate Markdown docs from /// comments (pub items)
orhon build -fast       # max speed optimization
orhon build -verbose    # show raw Zig compiler output (for debugging codegen)
orhon build -linux_x64 -win_x64  # cross-compile multi-target
```

Output goes to `bin/`. Cache lives in `.orh-cache/` and `zig-cache/` — both belong in `.gitignore`, never edit `.orh-cache/generated/` manually.

## Project Structure

Every project is rooted at `src/main.orh` with `module main`. Source files live in `src/` at any depth — directory layout is purely organizational; the compiler groups files by their `module` declaration, not their path.

```
src/
    main.orh            # module main — #build, #name, #version here only
    player.orh          # module main — additional file
    math/math.orh       # module math — anchor file (must match module name)
    math/vectors.orh    # module math — additional file
```

**Anchor file rule:** exactly one file per module must be named `<modulename>.orh`. Only the anchor file can contain metadata (`#build`, `#name`, `#version`, `#dep`).

**Build types:** `#build = exe` | `#build = static` | `#build = dynamic`

**Imports:**
```
import math             # project-local module
import std::alpha       # stdlib module
import std::alpha as io # with alias
```

No circular imports ever. Everything is private by default; `pub` exposes symbols outside the module.

## Zig Reference

Zig version: **0.15.2**
- Language reference: https://ziglang.org/documentation/0.15.0/
- Community guide: https://zig.guide/
- Source repo: https://codeberg.org/ziglang/zig

## Zig Bridge (Native Bindings)

All C/system interop goes through Zig. Each bridged module has a `.zig` sidecar alongside its anchor `.orh` file:

```
src/
    sdl.orh     # bridge declarations
    sdl.zig     # Zig implementation (C interop, SDL calls, etc.)
```

```
// sdl.orh
module sdl

bridge func windowCreate(title: String, w: i32, h: i32) Ptr(u8)
bridge struct Renderer {
    bridge func create(win: Ptr(u8)) Renderer
    bridge func draw(self: &Renderer) void
}
```

**Bridge safety:** mutable `&T` cannot cross the bridge in either direction (except `self: &BridgeStruct` on methods). Use `const &T` for read borrows or pass by value.

**External deps** declared in anchor file — the compiler never fetches them, place them manually:
```
#dep "./libs/sdl3"  Version(3, 0, 0)
```

## Dual Purpose

This project serves two equally important goals:

1. **Real framework** — a genuinely usable, production-quality game/multimedia library for Orhon
2. **Language stress test** — Orhon is young and actively developed; this framework is a primary vehicle for discovering compiler bugs, missing features, and language rough edges

When something doesn't compile or behaves unexpectedly, it may be a compiler bug rather than a code mistake. Log it in `docs/bugs.txt`. When a pattern feels awkward or requires a workaround, log it in `docs/ideas.txt` as potential language feedback.

**Never work around compiler bugs by writing bad code** — if a valid language construct is broken, note it and find a clean alternative, or leave a comment marking the workaround as temporary.

## Framework Design Goals

- Written in pure Orhon; native bindings (SDL3, Vulkan) via the Zig bridge only
- Highly modular — each component (renderer, audio, ECS, physics) is an independent library module
- Support both immediate and retained GUI modes
- Cross-platform, lean and fast — no hacks or workarounds

## Planned Components

- Window/input (SDL3 bridge)
- Vulkan and OpenGL rendering
- Standalone 2D renderer (Vulkan, performance-optimized)
- Standalone 3D renderer (Vulkan, performance-optimized)
- WAV player (sound effects) and OGG player (music)
- Physics engine (lightweight)
- ECS library with attachable Orhon scripts (Godot-style)
- Game loop
- 3D model loader

<!-- GSD:project-start source:PROJECT.md -->
## Project

**Tamga Framework**

A comprehensive collection of multimedia, gaming, and GUI libraries for the Orhon programming language. Tamga sits above Orhon's standard library as the heavier, higher-level building blocks — windowing, rendering, audio, and GUI — that don't belong in a std but are essential for real applications. The GUI component is also usable standalone as a lightweight general-purpose GUI toolkit, independent of any gaming or multimedia context. It also serves as a primary stress test for the Orhon compiler.

**Core Value:** Provide a complete, high-performance set of modular libraries that let an Orhon developer open a window, render 2D and 3D graphics, play audio, and build GUI — the foundation everything else is built on.

### Constraints

- **Language**: Pure Orhon; C/system interop only through Zig bridge sidecar files
- **Graphics API**: Vulkan only (no OpenGL this milestone)
- **Platform layer**: SDL3 via Zig bridge, fully abstracted behind Orhon API
- **Build system**: Orhon compiler (`orhon build`), Zig 0.15.x
- **Modularity**: Each component must be an independent library module with clean boundaries
- **Code quality**: No workarounds, no hacky code, no verbosity, no ambiguity — clean, modular, structural code with well-named variables. If something can't be done cleanly, defer it rather than hack it
- **Upstream bugs**: Zig and SDL3 are both young — log suspected upstream bugs separately from our own, verify before assuming our code is wrong
- **Compiler-first workflow**: When Orhon compiler bugs or missing features block framework work, stop and fix the compiler before continuing. No workarounds.
- **GPU optimizations**: General cross-vendor only — no vendor-specific code paths (no NVIDIA-only, no AMD-only)
- **Usability**: API must be easy to use from the caller's perspective — complexity lives inside the library, not in the user's code
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Platform Layer
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| SDL3 | 3.x (system) | Window creation, input, Vulkan surface, timing | Already implemented and working in the codebase (`tamga_sdl3`). SDL3 is a complete rewrite of SDL2 — unified event model, better Vulkan integration (`SDL_Vulkan_CreateSurface`, `SDL_Vulkan_GetInstanceExtensions`), first-class gamepad support. The `#linkC "SDL3"` directive works confirmed by bugs.txt. |
| SDL3_mixer | 3.x (system) | Audio mixing, WAV/OGG playback | Part of the SDL3 family. Handles WAV (sound effects) and OGG (music streaming) in one library. Eliminates the need to write a custom audio mixer, which is deep DSP territory not appropriate for a framework bootstrap. Alternative: raw `SDL_AudioStream` from SDL3 core (no extra dep, but requires manual OGG decoding). |
### Graphics API
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Vulkan | 1.0 minimum (target 1.2+) | GPU rendering backend for both 2D and 3D renderers | Already used in `tamga_vk3d`. The `#linkC "vulkan"` directive is confirmed working. Targeting 1.0 feature set as done in the prototype ensures maximum hardware compatibility. Vulkan 1.2 promoted many critical extensions (buffer device address, descriptor indexing) to core — consider `apiVersion = makeVersion(1, 2, 0)` in the VkApplicationInfo once the renderers need bindless. |
| VMA (Vulkan Memory Allocator) | 3.x | GPU memory allocation | Raw `vkAllocateMemory` per-buffer is the #1 Vulkan performance pitfall. VMA batches suballocations, handles alignment, and supports defragmentation. It is a single-header C library — one `.zig` sidecar file bridges it with no external build complexity. Every production Vulkan renderer uses this or an equivalent. |
| SPIR-V (offline compiled shaders) | — | Shader format | Shaders compiled offline with `glslangValidator` or `glslc` to `.spv` files, loaded at runtime. No runtime shader compilation needed. Ship `.spv` bytecode in the binary or alongside it. |
### Audio Backend
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| SDL3 core audio | 3.x | WAV loading, audio device management, mixing | `SDL_LoadWAV`, `SDL_OpenAudioDeviceStream`, `SDL_AudioStream` are in SDL3 core with no extra dependency. Already available via the existing `tamga_sdl3` bridge. Add `INIT_AUDIO` flag (already declared in the bridge). |
| stb_vorbis | 1.22+ | OGG Vorbis decoding for music streaming | Single-header C library. No build system integration needed — `@cInclude("stb_vorbis.c")` in the audio `.zig` sidecar with `#define STB_VORBIS_IMPLEMENTATION`. Gives streaming decode (feed chunks to `SDL_AudioStream`) without loading entire OGG into memory. Industry standard for game audio OGG decoding. |
### GUI Library Architecture
| Component | Approach | Why |
|-----------|----------|-----|
| Immediate mode GUI | Custom implementation in Orhon using the 2D renderer | Dear ImGui is the industry standard but is C++, not C — the Zig bridge handles C but C++ bindings (cimgui) add significant complexity and maintenance surface. Given that Tamga is also a language stress test, building a simple IMGUI layer in pure Orhon is the right call. |
| Retained mode GUI | Custom widget tree in Orhon | Same rationale. A retained widget tree (node hierarchy, dirty flags, layout engine) is straightforward to implement cleanly in Orhon and serves as a strong language stress test for generics and ownership. |
- Use `cimgui` (C wrapper around Dear ImGui v1.91.x) via Zig bridge as a stopgap for immediate mode
- For retained mode, there is no dominant C GUI library suitable for games — Clay (single-header C, UI layout) is gaining traction in 2025 for simple cases
- **Confidence on cimgui/Clay: LOW** — based on training data, not freshly verified
### Supporting C Libraries (via Zig bridge sidecar)
| Library | Version | Purpose | Notes |
|---------|---------|---------|-------|
| stb_image | 2.29+ | PNG/JPG texture loading | Single-header C. One `@cInclude` in the renderer Zig sidecar. Required for any textured rendering. |
| stb_vorbis | 1.22+ | OGG decoding | As above. |
| VMA | 3.x | Vulkan memory allocation | Header-only C++, but has a C interface (`vk_mem_alloc.h`). One Zig sidecar. |
| cgltf | 1.14+ | glTF 3D model loading (future) | Single-header C. Out of scope this milestone but plan the loader module slot now. |
### Build Toolchain
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Orhon compiler | current | Primary build system | `orhon build` handles all `.orh` + `.zig` sidecar compilation. |
| Zig | 0.15.x | Transpile target, C interop layer | Required by Orhon. The `@cImport`/`@cInclude` pattern is the only way to bridge C. Confirmed working for SDL3 and Vulkan. |
| glslc (Google) | latest | Compile GLSL shaders to SPIR-V | Part of the Vulkan SDK. `glslc shader.vert -o shader.vert.spv`. Prefer over glslangValidator for better error messages. |
| Vulkan SDK | latest | Validation layers, glslc, VMA headers | Install system-wide. The `VK_LAYER_KHRONOS_validation` layer is already used in the prototype. |
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
## Library Placement
## Module-to-Library Mapping
| Orhon Module | C Libraries Used | Bridge Sidecar |
|---|---|---|
| `tamga_sdl3` | SDL3 | `tamga_sdl3.zig` (exists) |
| `tamga_vk3d` | Vulkan, SDL3 (surface), VMA | `tamga_vk3d.zig` (exists, needs VMA) |
| `tamga_vk2d` | Vulkan, SDL3 (surface), VMA, stb_image | `tamga_vk2d.zig` (new) |
| `tamga_audio` | SDL3 audio, stb_vorbis | `tamga_audio.zig` (new) |
| `tamga_gui` | None (pure Orhon over tamga_vk2d) | None |
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
## Sources
- Existing codebase: `/src/TamgaVK3D/tamga_vk3d.zig`, `/src/TamgaSDL3/tamga_sdl3.zig` — HIGH confidence (working code)
- `/docs/bugs.txt` — confirms `#linkC` directive works, SDL3 bridge functional
- CLAUDE.md — confirms Zig 0.15.x, `#dep` non-fetching model, bridge pattern constraints
- SDL3 API surface inferred from existing `tamga_sdl3.zig` (`SDL_Init`, `SDL_AudioStream` family available in SDL3 core) — MEDIUM confidence
- VMA (Vulkan Memory Allocator) — widely documented, gpuopen.com/projects/vulkenmemoryallocator — MEDIUM confidence (version not freshly checked)
- stb libraries — nothings.org/stb — MEDIUM confidence (single-header C pattern confirmed by project structure)
- Vulkan spec 1.0/1.2/1.3 feature sets — training data — MEDIUM confidence
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
