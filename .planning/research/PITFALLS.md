# Domain Pitfalls

**Domain:** Multimedia/gaming framework — Vulkan rendering, SDL3 windowing, audio, GUI, built on a young transpiled language (Orhon -> Zig)
**Researched:** 2026-03-25
**Confidence:** MEDIUM — Vulkan and audio pitfalls are HIGH confidence from deep domain knowledge; Orhon-specific pitfalls are HIGH confidence from bugs.txt evidence; GUI pitfalls are MEDIUM from design patterns literature.

---

## Critical Pitfalls

Mistakes that cause rewrites, data corruption, GPU crashes, or unrecoverable design debt.

---

### Pitfall C1: Swapchain Resize Not Handled — Silent Corruption

**What goes wrong:** When the window is resized, `vkAcquireNextImageKHR` or `vkQueuePresentKHR` returns `VK_ERROR_OUT_OF_DATE_KHR` or `VK_SUBOPTIMAL_KHR`. If these return codes are not caught and the swapchain is not rebuilt, the renderer produces garbage frames, validation layers fire, and some drivers crash silently.

**Why it happens:** The current prototype passes `oldSwapchain = null` in `VkSwapchainCreateInfoKHR` and has `framebuffer_resized: bool` in `VulkanContext` but no swapchain rebuild path is implemented yet. The `SDL_EVENT_WINDOW_RESIZED` event is not being consumed and forwarded to the renderer.

**Consequences:** Black screen or GPU crash on window resize. On some drivers (particularly AMD on Linux), `VK_ERROR_OUT_OF_DATE_KHR` is not returned — the app just silently renders to wrong dimensions.

**Prevention:**
- In `beginFrame`, check for `VK_ERROR_OUT_OF_DATE_KHR` / `VK_SUBOPTIMAL_KHR` on both `vkAcquireNextImageKHR` and `vkQueuePresentKHR`.
- When detected OR when `framebuffer_resized` flag is set, call `vkDeviceWaitIdle` then destroy and recreate the swapchain, image views, framebuffers (NOT the render pass — it stays valid).
- Pass the old swapchain handle as `oldSwapchain` in the recreate path so the driver can reuse memory.
- SDL3 window: consume `SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED` (not just `RESIZED`) since HiDPI displays report different pixel vs logical sizes.

**Detection:** Black screen after resize; validation layer `VUID-VkPresentInfoKHR` errors; crash on window drag on multi-monitor setups with different DPI.

**Phase:** VK3D renderer — address before calling the renderer "complete."

---

### Pitfall C2: Fixed-Size Arrays for GPU Object Counts — Silent Truncation

**What goes wrong:** The prototype uses compile-time fixed arrays (`[8]VkImage`, `[8]VkFramebuffer`, `[32]VkQueueFamilyProperties`, `[256]VkExtensionProperties`) capped with `@min`. On hardware with more than 8 swapchain images, or with many device extensions, the arrays silently truncate. The renderer appears to work but produces intermittent corruption.

**Why it happens:** Avoiding allocator complexity in Zig bridge code. The `@min` cap looks safe but is actually a silent data loss path.

**Consequences:** On some integrated GPUs (Intel iGPU on Linux), `minImageCount + 1` can request more than 3 images. Extension enumeration truncation can cause `deviceSupportsSwapchain` to return false on perfectly valid hardware.

**Prevention:**
- The swapchain image array cap of 8 is pragmatically safe for current hardware (typical values: 2-4). Document the cap explicitly as a known limit, not a hidden truncation.
- `VkExtensionProperties` enumeration: the 256 cap is fine. The queue family cap of 32 is fine.
- Add an assertion: `if (actual_count > 8) log warning "swapchain image count capped"` so it is visible.
- For the render pipeline (pipelines, descriptor sets, materials): use a dynamic allocator from the start. Never cap those with a fixed array.

**Detection:** `swapchain_image_count` returns values truncated to 8; missing geometry on specific GPU vendors.

**Phase:** VK3D / VK2D infrastructure — fix before adding geometry passes.

---

### Pitfall C3: SDL3 Abstraction Leaking into Higher Modules

**What goes wrong:** SDL3 types, constants, or semantics bleed through the windowing abstraction into GUI, renderer, or audio code. Once leaked, all downstream modules have an implicit SDL3 dependency, making backend swapping (the stated goal) impossible without rewriting all of them.

