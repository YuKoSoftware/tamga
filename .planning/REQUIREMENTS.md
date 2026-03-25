# Requirements: Tamga Framework

**Defined:** 2026-03-25
**Core Value:** Complete, high-performance, easy-to-use modular libraries for windowing, rendering, audio, and GUI in Orhon

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Windowing (TamgaSDL3)

- [x] **WIN-01**: User can create a window with title, size, and flags (resizable, fullscreen, borderless, Vulkan)
- [x] **WIN-02**: Window resize events are handled and propagated to dependent systems
- [x] **WIN-03**: Window close / quit events trigger clean shutdown
- [x] **WIN-04**: Keyboard input: key down/up events with scancodes
- [x] **WIN-05**: Mouse input: position, delta, button press/release
- [x] **WIN-06**: Gamepad/controller input via SDL3 Gamepad API
- [x] **WIN-07**: Event polling loop with timing and delta time helpers
- [x] **WIN-08**: Cursor hide/show/lock (relative mouse mode) for 3D viewports
- [x] **WIN-09**: HiDPI / pixel density awareness (high pixel density flag)
- [x] **WIN-10**: Error propagation on initialization failure (Orhon error unions)
- [x] **WIN-11**: Text input events (Unicode) for GUI text fields
- [x] **WIN-12**: Full SDL3 abstraction — no SDL3 types leak above TamgaSDL3 module
- [x] **WIN-13**: Window handle exposed as opaque type for renderer consumption
- [x] **WIN-14**: Multiple monitor / display info query

### Vulkan 3D Renderer (TamgaVK3D)

- [ ] **VK3-01**: Vertex and index buffer submission for arbitrary geometry
- [ ] **VK3-02**: Perspective camera with view/projection matrix (UBO or push constants)
- [ ] **VK3-03**: Depth buffering with correct depth test
- [ ] **VK3-04**: Texture mapping on 3D geometry
- [ ] **VK3-05**: Directional and point lighting (Phong shading)
- [ ] **VK3-06**: Swapchain resize handling without crash
- [ ] **VK3-07**: MSAA anti-aliasing
- [ ] **VK3-08**: Push constants and UBO management abstraction
- [ ] **VK3-09**: Debug geometry rendering (lines, AABBs)
- [ ] **VK3-10**: VMA integration for GPU memory management
- [ ] **VK3-11**: Pipeline cache with persistent disk serialization
- [ ] **VK3-12**: Render graph with automated barrier management (resource usage declarations, automatic layout transitions)
- [ ] **VK3-13**: Depth prepass for early-Z optimization
- [ ] **VK3-14**: Attachment management API (engine declares render targets, renderer allocates and manages lifetimes)
- [ ] **VK3-15**: Compute pass slots in render graph (enables deferred lighting, SSAO, etc. at engine layer)
- [ ] **VK3-16**: General cross-vendor optimizations only — no vendor-specific code paths

### Vulkan 2D Renderer (TamgaVK2D)

- [ ] **VK2-01**: Draw colored rectangles and quads
- [ ] **VK2-02**: Draw textured sprites/quads with PNG/JPG loading (stb_image)
- [ ] **VK2-03**: Sprite batching for performance (transparent to user)
- [ ] **VK2-04**: Orthographic camera / projection
- [ ] **VK2-05**: Z-ordering / draw layers
- [ ] **VK2-06**: Basic shape drawing (lines, circles)
- [ ] **VK2-07**: Text rendering via font atlas (bitmap)
- [ ] **VK2-08**: Scissor / clipping support
- [ ] **VK2-09**: Color tinting and alpha blending
- [ ] **VK2-10**: Swapchain resize handling without crash
- [ ] **VK2-11**: Frame synchronization (double/triple buffering)

### GUI (TamgaGUI)

