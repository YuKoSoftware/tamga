# Project Research Summary

**Project:** Tamga Framework
**Domain:** Multimedia / gaming framework (windowing, Vulkan rendering, audio, GUI) built in Orhon
**Researched:** 2026-03-25
**Confidence:** MEDIUM

## Executive Summary

Tamga is a modular multimedia framework written in Orhon, serving both as a production-quality library and as a primary stress test for the Orhon language itself. Research confirms that the right approach is a strict layered architecture: a thin SDL3 platform bridge at the foundation, two independent Vulkan renderers (2D and 3D) above it, a standalone audio module, and a GUI library that renders through the 2D renderer rather than owning its own GPU pipeline. This structure mirrors the best lessons from Sokol's one-concern-per-module philosophy and avoids the SFML anti-pattern of coupling the renderer to the window. The existing codebase already has a working SDL3 bridge and a Vulkan 3D prototype — the architecture is proven at the foundation level.

The recommended stack is already largely in place: SDL3 for windowing and input, raw Vulkan with VMA for GPU memory, SPIR-V offline shaders, SDL3 core audio with stb_vorbis for OGG streaming, and stb_image for texture loading. No C GUI library is needed — the GUI should be written in pure Orhon on top of the 2D renderer, which is also the strongest language workout available. The key decision points are: adopting VMA before geometry rendering begins (raw `vkAllocateMemory` will not scale), committing to a Vulkan API version for the 2D renderer (1.0 render pass vs 1.3 dynamic rendering), and choosing the threading model for audio before writing any audio code.

The top risks are tightly bounded and preventable. Swapchain resize handling is the most urgent: the existing VK3D prototype has a resize flag but no rebuild path, and window drag will corrupt or crash on many drivers without it. SDL3 abstraction leakage is a permanent design risk — every renderer and GUI module must receive only an opaque handle, never SDL types. Audio threading is a correctness constraint, not a performance optimization: OGG streaming requires a lock-free command queue between the main thread and the audio callback thread from day one. Given Orhon's youth, all phases must treat compiler bugs as a normal event and file them rather than working around them with bad code.

---

## Key Findings

### Recommended Stack

The foundation is confirmed working: SDL3 via the existing `tamga_sdl3` Zig bridge, Vulkan via the existing `tamga_vk3d` Zig bridge. The remaining stack is low-risk single-header C libraries (`stb_image`, `stb_vorbis`, VMA) that follow the same bridge pattern already proven in the codebase. The only meaningful decision left open is whether the 2D renderer targets Vulkan 1.0 render passes (compatible with the existing 3D renderer pattern, simpler) or Vulkan 1.3 dynamic rendering (eliminates `VkRenderPass`/`VkFramebuffer` boilerplate). Research recommends staying with 1.0 render passes for now and upgrading in a dedicated refactor phase rather than mid-build.

**Core technologies:**
- **SDL3** (3.x): Window, input, event polling, Vulkan surface creation — already bridged and confirmed working via `#linkC "SDL3"`
- **Vulkan** (1.0 minimum, target 1.2+): GPU rendering for both 2D and 3D renderers — working prototype exists
- **VMA** (Vulkan Memory Allocator 3.x): GPU memory suballocation — required before any geometry rendering; single-header C via Zig bridge
- **stb_image** (2.29+): PNG/JPG texture loading — single-header C, one `@cInclude` in the renderer sidecar
- **stb_vorbis** (1.22+): OGG Vorbis decoding for music streaming — single-header C, streaming decode feeds `SDL_AudioStream`
- **SDL3 core audio**: WAV loading and audio device management via the existing SDL3 bridge — `INIT_AUDIO` flag already declared
- **SPIR-V offline shaders**: GLSL compiled with `glslc` to `.spv` files at build time — zero runtime compilation cost
- **Zig 0.15.x + Orhon compiler**: Build toolchain; Zig version must be pinned to avoid bridge API drift

### Expected Features

