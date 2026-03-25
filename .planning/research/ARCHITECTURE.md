# Architecture Patterns

**Domain:** Multimedia / gaming framework (windowing, Vulkan rendering, audio, GUI)
**Researched:** 2026-03-25
**Confidence:** MEDIUM — training data on SDL3, Sokol, Bevy, SFML, Godot; live web sources unavailable during research session. Patterns are well-established and stable; no cutting-edge API specifics required.

---

## Recommended Architecture

### Layered Module Stack

```
┌─────────────────────────────────────────────────────────┐
│  User Application (exe)                                  │
├─────────────────────────────────────────────────────────┤
│  TamgaGUI        │  TamgaVK2D  │  TamgaVK3D             │  <- Layer 3: High-level
├─────────────────────────────────────────────────────────┤
│  TamgaAudio      │  (shared Vulkan types / math)         │  <- Layer 2: Standalone
├─────────────────────────────────────────────────────────┤
│  TamgaSDL3  (window handle, events, timing)              │  <- Layer 1: Platform
├─────────────────────────────────────────────────────────┤
│  Zig bridge sidecars (.zig files, C interop)             │  <- Layer 0: Native
│  SDL3 / Vulkan / miniaudio / stb_vorbis (C libs)         │
└─────────────────────────────────────────────────────────┘
```

### Module Inventory

| Module | Type | Depends On | Owned By |
|--------|------|-----------|----------|
| `tamga_sdl3` | Platform bridge | — (C bridge only) | Zig sidecar |
| `tamga_vk3d` | Vulkan 3D renderer | `tamga_sdl3` (window handle) | Zig sidecar |
| `tamga_vk2d` | Vulkan 2D renderer | `tamga_sdl3` (window handle) | Zig sidecar |
| `tamga_audio` | Audio playback | — (C bridge only) | Zig sidecar |
| `tamga_gui` | GUI library | `tamga_vk2d` or `tamga_vk3d` | Orhon (renderer-agnostic draw calls) |

---

## Component Boundaries

### TamgaSDL3 — Platform Layer

**Responsibility:** Everything that touches the OS window and input.

| Concern | Included | Excluded |
|---------|----------|----------|
| Window lifecycle | create, resize, destroy, fullscreen | rendering surface details |
| Input | keyboard, mouse, gamepad scancodes | game-level input mapping |
| Events | raw SDL event polling | event routing or dispatch |
| Timing | getTicks, delay | frame pacing, vsync logic |
| Surface | `getHandle() Ptr(u8)` — opaque OS/Vulkan handle | Vulkan instance, swapchain |
| Audio init | SDL_INIT_AUDIO flag support | audio playback, mixing |

**Key contract:** `Window.getHandle() Ptr(u8)` is the sole coupling point between the platform layer and the renderers. Renderers receive an opaque OS window handle and own all further graphics setup internally.

**What must NOT leak out of TamgaSDL3:** SDL types, SDL error strings as first-class API, SDL_Renderer (use Vulkan renderers instead).

---

### TamgaVK3D — Vulkan 3D Renderer

**Responsibility:** Vulkan context management, 3D geometry, depth-tested rendering.

| Concern | Included | Excluded |
|---------|----------|----------|
| Vulkan lifecycle | instance, device, swapchain, render pass | window creation |
| Frame management | beginFrame / endFrame, sync primitives | game loop timing |
| 3D geometry | mesh upload, vertex/index buffers, draw calls | 2D sprite batching |
| Depth buffer | depth attachment, depth testing | 2D (no depth needed) |
| Shaders | SPIR-V pipeline, push constants, UBOs | GUI draw calls |
| Render graph | declarative pass system (existing design) | GUI pass integration |

**Coupling rule:** TamgaVK3D takes `Ptr(u8)` (opaque window handle) at creation time. It never calls back into TamgaSDL3 at runtime — no SDL3 import in the Orhon module declaration.

**Internal structure (Zig sidecar):** The existing `VulkanContext + RenderGraph` split is correct. Keep them as internal Zig structs; expose only `Renderer` to the Orhon side.

---

### TamgaVK2D — Vulkan 2D Renderer

**Responsibility:** High-throughput 2D rendering: sprites, shapes, text atlas, immediate draw list.

| Concern | Included | Excluded |
|---------|----------|----------|
| Sprite batching | sorted draw calls, texture atlas binding | 3D transforms |
| Shape primitives | filled/stroked rect, circle, line | mesh geometry |
| Text rendering | font atlas upload, glyph quads | font loading (separate concern) |
| Coordinate system | orthographic projection, pixel or NDC coords | depth buffer |
| Render order | painter's algorithm (back-to-front), z-order int | depth testing |