- [ ] **GUI-01**: Core widgets: button, label, text input, checkbox, radio, slider
- [ ] **GUI-02**: Panels / floating windows
- [ ] **GUI-03**: Layout system: horizontal, vertical, grid
- [ ] **GUI-04**: Scrollable containers
- [ ] **GUI-05**: Immediate mode rendering path (Dear ImGui style)
- [ ] **GUI-06**: Retained mode rendering path (widget tree)
- [ ] **GUI-07**: Font rendering and text layout (shared with VK2D)
- [ ] **GUI-08**: Mouse and keyboard event consumption (input priority / hit testing)
- [ ] **GUI-09**: Theming / style system (colors, padding, fonts)
- [ ] **GUI-10**: Clipping / scissor per widget
- [ ] **GUI-11**: Usable standalone for desktop apps (no gaming/media dependency required)

### Audio (TamgaAudio)

- [ ] **AUD-01**: Load and play WAV files (one-shot sound effects)
- [ ] **AUD-02**: Load and stream OGG files (music)
- [ ] **AUD-03**: Volume control (master and per-channel)
- [ ] **AUD-04**: Play / pause / stop / loop controls
- [ ] **AUD-05**: Multiple simultaneous sounds (mixing)
- [ ] **AUD-06**: No audio stutter or gaps (proper buffer sizing, callback threading)
- [ ] **AUD-07**: Audio bus architecture designed from day one (even if only SFX + Music buses initially)

### Cross-Cutting

- [x] **XC-01**: All APIs are easy to use — complexity lives inside libraries, not in user code
- [x] **XC-02**: Each component is an independent library module with clean boundaries
- [x] **XC-03**: All native bindings via Zig bridge sidecar files only
- [x] **XC-04**: Cross-platform: Linux, Windows, macOS
- [x] **XC-05**: Orhon compiler bugs logged in docs/bugs.txt, missing features in docs/ideas.txt
- [x] **XC-06**: No workarounds — if compiler blocks framework work, fix compiler first then return

### Frame Loop

- [ ] **LOOP-01**: Basic configurable frame loop with fixed timestep update and variable render
- [ ] **LOOP-02**: Delta time management accessible to user code
- [ ] **LOOP-03**: Clean start/stop lifecycle

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Rendering Performance

- **VKPERF-01**: GPU frustum culling via compute + Multi-Draw Indirect
- **VKPERF-02**: Bindless texture descriptors (VK_EXT_descriptor_indexing)
- **VKPERF-03**: Hi-Z occlusion culling (depth pyramid)
- **VKPERF-04**: Ubershader + background specialization compilation
- **VKPERF-05**: Instanced rendering

### Rendering Features

- **VKF-01**: PBR (physically-based rendering) lighting
- **VKF-02**: glTF 2.0 model loading
- **VKF-03**: Shadow mapping
- **VKF-04**: HDR + tonemapping
- **VKF-05**: Render-to-texture
- **VKF-06**: SDF text rendering
- **VKF-07**: Texture atlas packing (runtime)
- **VKF-08**: Nine-slice sprites

### Windowing

- **WINF-01**: Multiple window support
- **WINF-02**: Drag-and-drop file events
- **WINF-03**: Touch input support

### GUI

- **GUIF-01**: Unified API (single library with mode switching)
- **GUIF-02**: Animation / transitions
- **GUIF-03**: Custom widget extension API
- **GUIF-04**: Accessibility (focus, tab order)

### Audio