**Why it happens:** Convenience — it is faster to pass `SDL_Window*` through as `Ptr(u8)` (as the current `getHandle()` bridge does) and use it directly in the Vulkan bridge, rather than defining a clean handle abstraction. The VK3D bridge already takes `window_handle: Ptr(u8)` — this is correct but must remain the only crossing point.

**Consequences:** Adding a second windowing backend (e.g., GLFW, or a native Win32 backend) requires touching every module that ever received a raw handle. The stated goal of backend swappability becomes impossible.

**Prevention:**
- The windowing module must own a typed handle type (e.g., `WindowHandle` as an opaque struct) and never expose raw `Ptr(u8)` in its public API.
- The Vulkan bridge takes `Ptr(u8)` internally, but the windowing module's `pub` API returns `WindowHandle`, and the Vulkan renderer calls `window.getNativeHandle()` only in the bridge layer.
- Audit rule: no module outside `tamga_sdl3` should import `tamga_sdl3` except `tamga_vk3d` (surface creation only) and the application entry point.
- SDL3 event constants (`SCANCODE_*`, `EVENT_*`) must NOT appear in any public API — the windowing module's event type must use Tamga-defined enums.

**Detection:** Any `import tamga_sdl3` appearing in `tamga_gui`, `tamga_audio`, or `tamga_vk2d` source files.

**Phase:** Windowing abstraction design — get this right before building dependent modules.

---

### Pitfall C4: Orhon Compiler Bug Mistaken for Logic Bug — Wasted Investigation Time

**What goes wrong:** A valid language construct fails to compile or produces wrong Zig output. The developer spends hours debugging "their code" when the root cause is a codegen or parser issue in the Orhon compiler. The bug is then worked around with structurally bad code that becomes permanent.

**Why it happens:** Young language. Already confirmed examples from bugs.txt: duplicate imports when multiple module files import the same dependency (v0.8.2 fix). More will surface with generics, closures, complex error union patterns, and bridge struct interactions.

**Consequences:** Incorrect workarounds become technical debt. Unfiled bugs block other Orhon users.

**Prevention:**
- When a valid pattern fails to compile: check `orhon build -verbose` to see the generated Zig. If the Zig is wrong, it is a codegen bug.
- File in `docs/bugs.txt` immediately. Mark any workaround code with `// WORKAROUND: [bug description] — remove when fixed in vX.Y`.
- Test patterns incrementally in the `src/example/` suite before committing them to a module.
- High-risk Orhon patterns to test early: generic structs with multiple type parameters, error unions returned from bridge functions, closures capturing mutable state, `pub` re-exports across modules.

**Detection:** `-verbose` flag shows generated Zig with structural errors; compiler error message points to generated file rather than source file.

**Phase:** Every phase — establish the `-verbose` debugging habit in Phase 1.

---

### Pitfall C5: Audio Callback Threading — Data Race on Audio State

**What goes wrong:** Audio backends (SDL3 audio, miniaudio, or similar) call the audio callback from a dedicated audio thread. If the audio state (volume, currently playing sounds, decoded OGG position) is written from the main thread without synchronization, the result is intermittent corruption — clicks, crashes, or wrong audio.

**Why it happens:** Audio architecture is often designed as "just call play() and it works" without thinking about threading. OGG streaming in particular requires continuous buffer refills from the audio thread while the main thread may be seeking or stopping.

**Consequences:** Non-deterministic audio corruption, crashes on multi-core systems, crashes only on faster machines where the timing window is tighter.

**Prevention:**
- Design the audio module with explicit thread ownership: the audio thread owns all decode state; the main thread communicates only via a lock-free command queue (ring buffer of commands: play, stop, set_volume, seek).
- Never share mutable OGG decode state across threads without a mutex.
- SDL3 audio: use `SDL_LockAudioStream` / `SDL_UnlockAudioStream` for any state access from the main thread if using SDL's audio callback model.
- WAV playback is simpler — a preloaded buffer with an atomic position counter works fine.

**Detection:** Intermittent audio pops on multi-core machines; crash inside the audio callback with a stack trace showing main-thread data.

**Phase:** Audio module design — build the threading model in from the start, not added afterward.

---