**Relationship to TamgaVK3D:** These are sibling modules — same Vulkan initialization pattern, independent swapchains (or shared swapchain via `Ptr(u8)` handle). They do NOT import each other. A user app imports whichever it needs.

**GUI integration:** TamgaGUI renders through TamgaVK2D draw calls. TamgaGUI imports TamgaVK2D, not vice versa — dependency direction is GUI → VK2D.

---

### TamgaAudio — Audio Playback

**Responsibility:** WAV sound effects + OGG music streaming, volume, basic mixing.

| Concern | Included | Excluded |
|---------|----------|----------|
| WAV playback | load, play, stop, volume | streaming (one-shot SFX) |
| OGG streaming | streaming decode, loop, crossfade | DSP effects |
| Mixing | simple per-channel volume, master volume | spatial/3D audio |
| Lifecycle | audio context init/quit | SDL_INIT_AUDIO (internal) |

**Independence:** TamgaAudio has no dependency on TamgaSDL3, TamgaVK3D, or TamgaVK2D. It is completely standalone. Audio init (SDL_INIT_AUDIO or miniaudio) lives inside the audio Zig sidecar.

**Extensibility contract:** Design the Zig sidecar with a mixer callback architecture so spatial audio and DSP effects can be added later without breaking the Orhon API. Expose only the high-level API (play/stop/volume) to Orhon now.

---

### TamgaGUI — GUI Library

**Responsibility:** Both retained-mode widgets (persistent state) and immediate-mode draw API (stateless per-frame).

| Concern | Included | Excluded |
|---------|----------|----------|
| Retained widgets | Button, Label, Panel, ScrollView, Input | 3D scene widgets |
| Immediate mode | draw commands issued per-frame, no state | persistent layout trees |
| Layout | flex-style or manual rect layout | CSS-level layout engine |
| Theming | color palette, font size constants | CSS/runtime stylesheets |
| Input routing | mouse hit-testing, keyboard focus | raw event polling |
| Renderer bridge | emits draw calls to TamgaVK2D | owns Vulkan pipeline |

**Mode unification strategy:** Use a single library where retained widgets are built on top of the immediate draw layer. Retained = immediate draw calls with cached per-widget state. This is the Dear ImGui + nuklear approach — the immediate layer is the core, retained adds state management above it.

**Input flow:** TamgaGUI receives pre-processed input structs (mouse position, button bitmask, key events) passed by the application from TamgaSDL3 event data. TamgaGUI does NOT import TamgaSDL3 — the app layer bridges raw SDL events into GUI-friendly input structs. This keeps GUI portable across future platform backends.

---

## Data Flow

### Frame Loop (3D Application)

```
SDL event poll (TamgaSDL3)
    │
    ▼
Application processes events
    │
    ├──► Input state update (keyboard/mouse bitmask)
    │
    ▼
TamgaVK3D.beginFrame()
    │  acquires swapchain image, waits on fence
    ▼
Application submits draw commands
    │  (future: meshes, transforms, materials)
    ▼
TamgaVK3D.endFrame()
    │  submits command buffer, presents
    ▼
TamgaAudio (runs on separate thread / callback)
    │  decoder feeds audio device continuously
    ▼
Frame complete → getTicks() for timing
```

### Frame Loop (2D Application with GUI)

```
SDL event poll (TamgaSDL3)
    │
    ▼
Application extracts input → builds GuiInput struct
    │
    ▼
TamgaVK2D.beginFrame()
    │
    ▼
TamgaGUI.beginFrame(gui_input)
    │  immediate: issue draw calls to TamgaVK2D
    │  retained: update widget state, then issue draw calls
    ▼
TamgaGUI.endFrame()
    │
    ▼
TamgaVK2D.endFrame()
    │  flush draw list, present
    ▼
Frame complete
```

### Input Data Flow

```
SDL3 (C)
    │  SDL_Event (C struct)
    ▼
TamgaSDL3 bridge (Zig sidecar)
    │  Event struct with typed accessors
    ▼
Application (Orhon)
    │  application-level input state (key bitmask, mouse pos)
    │
    ├──► Game logic (move player, etc.)
    └──► TamgaGUI input struct (mouse pos, clicks, char input)
```

**Rule:** Raw SDL event types never appear in TamgaGUI or TamgaVK3D/VK2D. The application layer is responsible for translating between SDL events and the higher-level inputs each library expects.