- **AUDF-01**: Audio bus grouping (SFX / Music / UI)
- **AUDF-02**: Pitch shifting
- **AUDF-03**: Fade in / fade out
- **AUDF-04**: Extensible DSP chain
- **AUDF-05**: Spatial audio (3D positioned sounds)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| OpenGL renderer | Vulkan-only this milestone; deferred to future |
| Physics engine | Future milestone — core libraries first |
| ECS library | Game engine territory (Tamga engine project) |
| Networking | No user demand at framework level |
| Game loop / scene tree | Game engine territory |
| Scripting / hot-reload | Orhon is compiled; scripting is engine territory |
| Asset management / virtual FS | Separate future module (TamgaPack) |
| Video playback | Extreme complexity, niche use |
| Vendor-specific GPU optimizations | General cross-vendor only |
| Mesh shaders / task shaders | Portability concerns; MDI achieves comparable results |
| Raytraced shadows / GI | Requires hardware RT; future milestone |
| Built-in deferred renderer | Engine territory — framework provides the building blocks |
| SDL_gpu usage | Tamga uses raw Vulkan directly |
| FMOD-style proprietary audio | Build on open formats (WAV, OGG) |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| WIN-01 | Phase 1 | Complete |
| WIN-02 | Phase 1 | Complete |
| WIN-03 | Phase 1 | Complete |
| WIN-04 | Phase 1 | Complete |
| WIN-05 | Phase 1 | Complete |
| WIN-06 | Phase 1 | Complete |
| WIN-07 | Phase 1 | Complete |
| WIN-08 | Phase 1 | Complete |
| WIN-09 | Phase 1 | Complete |
| WIN-10 | Phase 1 | Complete |
| WIN-11 | Phase 1 | Complete |
| WIN-12 | Phase 1 | Complete |
| WIN-13 | Phase 1 | Complete |
| WIN-14 | Phase 1 | Complete |
| XC-01 | Phase 1 | Complete |
| XC-02 | Phase 1 | Complete |
| XC-03 | Phase 1 | Complete |
| XC-04 | Phase 1 | Complete |
| XC-05 | Phase 1 | Complete |
| XC-06 | Phase 1 | Complete |
| LOOP-01 | Phase 1 | Pending |
| LOOP-02 | Phase 1 | Pending |
| LOOP-03 | Phase 1 | Pending |
| VK3-01 | Phase 2 | Pending |
| VK3-02 | Phase 2 | Pending |
| VK3-03 | Phase 2 | Pending |
| VK3-04 | Phase 2 | Pending |
| VK3-05 | Phase 2 | Pending |
| VK3-06 | Phase 2 | Pending |
| VK3-07 | Phase 2 | Pending |
| VK3-08 | Phase 2 | Pending |
| VK3-09 | Phase 2 | Pending |
| VK3-10 | Phase 2 | Pending |
| VK3-11 | Phase 2 | Pending |
| VK3-12 | Phase 2 | Pending |
| VK3-13 | Phase 2 | Pending |
| VK3-14 | Phase 2 | Pending |
| VK3-15 | Phase 2 | Pending |
| VK3-16 | Phase 2 | Pending |
| AUD-01 | Phase 3 | Pending |
| AUD-02 | Phase 3 | Pending |
| AUD-03 | Phase 3 | Pending |
| AUD-04 | Phase 3 | Pending |
| AUD-05 | Phase 3 | Pending |
| AUD-06 | Phase 3 | Pending |
| AUD-07 | Phase 3 | Pending |
| VK2-01 | Phase 4 | Pending |
| VK2-02 | Phase 4 | Pending |
| VK2-03 | Phase 4 | Pending |
| VK2-04 | Phase 4 | Pending |
| VK2-05 | Phase 4 | Pending |
| VK2-06 | Phase 4 | Pending |
| VK2-07 | Phase 4 | Pending |
| VK2-08 | Phase 4 | Pending |
| VK2-09 | Phase 4 | Pending |
| VK2-10 | Phase 4 | Pending |
| VK2-11 | Phase 4 | Pending |
| GUI-01 | Phase 5 | Pending |
| GUI-02 | Phase 5 | Pending |
| GUI-03 | Phase 5 | Pending |
| GUI-04 | Phase 5 | Pending |
| GUI-05 | Phase 5 | Pending |
| GUI-06 | Phase 5 | Pending |
| GUI-07 | Phase 5 | Pending |
| GUI-08 | Phase 5 | Pending |
| GUI-09 | Phase 5 | Pending |
| GUI-10 | Phase 5 | Pending |
| GUI-11 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 55 total
- Mapped to phases: 55
- Unmapped: 0

---
*Requirements defined: 2026-03-25*
*Last updated: 2026-03-25 after roadmap creation — all 52 requirements mapped*
