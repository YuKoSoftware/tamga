# Feature Landscape

**Domain:** Multimedia / gaming framework (windowing, Vulkan rendering, GUI, audio)
**Researched:** 2026-03-25
**Confidence:** MEDIUM — derived from training knowledge of SDL3, SFML, Raylib, LÖVE, Sokol, Bevy, wgpu, Dear ImGui, Clay, Nuklear, miniaudio, SoLoud. No live web searches available; flagged where claims need validation against current docs.

---

## Methodology

This analysis surveys what the following frameworks/libraries provide out of the box, then distills what Tamga's target users (Orhon developers building games, tools, and apps) will expect from each component:

- **Platform / windowing:** SDL3, SFML, Raylib, Sokol (sokol_app)
- **Vulkan rendering:** wgpu, Bevy (wgpu backend), raw Vulkan tutorials (Vulkan-tutorial.com, vkguide.dev)
- **2D rendering:** SDL_gpu (SDL3), Raylib (immediate 2D), SFML (sprite/shape API), Sokol (sokol_gfx)
- **GUI:** Dear ImGui (immediate), Clay, Nuklear, Iced, egui (retained-ish)
- **Audio:** SDL3_mixer, miniaudio, SoLoud, FMOD (reference ceiling)

---

## Table Stakes

Features users expect. Missing = product feels incomplete or unusable.

### Windowing / Input

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Create window with title, size, flags | Every framework does this | Low | SDL3: `SDL_CreateWindow`; flags include RESIZABLE, FULLSCREEN, BORDERLESS, VULKAN |
| Window resize handling | Resize events must invalidate swapchain | Low | Already exists in SDL3 bridge; VK swapchain recreation is the hard part |
| Window close / quit event | Users expect clean shutdown | Low | EVENT_QUIT already bridged |
| Keyboard input (key down/up, scancode) | Any interactive app needs this | Low | Already bridged; needs full scancode table eventually |
| Mouse input (position, delta, buttons) | Every game/tool needs mouse | Low | Already bridged |
| Gamepad / controller support | Table stakes for games specifically | Medium | SDL3 has SDL_Gamepad API; not yet bridged |
| Event polling loop | The heartbeat of every SDL app | Low | Bridge has `Event.poll()`; needs doc/example |
| Timing / delta time | Frame-rate-independent update | Low | `getTicks()` bridged; need delta-time helper |
| Cursor hide/show/lock (relative mouse mode) | FPS and 3D viewports need this | Low | SDL3: `SDL_SetWindowRelativeMouseMode` |
| Multiple monitor / display info | HiDPI, fullscreen on correct monitor | Low-Med | SDL3 provides this; important for HiDPI support |
| HiDPI / pixel density awareness | Blurry windows on retina/4K screens | Low | SDL3 `HIGH_PIXEL_DENSITY` flag already in bridge |
| Error propagation on init failure | Frameworks that silently fail are unusable | Low | Bridge already returns `Error | Window` |

### Vulkan 2D Renderer

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Draw colored rectangles / quads | Primitive building block | Medium | Requires vertex buffer, pipeline, push constants |
| Draw textured sprites/quads | Core 2D output primitive | Medium | Needs texture loading, sampler, descriptor set |
| PNG/JPG texture loading | Virtually every 2D renderer needs it | Low-Med | STB image (via Zig bridge) is the standard approach |
| Sprite batching | Without it, single draw call per sprite = unusable at scale | High | The key performance requirement for 2D Vulkan |
| Orthographic camera / projection | 2D coordinate system that makes sense | Low | Just a 4x4 matrix in a push constant or UBO |
| Z-ordering / draw layers | Sprites need depth ordering | Low-Med | Can be render-order or a depth buffer |
| Basic shape drawing (lines, circles) | Debug overlays, HUD elements | Medium | Can be CPU-tessellated quads |
| Text rendering | Without text, no HUD, no UI | High | Biggest complexity spike: font atlas, SDF or bitmap |
| Scissor / clipping | GUI and UI panels need it | Low | Just a Vulkan scissor rect |
| Color tinting / alpha blending | Translucency, hit flash, fade | Low | Blend state in Vulkan pipeline |
| Swapchain resize handling | Window resize must not crash | High | VK swapchain recreation on resize is notorious |
| Frame synchronization | Double/triple buffer without tearing | Medium | Fences + semaphores; already implied by beginFrame/endFrame |