---

## Build Order (Dependency Graph)

The modules form a DAG. Build and stabilize in this order:

```
Phase 1 (foundation)
  tamga_sdl3  ─────────────────────────────────┐
                                                │ window handle
Phase 2 (renderers)                             ▼
  tamga_vk3d  ◄── window_handle (Ptr u8) ──── [app]
  tamga_vk2d  ◄── window_handle (Ptr u8) ──── [app]

Phase 3 (audio, independent)
  tamga_audio ◄── no framework deps

Phase 4 (GUI, depends on VK2D)
  tamga_gui   ◄── tamga_vk2d (draw calls)
```

Rationale for this order:
1. `tamga_sdl3` must exist first — it provides the window handle every renderer needs.
2. `tamga_vk3d` and `tamga_vk2d` can be developed in parallel (same Vulkan init pattern, different draw systems).
3. `tamga_audio` has zero framework dependencies — can be built any time after the platform work stabilizes.
4. `tamga_gui` depends on `tamga_vk2d` being stable enough to accept draw calls. Build last.

---

## Patterns to Follow

### Pattern 1: Opaque Handle Isolation

**What:** Renderers receive `Ptr(u8)` (opaque window handle) from `TamgaSDL3.Window.getHandle()`. They never import `tamga_sdl3`.

**Why:** Prevents tight coupling. The renderer doesn't care about SDL internals — it only needs the OS window handle to create a Vulkan surface. Future backends (GLFW, raw Win32) can provide the same `Ptr(u8)` without changing renderer modules.

**Example:**
```
// Application bootstrap — the only place tamga_sdl3 and tamga_vk3d coexist
let win = try Window.create("My App", 1280, 720, WINDOW_VULKAN)
let renderer = try tamga_vk3d.Renderer.create(win.getHandle(), false)
```

---

### Pattern 2: Bridge-Thin, Orhon-Fat

**What:** Zig sidecar files handle raw C interop only. Higher-level logic — resource management, type-safe wrappers, error translation — lives in Orhon.

**Why:** Orhon gets the language workout. Zig sidecars stay minimal and easy to audit. The Orhon type system validates usage at compile time.

**Boundary:** If it requires a C header, it's in Zig. If it can be expressed in Orhon types, it's in Orhon.

---

### Pattern 3: Renderer-Agnostic GUI Input

**What:** TamgaGUI accepts an input value struct containing mouse position, button state, and key events. It does not call TamgaSDL3 or access raw SDL events.

**Why:** GUI portability. The same TamgaGUI module works regardless of how the host application sources input. Required for future engine integration where the game engine might intercept inputs before the GUI sees them.

---

### Pattern 4: Render Graph for Future-Proofing

**What:** TamgaVK3D already uses a `RenderGraph` struct internally (as seen in existing Zig sidecar). Maintain this pattern. Each rendering concern (shadow pass, geometry pass, post-process pass) is a node.

**Why:** Adding geometry, shadows, or post-processing later requires no restructuring. The existing `// future: execute registered pass callbacks here` comment marks the extension point explicitly.

---

### Pattern 5: Audio Callback Architecture

**What:** TamgaAudio Zig sidecar uses an audio device callback pattern rather than polling. The mixer runs on the audio thread; the Orhon API submits commands (play, stop, volume) as thread-safe messages.

**Why:** Audio must not stutter when the main thread is busy rendering. Callback-based audio (SDL_AudioStream or miniaudio) runs independently of frame rate.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: SDL3 Leakage Into Renderer Modules

**What:** Importing `tamga_sdl3` inside `tamga_vk3d` or `tamga_vk2d`.

**Why bad:** Couples rendering to the platform layer. If SDL3 is ever swapped out, every renderer module breaks. SDL3 event types appearing in renderer headers also pollutes the API surface.

**Instead:** Pass `Ptr(u8)` window handle. Renderers call `SDL_Vulkan_CreateSurface` inside the Zig sidecar where it belongs — not from Orhon-visible API.

---

### Anti-Pattern 2: Shared Vulkan State Between 2D and 3D Renderers

**What:** A single Vulkan context (device, swapchain, queues) shared between TamgaVK2D and TamgaVK3D.

**Why bad:** Creates a hidden dependency between sibling modules. If the user only needs 2D, they'd still drag in 3D initialization. Testing in isolation becomes impossible.

**Instead:** Each renderer owns its own Vulkan context. If a future "composite renderer" layer is needed (render 3D scene + 2D HUD in one frame), build it as a separate module above both.

