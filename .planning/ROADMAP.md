# Roadmap: Tamga Framework

## Overview

Tamga is built in strict dependency order: a complete SDL3 platform layer first, then the Vulkan 3D renderer (the most architecturally complex piece, and a validated template for the 2D renderer), then the standalone audio module, then the 2D renderer (which unlocks GUI), and finally the GUI library that sits on top of the 2D renderer's draw API. Each phase delivers one complete, independently verifiable capability. Nothing is built twice. No architectural decisions are deferred past the phase that owns them.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Platform Foundation** - Complete TamgaSDL3 — windowing, input, events, opaque handles, and the cross-cutting standards all modules depend on
- [ ] **Phase 2: Vulkan 3D Renderer** - Complete TamgaVK3D — geometry, lighting, render graph, swapchain resize, and advanced pipeline features
- [ ] **Phase 3: Audio** - Complete TamgaAudio — WAV SFX, OGG streaming, mixing, and a thread-safe callback architecture designed for future extension
- [ ] **Phase 4: Vulkan 2D Renderer** - Complete TamgaVK2D — sprite batching, font atlas, shapes, and the draw list API that TamgaGUI will consume
- [ ] **Phase 5: GUI Library** - Complete TamgaGUI — immediate mode first, retained mode second, standalone-capable, running on top of VK2D

## Phase Details

### Phase 1: Platform Foundation
**Goal**: A developer can open a window, receive all input events, and hand an opaque handle to a renderer — with no SDL3 type leaking above the module boundary
**Depends on**: Nothing (first phase)
**Requirements**: WIN-01, WIN-02, WIN-03, WIN-04, WIN-05, WIN-06, WIN-07, WIN-08, WIN-09, WIN-10, WIN-11, WIN-12, WIN-13, WIN-14, XC-01, XC-02, XC-03, XC-04, XC-05, XC-06, LOOP-01, LOOP-02, LOOP-03
**Success Criteria** (what must be TRUE):
  1. A caller can create a window with title, size, and flags (resizable, fullscreen, borderless) using only Tamga types — no SDL3 import required
  2. Keyboard, mouse, gamepad, and text-input events are all receivable in a polling loop with correct delta time and timestamps
  3. Window resize events deliver new pixel dimensions (HiDPI-correct) and a close event triggers clean shutdown without a crash
  4. The opaque `WindowHandle` type is the only surface exposed to downstream modules — no SDL3 constants, structs, or enums appear above the TamgaSDL3 boundary
  5. Error on initialization failure propagates as an Orhon error union; compiler bugs encountered are logged in docs/bugs.txt before any workaround is attempted
  6. A basic frame loop runs with fixed timestep update and variable render; delta time is accessible to user code; loop starts and stops cleanly
**Plans**: TBD

### Phase 2: Vulkan 3D Renderer
**Goal**: A developer can submit arbitrary 3D geometry with textures and lighting, resize the window without a crash, and get correct depth-tested output — with a render graph that supports compute passes and deferred rendering at the engine layer
**Depends on**: Phase 1
**Requirements**: VK3-01, VK3-02, VK3-03, VK3-04, VK3-05, VK3-06, VK3-07, VK3-08, VK3-09, VK3-10, VK3-11, VK3-12, VK3-13, VK3-14, VK3-15, VK3-16
**Success Criteria** (what must be TRUE):
  1. A mesh with vertex/index buffers renders correctly with a perspective camera and depth testing — no Z-fighting, no invisible faces
  2. A texture-mapped, Phong-lit mesh renders with directional and point lights; dragging the window to resize does not crash or corrupt the output
  3. Debug geometry (lines, AABBs) can be drawn in the same frame as normal geometry without state corruption
  4. The render graph declares resource usage and manages barrier transitions automatically; a compute pass slot exists and is callable from the engine layer
  5. GPU memory is managed via VMA; the pipeline cache serializes to disk and reloads on next run
**Plans**: TBD
**UI hint**: yes

### Phase 3: Audio
**Goal**: A developer can play WAV sound effects and stream OGG music simultaneously with volume control — with a callback threading model that is safe from the start and designed for future DSP/spatial extension
**Depends on**: Phase 1
**Requirements**: AUD-01, AUD-02, AUD-03, AUD-04, AUD-05, AUD-06, AUD-07
**Success Criteria** (what must be TRUE):
  1. A WAV file plays as a one-shot sound effect; multiple WAV sounds can play simultaneously without cutoff or corruption
  2. An OGG file streams continuously as background music with no audible gaps, stutters, or pops — including at loop boundaries
  3. Master volume and per-channel volume are adjustable at runtime; play/pause/stop/loop controls work correctly on both WAV and OGG channels
  4. Audio bus architecture exists with at least SFX and Music buses; the main thread communicates with the audio callback thread only via a lock-free command queue (no shared mutable state)
**Plans**: TBD

### Phase 4: Vulkan 2D Renderer
**Goal**: A developer can render colored and textured quads, text, and basic shapes with sprite batching and Z-ordering — and the draw list API is stable enough for TamgaGUI to emit into
**Depends on**: Phase 2
**Requirements**: VK2-01, VK2-02, VK2-03, VK2-04, VK2-05, VK2-06, VK2-07, VK2-08, VK2-09, VK2-10, VK2-11
**Success Criteria** (what must be TRUE):
  1. Colored and textured quads render correctly with an orthographic camera; PNG textures load via stb_image and display without artifacts
  2. Sprite batching is transparent — submitting many sprites in one frame produces fewer draw calls than sprites submitted, with no visible correctness difference
  3. Text renders from a font atlas with correct glyph spacing and alignment; scissor/clipping correctly clips text and sprites to a rect
  4. Resizing the window does not crash or corrupt output; frame synchronization (double/triple buffering) is correct with no tearing or validation errors
**Plans**: TBD
**UI hint**: yes

### Phase 5: GUI Library
**Goal**: A developer can build a complete UI with buttons, labels, text fields, sliders, panels, and scrollable containers — using either immediate mode or retained mode — with no dependency on any gaming or media module
**Depends on**: Phase 4
**Requirements**: GUI-01, GUI-02, GUI-03, GUI-04, GUI-05, GUI-06, GUI-07, GUI-08, GUI-09, GUI-10, GUI-11
**Success Criteria** (what must be TRUE):
  1. All core widgets (button, label, text input, checkbox, radio, slider) work correctly in immediate mode: buttons respond to clicks, text inputs accept keyboard input, sliders move with mouse drag
  2. Panels/floating windows display correctly with all layout modes (horizontal, vertical, grid) and scrollable containers scroll without layout corruption
  3. Retained mode widgets render from a widget tree; retained and immediate modes can coexist in the same frame without state collision
  4. TamgaGUI can be used standalone in a desktop app without importing TamgaSDL3, TamgaVK3D, TamgaAudio, or any gaming module — it requires only TamgaVK2D and a `GuiInput` struct from the host
  5. The style/theme system (colors, padding, fonts) applies consistently across all widgets; clipping per widget works correctly at all nesting levels
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Platform Foundation | 0/? | Not started | - |
| 2. Vulkan 3D Renderer | 0/? | Not started | - |
| 3. Audio | 0/? | Not started | - |
| 4. Vulkan 2D Renderer | 0/? | Not started | - |
| 5. GUI Library | 0/? | Not started | - |