### Vulkan 3D Renderer

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Clear to solid color | Already exists | Low | Done |
| Vertex/index buffer submission | Render any geometry | Medium | The next step after clear |
| Perspective camera (VP matrix) | Without this, no real 3D | Low | UBO or push constants |
| Depth buffering | Without it, geometry overdraw is wrong | Medium | Depth attachment + depth test pipeline state |
| OBJ model loading | Most basic 3D asset format | Medium | tinyobjloader via Zig bridge is standard |
| Texture mapping | Untextured 3D is just a prototype | Medium | Same pipeline as 2D |
| Directional + point lighting | Phong or PBR; without it scenes look flat | High | PBR is differentiator; Phong is table stakes |
| Swapchain resize handling | Same as 2D — crashes = unusable | High | |
| MSAA anti-aliasing | Jagged edges are conspicuous without it | Medium | Vulkan multisampling |
| Debug geometry (lines, AABBs) | Every 3D app needs debug drawing | Medium | Thin line pipeline |
| Push constants / UBO management | Shader data must be manageable | Medium | Abstraction saves per-draw boilerplate |
| Shadow mapping (basic) | Point lights without shadows feel wrong in modern 3D | High | Can be deferred to differentiator phase |

### GUI (Immediate + Retained)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Button, label, text input | Core widget set | Medium | Any toolkit missing these is not a GUI toolkit |
| Checkbox, radio, slider | Form controls users expect | Medium | |
| Panels / windows (floating) | Organize UI regions | Medium | |
| Layout (horizontal, vertical, grid) | Without layout, everything is positioned manually | High | The hardest part of GUI |
| Scrollable containers | Lists longer than one screen | Medium | |
| Immediate mode path (like Dear ImGui) | Developer tools, debug overlays, in-game editors | High | Dear ImGui is the baseline expectation |
| Retained mode path (widget tree) | Game UI, menus, HUDs | High | |
| Font rendering / text layout | No GUI without text | High | Shared with renderer |
| Mouse and keyboard event consumption | GUI must capture events before game layer | Medium | Input priority / hit testing |
| Theming / style (colors, padding, fonts) | Without theming, GUI is hardcoded to one look | Medium | |
| Clipping / scissor per widget | Scrollable content must not bleed | Low-Med | |

### Audio

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Load and play WAV (one-shot SFX) | Game SFX are almost always WAV | Low-Med | SDL3_mixer or miniaudio; one-shot fire-and-forget |
| Load and stream OGG (music) | Music files too large to load entirely | Medium | Streaming decode: ogg/vorbis via Zig bridge |
| Volume control (master + per-channel) | Users expect volume knobs | Low | |
| Play / pause / stop | Minimum transport controls | Low | |
| Loop music track | Background music must loop | Low | |
| Multiple simultaneous sounds | Explosion + footstep + music at once | Medium | Mixing; SDL3_mixer or miniaudio handle this |
| Prevent audio stutter / gaps | Audible gaps are immediately noticeable | Medium | Buffer sizing, callback threading |

---

## Differentiators

Features that set Tamga apart. Not universally expected, but highly valued.

### Windowing / Input

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Full scancode + keyname table (all keys) | Rebindable controls need the full table | Low | Just constant declarations |
| Text input events (Unicode) | Proper text fields in-game or in GUI | Low-Med | SDL3 `SDL_EVENT_TEXT_INPUT` |
| Touch input support | Mobile/tablet targets | Medium | SDL3 has this; deferred unless cross-platform touch is needed |
| Multiple windows | Editor tools, second monitor debug views | Medium | SDL3 supports it |
| Drag-and-drop file events | Asset drag into editor | Low | SDL3 `SDL_EVENT_DROP_FILE` |

### Vulkan 2D Renderer

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Signed Distance Field (SDF) text | Crisp text at any scale; Raylib-quality UX | Very High | Major implementation effort; huge quality gain |
| Texture atlas packing | Reduce draw calls; better batching | High | Runtime atlas builder |
| Nine-slice sprites | UI backgrounds that scale without distortion | Medium | Common GUI requirement |
| Render-to-texture | Post-processing, off-screen UI, minimap | High | Vulkan render pass to image |
| Post-processing pipeline (bloom, vignette) | Modern look without 3D engine | Very High | Deferred to later milestone |
| Particle system (2D) | Visual polish for effects | High | |