### Pitfall C6: Retained GUI and Immediate GUI Sharing Mutable State — Mode Collision

**What goes wrong:** A "unified" GUI library that supports both retained and immediate modes often ends up with shared mutable widget state that is invalid in one mode. Retained mode caches widget identity; immediate mode does not. If both modes write to the same backing store, retained widgets appear in immediate-mode frames and vice versa.

**Why it happens:** Temptation to share the layout engine, input state, and draw call buffer between both modes to avoid code duplication.

**Consequences:** Retained widgets persist across immediate frames; input events route to wrong widgets; widget IDs conflict.

**Prevention:**
- Use a strict separation: the GUI module has a retained subsystem and an immediate subsystem. They share a draw call buffer and input snapshot (read-only), but nothing mutable.
- Immediate mode state lives entirely on the stack within the frame's call sequence — never heap-allocated between frames.
- If the unified API proves too complex during Phase 1 GUI research, split into two modules (`tamga_gui_retained`, `tamga_gui_im`) early rather than late.

**Detection:** Retained widgets flicker in immediate-mode-only frames; widget click state bleeds across mode boundaries.

**Phase:** GUI architecture — decide retained/immediate architecture before writing any widget code.

---

## Moderate Pitfalls

Mistakes that cause significant rework but not full rewrites.

---

### Pitfall M1: VK_API_VERSION Not Matching Actual Device Support

**What goes wrong:** `VkApplicationInfo.apiVersion` is hardcoded to `VK_API_VERSION_1_0` (as in the current prototype using `makeVersion(1, 0, 0)`). Features needed for an efficient 2D renderer (e.g., dynamic rendering from Vulkan 1.3, which eliminates render pass objects) are unavailable, requiring boilerplate-heavy Vulkan 1.0 patterns throughout.

**Prevention:** Query `vkEnumerateInstanceVersion` at startup. Target Vulkan 1.2 as minimum (timeline semaphores, buffer device address). For the 2D renderer specifically, evaluate dynamic rendering (1.3) vs render pass (1.0) before locking in the pipeline design. The current VK3D prototype is Vulkan 1.0 — this is fine for the prototype but must be revisited before the 2D renderer.

**Phase:** VK2D renderer architecture decision.

---

### Pitfall M2: Vulkan Pipeline State Object Explosion

**What goes wrong:** Every combination of blend mode, depth test, stencil, polygon mode, and dynamic state requires a separate `VkPipeline`. Without a pipeline cache and a registry, a scene with 10 material types creates 10+ PSOs, each taking 50-200ms to compile. Stutter on first frame, long startup.

**Prevention:** Implement a pipeline cache (`VkPipelineCache`) from the beginning, persisted to disk. Use a pipeline registry keyed on state hash. For the 2D renderer, use a single pipeline with a push constant to select blend mode rather than separate pipelines per blend mode.

**Phase:** VK3D and VK2D pipeline implementation.

---

### Pitfall M3: SDL3 Event Polling Blocking Input for Renderer

**What goes wrong:** SDL3 event processing (polling via `SDL_PollEvent`) and rendering are coupled in the same thread without explicit frame timing. On Windows, window move/resize triggers a modal event loop that starves the render loop. Result: rendering freezes during window drag.

**Prevention:** SDL3 provides `SDL_SetEventFilter` and separate `SDL_PumpEvents` — use them to separate event consumption from the render tick. Alternatively, structure the frame loop as: pump events -> process events -> update -> render. Never call `SDL_Delay` inside the render loop (the current bridge exposes `delay()` — document it as "testing only, never in production loops").

**Phase:** Windowing + game loop integration.

---

### Pitfall M4: OGG Streaming Stutter from Blocking Decode

**What goes wrong:** OGG decoding is blocking. If the audio callback runs on the audio thread and the next buffer is not ready (because the decode ran long, or the disk was slow), the result is a buffer underrun — audible pop or silence.

**Prevention:** Double-buffer the OGG decode: decode one buffer in advance while the other is being played. Use a dedicated decode thread (or async decode) with a buffer queue deep enough to absorb a 100ms decode spike. For music files (which are the OGG use case), a 500ms ring buffer with double-decode is the standard approach.

**Phase:** Audio module — OGG streaming implementation.

---

### Pitfall M5: Bridge Struct Ownership Mismatch — Double Free or Leak