---

### Anti-Pattern 3: GUI Owning the Render Pipeline

**What:** TamgaGUI creates its own Vulkan pipeline, swap chain, or command buffers.

**Why bad:** GUI output would be disconnected from the main renderer's frame. Compositing them would require explicit synchronization or two present calls.

**Instead:** TamgaGUI emits a draw list (rectangles, text quads, colors) and hands it to TamgaVK2D. TamgaVK2D flushes the GUI draw list as part of the same frame as all other 2D content.

---

### Anti-Pattern 4: Synchronous Audio Loading on Main Thread

**What:** WAV/OGG loading happens inside the frame loop in response to a play call.

**Why bad:** File I/O causes visible frame hitches. Audio assets can be multi-megabyte.

**Instead:** Provide explicit load/preload calls that are separate from play. WAV files buffer fully at load time; OGG files begin decoding on a background thread or during a load phase.

---

### Anti-Pattern 5: Module Anchor File With Logic

**What:** Putting initialization code, struct fields, or substantial logic in the module's anchor `.orh` file (the file matching `<modulename>.orh`).

**Why bad:** Orhon's anchor file is where `#build`, `#dep`, and module metadata live. Mixing metadata with logic makes it harder to understand what the anchor does and risks confusing the compiler (Orhon is young; simpler patterns reduce compiler bug surface).

**Instead:** Use the anchor file for metadata and import declarations only. Logic lives in additional `.orh` files in the same module directory.

---

## Scalability Considerations

| Concern | Current Scope | Later (Engine) |
|---------|--------------|----------------|
| Draw calls | Minimal (clear screen prototype) | Batching, instancing, culling |
| Audio channels | WAV + OGG playback | Spatial, DSP, N-channel mixing |
| GUI complexity | Basic widgets | Scene editor, dockable panels |
| Platform backends | SDL3 only | Multiple (GLFW, native) via same interface |
| Build targets | Linux dev primary | Linux + Windows + macOS |

**Extensibility seams to protect now:**
- `Window.getHandle() Ptr(u8)` — keeps platform swappable
- `TamgaAudio` audio callback architecture — keeps DSP chain insertable
- `RenderGraph` in TamgaVK3D — keeps render pass topology flexible
- GUI input struct decoupled from SDL — keeps GUI portable

---

## Reference: How Major Frameworks Structure This

**Confidence: MEDIUM** — Based on training data from SDL, Sokol, SFML, Bevy, Godot documentation. Live verification not available during this session.

| Framework | Windowing | Renderer | Audio | GUI | Key Lesson |
|-----------|-----------|----------|-------|-----|------------|
| SDL3 | SDL_Window | SDL_Renderer or external (Vulkan/GL) | SDL_Audio | External (Dear ImGui) | Platform layer stays thin; graphics handed off |
| Sokol | sokol_app | sokol_gfx (backend-agnostic) | sokol_audio | sokol_imgui (ImGui bridge) | Header-per-concern, zero cross-header state |
| Bevy | winit plugin | wgpu render plugin | rodio audio plugin | bevy_ui plugin | Plugin system; every subsystem is a plugin; ECS events connect them |
| SFML | sf::Window | sf::RenderWindow / sf::RenderTexture | sf::Sound + sf::Music | External | RenderWindow subclasses Window — now considered a design mistake |
| Godot | DisplayServer | RenderingServer (abstract) | AudioServer | Control nodes | Servers are global singletons; nodes dispatch to them |

**Lesson for Tamga:** Sokol's one-concern-per-module approach maps most naturally to Orhon's module system. Bevy's plugin isolation is also instructive — no subsystem imports another at the module level; they communicate through shared events/data at the application layer.

The SFML anti-pattern of `RenderWindow extends Window` is worth explicitly avoiding — do not make `tamga_vk3d` subclass or wrap `tamga_sdl3`. The opaque handle boundary (Pattern 1 above) is the Tamga answer to this.

---

## Sources

- Existing codebase: `src/TamgaSDL3/tamga_sdl3.orh`, `src/TamgaSDL3/tamga_sdl3.zig`, `src/TamgaVK3D/tamga_vk3d.orh`, `src/TamgaVK3D/tamga_vk3d.zig` — HIGH confidence (direct inspection)
- `CLAUDE.md` framework design goals and bridge safety rules — HIGH confidence
- `.planning/PROJECT.md` requirements and constraints — HIGH confidence
- SDL3, Sokol, SFML, Bevy, Godot architectural patterns — MEDIUM confidence (training data, not live-verified)