### Vulkan 3D Renderer

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| PBR (physically-based rendering) | Modern, correct lighting | Very High | The industry standard since ~2015 |
| glTF 2.0 model loading | Industry-standard 3D format; OBJ is legacy | High | Better to do glTF than OBJ long-term |
| Skeletal animation | Animated characters | Very High | Deferred milestone |
| Instanced rendering | Draw 1000 trees with one call | Medium | High value for performance |
| Frustum culling | Don't draw what's off-screen | Medium | Important at scene scale |
| HDR + tonemapping | Modern rendering expectation | High | |
| Bindless textures (Vulkan descriptor indexing) | Eliminates per-material descriptor churn | High | Requires VK extension; major perf gain |
| Render graph / frame graph | Structured GPU pass scheduling | Very High | What Bevy and wgpu use internally |

### GUI

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Unified API (one lib, two modes) | No context switch between tool UI and game UI | Very High | The KEY Tamga GUI differentiator per PROJECT.md |
| Animation / transitions | Polished UI feel | High | |
| SVG / vector icon support | Sharp icons at all DPI | Very High | Deferred |
| Accessibility (focus, tab order) | Required for tool software | High | Deferred |
| Custom widget extension API | Power users want to build their own widgets | High | |

### Audio

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Audio bus/channel grouping (SFX / Music / UI buses) | Industry expectation from Godot/Unity users | Medium | Architecture decision, not much more code |
| Pitch shifting | Speed-up / slow-down for effects | Medium | miniaudio supports this |
| Fade in / fade out | Music transitions without a click | Low-Med | |
| Extensible DSP chain | Future effects pipeline (reverb, EQ) | High | Design now, implement later |
| Audio asset hot-reload | Dev workflow speed | Medium | |

---

## Anti-Features

Features to explicitly NOT build in this milestone.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| OpenGL renderer | Double the maintenance; Vulkan is the focus | Defer to future milestone per PROJECT.md |
| Built-in game loop / scene tree | Game engine territory; not framework territory | Leave to the Tamga engine project that consumes this framework |
| ECS (Entity Component System) | Out of scope for this milestone | TamgaECS is a separate future module |
| Physics engine | Out of scope | TamgaPhysics is a separate future module |
| Networking | No user demand at framework level | Future milestone |
| Scripting / hot-reload scripts | Orhon is compiled; scripting is out of place here | ECS script attachment is engine territory |
| Asset management / virtual filesystem | Complex system with its own trade-offs | TamgaPack is a separate future module |
| Video playback | Extreme complexity, niche use | Not in scope |
| Font rendering in the renderer layer | Font belongs in GUI, not in the Vulkan renderers | Renderers provide raw text glyph quads; GUI owns font layout |
| Tightly coupled 2D+3D renderer | Separate optimizations are lost | Keep TamgaVK2D and TamgaVK3D independent |
| SDL3 leaking above the SDL3 module | API stability requires abstraction | SDL3 types/constants must not appear in TamgaVK2D, TamgaGUI, etc. |
| FMOD-style middleware dependency | Proprietary lock-in | Build on open formats (WAV, OGG) via miniaudio/stb_vorbis |

---

## Feature Dependencies

```
TamgaSDL3 (window + input)
    └── TamgaVK3D (consumes window handle)
    └── TamgaVK2D (consumes window handle)
    └── TamgaGUI  (consumes input events + render surface)
    └── TamgaAudio (init via SDL3 audio subsystem OR standalone)

TamgaVK2D
    └── TamgaGUI (GUI renders via 2D renderer)

Text rendering (font atlas)
    └── TamgaVK2D depends on it (debug text, sprite labels)
    └── TamgaGUI depends on it (labels, text inputs, everything)

Sprite batching
    └── TamgaVK2D — required before any real 2D use

Swapchain resize
    └── TamgaVK2D and TamgaVK3D both — must be solved early; window resize
        will crash if unhandled

Audio mixing (multi-channel)
    └── Required before WAV SFX is useful (can't play only one sound at a time)
```

---

## MVP Recommendation

For a first usable milestone, prioritize in this order:

**Windowing / Input (TamgaSDL3)**
1. Full scancode table (all standard keys) — filling the existing bridge
2. Relative mouse mode (cursor lock for 3D viewport)
3. Text input events (needed by GUI)
4. Gamepad support (SDL_Gamepad API)