**What goes wrong:** Orhon's bridge structs (e.g., `Window`, `Renderer`) are owned by Orhon's borrow checker, but the underlying C resources (SDL window pointer, Vulkan handles) are owned by the Zig implementation. If the bridge struct is copied, moved, or dropped without calling the `destroy` bridge function, the C resource leaks. If `destroy` is called twice (e.g., after a move), it's a double free in C territory.

**Why it happens:** Orhon's ownership model applies to its own allocations. Bridge structs contain opaque data that the borrow checker cannot reason about — it does not know that `destroy()` must be called exactly once.

**Prevention:**
- Bridge structs should never be copyable — design them as move-only types in the Orhon API.
- Pair every `create()` with a `destroy()` in a scoped block; use a RAII-style wrapper at the Orhon layer.
- In the Zig implementation, use sentinel values (`null` handles, initialized flags) so that a double `destroy()` is a no-op rather than undefined behavior.
- Document: "Bridge structs are not automatically cleaned up. Call `destroy()` before scope ends."

**Phase:** Every bridge module — establish the pattern in Phase 1 (SDL3 bridge).

---

### Pitfall M6: Cross-Platform HiDPI Coordinate Mismatch

**What goes wrong:** On macOS Retina displays and Windows with DPI scaling, the logical window size (what SDL3 reports for window width/height) differs from the physical pixel size (what the Vulkan surface needs for the swapchain extent). Using logical coordinates for Vulkan produces a blurry or incorrectly scaled framebuffer.

**Prevention:** Always use `SDL_GetWindowSizeInPixels` (not `SDL_GetWindowSize`) for Vulkan surface dimensions — the current VK3D prototype already does this correctly in `chooseSwapExtent`. Carry this pattern into VK2D. For GUI layout, use logical coordinates; for rendering, use physical pixels; provide a `dpiScale()` function in the windowing module.

**Phase:** Windowing module (document the pattern); VK2D (must follow it).

---

### Pitfall M7: No Depth Buffer in 3D Renderer — Deferred Too Long

**What goes wrong:** The VK3D prototype has no depth attachment in the render pass (`pDepthStencilAttachment = null`). This is correct for the clear-screen prototype but must be added before any geometry rendering. If depth is added as an afterthought, the render pass, framebuffers, and all pipeline PSOs must be recreated from scratch because the render pass changes.

**Prevention:** Even if depth rendering is not the current milestone goal, add the depth attachment stub to the render pass now so the framebuffer/pipeline architecture does not need to be redesigned. The cost is one additional `VkImage` allocation and minor framebuffer setup.

**Phase:** VK3D geometry phase — add depth before the first triangle.

---

## Minor Pitfalls

Design friction and wasted time, but recoverable.

---

### Pitfall m1: Orhon Module Anchor File Rule Violations

**What goes wrong:** A new module is added without an anchor file named exactly `<modulename>.orh`, or two files in the same module both try to contain `#dep`/`#build` metadata. The error message may not clearly indicate the anchor file rule.

**Prevention:** Establish directory naming convention: every module lives in a directory named after the module (`TamgaVK3D/tamga_vk3d.orh`). The anchor is always `<dirname_lowercased>.orh`. Document this in a module creation checklist.

**Phase:** Every new module — check in Phase 1 module scaffolding.

---

### Pitfall m2: #linkC for System Libraries Not Working on All Platforms

**What goes wrong:** `#linkC "SDL3"` relies on the system having SDL3 installed and discoverable via `linkSystemLibrary`. On Windows, SDL3 may not be in the system path and must be linked statically or via a bundled DLL. On macOS, Homebrew paths differ from system paths.

**Prevention:** For development, document required system library setup per platform. For distribution, plan static linking early. The current `#dep "./libs/sdl3"` pattern supports bundled deps — use it for CI and release builds.

**Phase:** Cross-platform build setup.

---

### Pitfall m3: Validation Layers Not Catching All Bugs in Release

**What goes wrong:** Vulkan validation layers are only enabled in `debug_mode`. Developers may not run in debug mode during the early prototype phase, missing important synchronization errors. Alternatively, validation is always on during development and the performance impact is accepted, then disabled for release — but bugs that only appear without validation (rare race conditions) go unnoticed.

**Prevention:** Default `debug_mode = true` during all development. Only disable it explicitly for performance profiling. Keep a CI test that runs with validation on and treats any validation error as a test failure.