**Must have (table stakes):**
- Window creation, resize, fullscreen, close events — SDL3 events must not crash the renderer on resize
- Keyboard, mouse, and gamepad input with full scancode table
- Vulkan 3D: vertex/index buffer submission, perspective camera, depth buffer, UBO management, swapchain resize
- Vulkan 2D: colored/textured quad rendering, sprite batching, orthographic camera, PNG loading, swapchain resize
- GUI: button, label, text input, checkbox, slider — immediate mode path first, retained mode second
- Audio: WAV one-shot SFX, OGG streaming music, volume control, multi-channel mixing, loop support

**Should have (competitive differentiators):**
- Signed Distance Field (SDF) text rendering for crisp text at any scale
- Sprite texture atlas packing to reduce draw calls
- Vulkan 3D: glTF 2.0 model loading (preferred over OBJ long-term), instanced rendering, frustum culling
- Audio bus architecture (SFX / Music / UI buses), fade in/out, pitch shifting
- Unified GUI API where retained widgets are built on top of the immediate draw layer
- Nine-slice sprites for scalable UI backgrounds

**Defer (v2+):**
- PBR lighting — Phong shading is sufficient for the first 3D milestone
- Post-processing pipeline (bloom, vignette) — not needed for MVP
- Skeletal animation — very high complexity, separate milestone
- OpenGL renderer — not this milestone
- ECS, physics, scripting, asset manager, networking — separate future modules
- SVG/vector icon support, accessibility

### Architecture Approach

The framework uses a strict 4-layer dependency graph: a Zig/C native layer (SDL3, Vulkan, stb, VMA), a platform bridge layer (`tamga_sdl3`), independent high-level modules (`tamga_vk3d`, `tamga_vk2d`, `tamga_audio`), and a GUI layer (`tamga_gui`) that depends only on `tamga_vk2d`. The key architectural invariant is that no module above the platform layer imports `tamga_sdl3` at the Orhon level — renderers and GUI receive only an opaque `WindowHandle`. Audio is fully standalone with zero framework dependencies. The GUI emits draw commands into `tamga_vk2d`'s draw list and never owns its own Vulkan pipeline.

**Major components:**
1. `tamga_sdl3` — Platform bridge: window lifecycle, raw input events, timing, audio init flag; exposes opaque `WindowHandle` only
2. `tamga_vk3d` — Vulkan 3D renderer: owns full Vulkan context, render graph, depth-tested mesh rendering; receives `Ptr(u8)` handle at construction
3. `tamga_vk2d` — Vulkan 2D renderer: sprite batching, shape drawing, font atlas, orthographic projection; sibling to VK3D, not a superset
4. `tamga_audio` — Standalone audio: WAV one-shot + OGG streaming, callback-based threading, SDL3 or miniaudio backend
5. `tamga_gui` — GUI library: retained and immediate modes unified; emits draw calls to `tamga_vk2d`; receives input structs from the app, not from SDL3 directly

### Critical Pitfalls

1. **Swapchain resize not handled** — Implement the rebuild path in `beginFrame` (check `VK_ERROR_OUT_OF_DATE_KHR` / `VK_SUBOPTIMAL_KHR`) before considering either Vulkan renderer complete. Use `SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED`, not just `RESIZED`, to handle HiDPI correctly. Address this before the first geometry pass, not after.

2. **SDL3 abstraction leakage** — The window module must expose a typed `WindowHandle` opaque struct, not raw `Ptr(u8)`, in its public API. SDL constants and event types must be translated to Tamga-defined enums at the bridge boundary. Any `import tamga_sdl3` in `tamga_gui` or `tamga_vk2d` source files is a hard design violation.

3. **Audio callback threading data race** — The audio thread owns all decode state. The main thread must communicate only via a lock-free command queue. OGG streaming requires double-buffered decode. Design this threading model before writing any audio code — it cannot be retrofitted cleanly.

4. **Orhon compiler bugs masquerading as logic bugs** — When a valid language construct fails, run `orhon build -verbose` to inspect generated Zig. File in `docs/bugs.txt` immediately. Mark workarounds with `// WORKAROUND:` comments. High-risk patterns to test early: generic structs with multiple type parameters, error unions from bridge functions, closures capturing mutable state.

5. **Retained/immediate GUI state collision** — Retained and immediate GUI modes must share only a read-only input snapshot and a draw call buffer. Immediate mode state lives entirely on the call stack within a frame — never heap-allocated between frames. Decide the unification architecture before writing any widget code.