**Vulkan 3D Renderer (TamgaVK3D)**
1. Vertex/index buffer submission — geometry rendering
2. UBO / push constant management — camera and model matrices
3. Depth buffer — correct rendering
4. Swapchain resize — stability
5. OBJ or glTF loading — basic scene
6. Phong lighting — minimum viable shading

**Vulkan 2D Renderer (TamgaVK2D)**
1. Colored quad rendering
2. Textured quad + PNG loading (stb_image)
3. Sprite batching — performance gate
4. Orthographic camera
5. Swapchain resize

**GUI (TamgaGUI)**
1. Immediate mode path first (simpler to bootstrap; useful for debug tools immediately)
2. Core widgets: button, label, text input, checkbox, slider
3. Layout: vertical + horizontal stacking
4. Retained mode path second (build on top of immediate foundations or as parallel tree)

**Audio (TamgaAudio)**
1. WAV load + play (one-shot)
2. OGG stream + loop
3. Volume control + mixing (multi-channel simultaneous)
4. Audio bus architecture (even if only 2 buses: SFX + Music)

**Defer:**
- PBR lighting — use Phong first
- SDF text — use bitmap atlas first
- Post-processing — not needed for MVP
- Skeletal animation, render-to-texture, instancing — all future
- Retained GUI mode — can follow immediate mode

---

## Notes on Framework Comparisons

**SDL3 (platform layer):** The reference for what windowing/input "table stakes" means. SDL3's new GPU API (SDL_gpu, added in SDL 3.x) adds a high-level draw API on top of Vulkan/Metal/DX12 — Tamga does not use SDL_gpu (uses raw Vulkan directly), so only the platform/input layer of SDL3 is relevant here. [MEDIUM confidence — SDL3 GPU API status as of training data; verify current SDL3 release state]

**Raylib:** Sets the UX expectation bar for simplicity. Functions like `DrawTexture`, `DrawRectangle`, `PlaySound` are one-liners. Tamga's API should feel similarly approachable even though it targets a systems audience. Raylib's text API (`DrawText`, `MeasureText`) is what Tamga users will compare against.

**Dear ImGui:** Defines immediate mode GUI expectations. Every "developer tools" use case assumes ImGui-like behavior: retained state in the library, stateless call sites, docking, overlay windows. Tamga's immediate mode path will be compared to this.

**SFML:** Sets the expectation for retained-mode 2D framework ergonomics. `Sprite`, `Texture`, `Sound` as owning value types with clean constructors. Tamga retained API should feel like this tier of DX.

**wgpu / Bevy (render graph):** Sets the expectation that GPU resource management is structured, not ad-hoc. Bevy's render graph and wgpu's `RenderPass` model show what "well-designed Vulkan abstraction" looks like for Rust users. Tamga's Vulkan abstractions will be compared to this quality level by technically sophisticated users.

**miniaudio:** The reference for audio simplicity. Single-header, works everywhere, WAV/OGG out of the box, no external dependencies. Tamga's audio module should be at least this capable and should consider wrapping miniaudio via Zig bridge rather than building from scratch.

**SoLoud:** Sets the ceiling for what a "complete" audio library looks like: buses, filters, 3D spatial audio, fade/pitch, voice groups. Tamga's architecture should not preclude reaching this level later.

---

## Sources

- Training knowledge: SDL3 documentation and API surface (as of ~mid-2025)
- Training knowledge: Dear ImGui, Raylib, SFML, LÖVE feature sets
- Training knowledge: wgpu, Bevy render architecture
- Training knowledge: miniaudio, SoLoud audio library APIs
- Training knowledge: Vulkan-tutorial.com and vkguide.dev patterns
- Project context: `/home/yunus/Projects/orhon/tamga_framework/.planning/PROJECT.md`
- Existing code: `src/TamgaSDL3/tamga_sdl3.orh`, `src/TamgaVK3D/tamga_vk3d.orh`

**Confidence notes:**
- Windowing feature list: HIGH (SDL3 API is stable and well-documented in training data)
- Vulkan renderer features: MEDIUM (Vulkan patterns are stable; specific SDL3 GPU API status needs verification)
- GUI feature categorization: HIGH (Dear ImGui and Clay are well-understood)
- Audio feature list: HIGH (miniaudio/SoLoud APIs are stable and well-documented in training data)
- "Unified GUI mode" feasibility: LOW (novel design decision; no existing framework does exactly this)