**Phase:** VK3D and VK2D — establish the debug default.

---

### Pitfall m4: Zig 0.15 API Churn in Bridge Code

**What goes wrong:** Zig is itself under active development. The `.zig` sidecar files use current Zig 0.15 API. If the Orhon compiler's generated Zig is targeted at a slightly different Zig version, API mismatches (changed function signatures, renamed stdlib functions) cause build failures. The `callconv(.c)` syntax in the debug callback already reflects a 0.15-specific change.

**Prevention:** Pin the Zig version in a `.tool-versions` or `zig-version` file at the repo root. Document the required Zig version prominently (already in CLAUDE.md as "0.15.2"). When upgrading, audit all `.zig` bridge sidecars for API changes.

**Phase:** Project setup — document the version pin before onboarding anyone.

---

### Pitfall m5: WAV Parser Assuming PCM Format

**What goes wrong:** A naive WAV parser assumes all WAV files are uncompressed PCM. Many game-produced WAV files use ADPCM, IEEE float, or other compressed formats. The parser fails silently (plays garbage audio) or crashes on non-PCM files.

**Prevention:** Implement WAV parsing to handle at minimum: PCM (format tag 1) and IEEE float (format tag 3). Reject all others with a clear error rather than silent garbage. Document supported formats in the module API.

**Phase:** Audio module — WAV player implementation.

---

### Pitfall m6: Immediate GUI Input Handling Order Dependency

**What goes wrong:** In immediate-mode GUI, the order of `if widget_clicked()` calls in the frame function determines which widget receives overlapping input. If two overlapping widgets both return "clicked," both respond — double actions. This is a known immediate-mode pitfall that Clay, Dear ImGui, and Nuklear all address differently.

**Prevention:** Maintain a single "hot item" and "active item" concept (à la Dear ImGui). The first widget to claim input in z-order wins. Process input in reverse draw order (last drawn = topmost = first to receive input). Design this into the input routing before any widget implementation.

**Phase:** GUI module — input handling design.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|----------------|------------|
| SDL3 windowing module | SDL3 abstraction leaking (C3), HiDPI coordinates (M6), bridge destroy pattern (M5) | Design window handle type before writing code; use pixel coords for Vulkan |
| VK3D geometry rendering | Swapchain resize not handled (C1), no depth buffer (M7), fixed-size arrays (C2), pipeline explosion (M2) | Add resize path and depth stub before first triangle |
| VK2D renderer | Vulkan API version choice (M1), inherits all VK3D patterns | Decide 1.0 vs 1.3 dynamic rendering before pipeline design |
| Audio module | Audio thread data race (C5), OGG stutter (M4), WAV format assumptions (m5) | Design threading model first; choose lib (miniaudio vs SDL audio) with async decode |
| GUI module | Retained/immediate state collision (C6), immediate input order (m6) | Architectural decision on unified vs split before any widget code |
| Every bridge module | Orhon compiler bugs (C4), bridge destroy leaks (M5), anchor file rule (m1) | Use -verbose, file bugs promptly, RAII-style destroy wrappers |
| Cross-platform builds | #linkC on Windows/macOS (m2), Zig version drift (m4) | Pin Zig version, test on all platforms early |

---

## Sources

Confidence levels:

- Vulkan pitfalls (C1, C2, M1, M2, M3, M7, m3): HIGH — confirmed via Vulkan specification, validation layer error catalog, and inspection of the existing `tamga_vk3d.zig` prototype.
- Orhon compiler pitfalls (C4, m1, m4): HIGH — confirmed from `docs/bugs.txt` and direct language documentation in CLAUDE.md.
- Bridge ownership pitfalls (M5, C3): HIGH — derived from the bridge safety rules documented in CLAUDE.md and current API design in `tamga_sdl3.orh`.
- Audio pitfalls (C5, M4, m5): HIGH — well-established audio programming domain knowledge.
- GUI pitfalls (C6, m6): MEDIUM — design patterns from Dear ImGui, Clay, and Nuklear documentation; no GUI code exists yet to confirm.
- Platform pitfalls (M6, m2): MEDIUM — SDL3/HiDPI behavior confirmed from SDL3 migration guide; Windows linking confirmed from cross-platform build practice.