---

## Implications for Roadmap

Based on research, the build dependency graph is deterministic. The architecture requires a strict build order; phases that violate it create rework. Research also confirms that Orhon-specific risk (compiler bugs, bridge patterns) must be managed across all phases, not just early ones.

### Phase 1: Platform Foundation (TamgaSDL3)

**Rationale:** Everything else depends on the window handle. The SDL3 bridge exists but is incomplete — full scancode table, HiDPI pixel coordinates, swapchain-friendly resize events, text input, and gamepad support are all missing. More importantly, the `WindowHandle` opaque type must be designed correctly here before any downstream module is built on top of it. SDL3 abstraction leakage (Pitfall C3) must be designed out at this phase.

**Delivers:** A complete, stable platform layer — window, input, events, timing, HiDPI, gamepad, opaque handle contract — that all other modules depend on without importing SDL3.

**Addresses:** Full scancode table, relative mouse mode (FPS camera), text input events (required by GUI), gamepad bridging, `WindowHandle` typed wrapper, delta-time helper, `SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED` handling.

**Avoids:** Pitfall C3 (SDL abstraction leakage), Pitfall M6 (HiDPI coordinate mismatch), Pitfall M5 (bridge destroy/ownership pattern established here as the model for all modules).

**Research flag:** Standard patterns — SDL3 API is well-documented and the existing bridge confirms the approach. No additional research needed.

---

### Phase 2: Vulkan 3D Renderer (TamgaVK3D)

**Rationale:** The prototype already clears the screen with a working Vulkan context, swapchain, and render pass. The next step is geometry rendering. However, two critical issues must be resolved before adding geometry: swapchain resize handling (currently absent) and VMA integration for GPU memory (raw `vkAllocateMemory` cannot support buffer + texture uploads without hitting driver limits). Depth buffer must also be added to the render pass before the first triangle, not after — changing the render pass after pipelines exist is a major reconstruction.

**Delivers:** A production-ready 3D renderer capable of vertex/index buffer submission, perspective camera with UBO, depth-tested geometry, basic Phong lighting, OBJ/glTF model loading, and correct swapchain resize behavior.

**Uses:** VMA (Zig bridge — new), stb_image for texture loading, SPIR-V shaders compiled with glslc.

**Implements:** Architecture Pattern 4 (RenderGraph extension point), Pattern 1 (opaque handle), Pattern 2 (bridge-thin Orhon-fat).

**Avoids:** Pitfall C1 (swapchain resize), Pitfall C2 (fixed-size GPU arrays with assertions), Pitfall M7 (depth buffer added before first geometry), Pitfall M2 (pipeline cache from the start).

**Research flag:** Needs deeper research during planning for the geometry pipeline architecture (vertex formats, UBO layout, descriptor set design). The Vulkan-tutorial.com / vkguide.dev patterns are well-established but the specific Orhon bridge surface area for geometry needs design work.

---

### Phase 3: Audio (TamgaAudio)

**Rationale:** Audio has zero framework dependencies and can be developed in parallel with the 3D renderer or independently. Scheduling it after Phase 2 in the roadmap simply ensures the SDL3 foundation (Phase 1) is stable. Audio is the most threading-sensitive module — building it while the rendering work is fresh ensures the callback architecture is designed carefully rather than rushed.

**Delivers:** WAV one-shot SFX playback, OGG music streaming with loop and volume control, multi-channel mixing, audio bus architecture (SFX/Music buses), and a threading model that is safe for future DSP chain extension.

**Uses:** SDL3 core audio (`SDL_AudioStream`, `SDL_LoadWAV`), stb_vorbis (new Zig bridge sidecar) for OGG decoding.

**Implements:** Architecture Pattern 5 (audio callback architecture — mixer on audio thread, command queue from main thread).

**Avoids:** Pitfall C5 (audio threading data race), Pitfall M4 (OGG streaming stutter via double-buffered decode), Pitfall m5 (WAV format assumptions — support PCM and IEEE float, reject others explicitly).

**Research flag:** Standard patterns — SDL3 audio and stb_vorbis are well-documented. The double-buffer OGG decode pattern is established. No additional research needed unless miniaudio is chosen as an alternative backend.

---

### Phase 4: Vulkan 2D Renderer (TamgaVK2D)

**Rationale:** The 2D renderer is architecturally simpler than the 3D renderer for geometry but has a unique performance challenge: sprite batching is required before 2D is useful at any real scale. The 2D renderer also has a new decision: Vulkan 1.0 render pass vs 1.3 dynamic rendering. Research recommends 1.0 to match the existing VK3D pattern and defer the 1.3 upgrade. This phase must be complete before GUI development begins.

**Delivers:** Colored and textured quad rendering, sprite batching, PNG texture loading (stb_image), orthographic camera, Z-order layers, basic shape drawing (lines, circles via tessellated quads), scissor/clipping, swapchain resize.

**Uses:** VMA (shared pattern from Phase 2), stb_image (existing bridge), SPIR-V shaders.

**Implements:** Architecture Pattern 2 (bridge-thin), draw list model that TamgaGUI will emit into.

**Avoids:** Pitfall C1 (swapchain resize — same pattern as VK3D), Pitfall M1 (Vulkan version decision made explicitly at phase start), Pitfall M2 (pipeline cache).

**Research flag:** Needs deeper research during planning for sprite batching architecture (instanced rendering vs merged vertex buffer vs texture array approach) and the font atlas design (bitmap vs SDF) since text rendering is required for GUI.

---

### Phase 5: GUI (TamgaGUI)

**Rationale:** GUI is last because it depends on a stable TamgaVK2D draw API and a stable input contract from TamgaSDL3. Building GUI before the draw API is settled means constant refactoring. The immediate mode path should be built first — it is simpler, useful for debug overlays immediately, and forms the foundation that retained widgets are built on top of.

**Delivers:** Immediate mode GUI path (button, label, text input, checkbox, slider, panel, vertical/horizontal layout), font rendering via shared font atlas with TamgaVK2D, input routing with hot/active item model. Retained mode GUI path follows as a second milestone within this phase.

**Implements:** Architecture Pattern 3 (renderer-agnostic GUI input — GUI receives `GuiInput` struct from app, never imports tamga_sdl3), unified retained-on-immediate architecture from ARCHITECTURE.md.

**Avoids:** Pitfall C6 (retained/immediate state collision — immediate mode state lives on the call stack only), Pitfall m6 (immediate input order dependency — hot/active item model designed before any widget code).

**Research flag:** Needs research during planning for font atlas generation (stb_truetype vs pre-rasterized bitmap) and the unified immediate/retained API design. The "unified GUI" approach is novel — no existing framework does exactly this, so the architecture needs to be validated against Orhon's type system before implementation.

---

### Phase Ordering Rationale

- Phase 1 before everything: `WindowHandle` opaque type is the single coupling point between platform and all other modules. Getting it right once avoids ripple fixes.
- Phase 2 before Phase 4: Both renderers use the same Vulkan context pattern. Establishing the VMA integration, swapchain resize path, and descriptor set management in the 3D renderer gives the 2D renderer a validated template.
- Phase 3 (audio) is independent and can be parallelized with Phase 2 if development resources allow.
- Phase 4 before Phase 5: GUI depends on TamgaVK2D's draw list API. The draw call interface must be stable before any widget layout code is written.
- Depth buffer (Phase 2) before geometry: changing the render pass format after pipelines exist is a full reconstruction. Add the depth stub at render pass creation time.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 2 (VK3D geometry):** Vertex format design, UBO/push constant layout, descriptor set architecture for materials and textures. Well-understood in Vulkan docs but the Orhon bridge surface area needs design.
- **Phase 4 (VK2D):** Sprite batching implementation strategy (instancing vs merged VBO), font atlas approach (bitmap raster vs SDF), draw list format that TamgaGUI can emit into.
- **Phase 5 (GUI):** Font atlas generation library choice, unified immediate/retained API design. Novel design — no template exists. Validate Orhon generic struct support before committing to the design.

Phases with standard patterns (skip research-phase):
- **Phase 1 (SDL3):** SDL3 API is stable and well-documented. Existing bridge confirms all patterns. No new patterns needed.
- **Phase 3 (Audio):** SDL3 audio + stb_vorbis pattern is well-documented. Double-buffer OGG decode is standard. Threading model is clear from the callback architecture.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | Core choices confirmed by working codebase (SDL3, Vulkan). VMA/stb_vorbis/stb_image are well-established single-header C libs — pattern confirmed, specific versions from training data only. |
| Features | MEDIUM-HIGH | SDL3 windowing and Vulkan renderer features are HIGH. GUI feature completeness is HIGH. "Unified GUI mode" feasibility is LOW — novel design with no direct precedent. |
| Architecture | MEDIUM | Layered module structure is HIGH confidence (confirmed by existing code and Sokol/Bevy reference patterns). Specific Orhon bridge API shapes are MEDIUM — depend on Orhon language maturity. |
| Pitfalls | MEDIUM-HIGH | Vulkan pitfalls HIGH (confirmed from existing code + Vulkan spec). Orhon compiler pitfalls HIGH (confirmed from bugs.txt). GUI pitfalls MEDIUM (no GUI code exists yet to confirm). |

**Overall confidence:** MEDIUM

### Gaps to Address

- **Vulkan 1.0 vs 1.3 for VK2D:** Research recommends staying on 1.0 render passes for consistency with VK3D, but 1.3 dynamic rendering eliminates significant boilerplate. Validate `vkEnumerateInstanceVersion` against target hardware at Phase 4 start.
- **Audio backend final choice (SDL3 core vs miniaudio):** Research recommends SDL3 core audio + stb_vorbis. miniaudio is a valid alternative (better built-in OGG support, no SDL3 dependency). Commit to one before Phase 3 implementation starts.
- **Font atlas strategy for text rendering:** Bitmap atlas is simpler to build; SDF gives crisp scaling. This decision affects both TamgaVK2D and TamgaGUI. Needs explicit validation before Phase 4 pipeline design begins.
- **Unified GUI API feasibility in Orhon:** The retained-on-immediate architecture is the right approach but depends on Orhon supporting the generic struct and closure patterns needed for widget state. Test these patterns in isolation before committing the GUI architecture.
- **Orhon compiler stability for complex patterns:** Generic structs with multiple type parameters and error unions from bridge functions are flagged as high-risk. Early prototype testing of these patterns in Phase 1 will surface blockers before they affect dependent modules.

---

## Sources

### Primary (HIGH confidence)
- `/home/yunus/Projects/orhon/tamga_framework/src/TamgaSDL3/tamga_sdl3.zig` — SDL3 bridge implementation, confirmed working
- `/home/yunus/Projects/orhon/tamga_framework/src/TamgaVK3D/tamga_vk3d.zig` — Vulkan context, render graph, swapchain prototype
- `/home/yunus/Projects/orhon/tamga_framework/docs/bugs.txt` — Confirmed Orhon compiler bugs and `#linkC` behavior
- `CLAUDE.md` — Bridge safety rules, anchor file constraints, Zig version requirement

### Secondary (MEDIUM confidence)
- SDL3 API surface (training data, ~mid-2025) — windowing, input, audio stream API
- Vulkan specification 1.0/1.2/1.3 feature sets — swapchain, render pass, pipeline patterns
- VMA documentation (gpuopen.com) — GPU memory allocation patterns
- stb libraries (nothings.org/stb) — single-header C integration pattern
- Sokol, Bevy, SFML, Godot architecture patterns — layered module design lessons
- Dear ImGui, Clay, Nuklear — immediate/retained GUI patterns and pitfalls
- Vulkan-tutorial.com, vkguide.dev — geometry rendering patterns

### Tertiary (LOW confidence)
- "Unified immediate + retained GUI" design — novel approach, no existing framework validated; inferred from Dear ImGui internal architecture
- SDL3 GPU API current state — SDL3's `SDL_gpu` subsystem status may have changed since training data cutoff
- cimgui/Clay as GUI fallback — mentioned in STACK.md as emergency option; not freshly verified

---
*Research completed: 2026-03-25*
*Ready for roadmap: yes*
