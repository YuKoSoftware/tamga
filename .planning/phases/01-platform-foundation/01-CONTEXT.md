# Phase 1: Platform Foundation - Context

**Gathered:** 2026-03-25 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Complete TamgaSDL3 — windowing, input, events, opaque handles, and the cross-cutting standards all modules depend on. A developer can open a window, receive all input events, and hand an opaque handle to a renderer — with no SDL3 type leaking above the module boundary.

</domain>

<decisions>
## Implementation Decisions

### SDL3 Abstraction Architecture
- **D-01:** Restructure `tamga_sdl3` into a two-layer design: internal bridge layer (`.zig` sidecar talking to SDL3 C API) and public Orhon API layer that wraps it with Tamga-native types
- **D-02:** No SDL3 constants, structs, or enums leak above the module boundary — all public types are Tamga-native (Orhon enums, structs, named types)
- **D-03:** Downstream modules (TamgaVK3D, TamgaAudio, etc.) import only the public Tamga types, never internal SDL3 bindings

### Event System
- **D-04:** Replace the current flat accessor pattern (`event.getType()` + type-specific getters) with a type-safe structured event model
- **D-05:** Event system must cover keyboard, mouse, gamepad, text input, window resize, and close events — all with typed payloads
- **D-06:** Event design should use Orhon's type system (tagged union if supported, otherwise typed structs with dispatcher) to prevent wrong-getter-on-wrong-event bugs

### Opaque Window Handle
- **D-07:** Formalize `Ptr(u8)` as a named opaque `WindowHandle` type — the sole surface exposed to downstream renderer modules
- **D-08:** `WindowHandle` replaces raw `Ptr(u8)` in both TamgaSDL3's public API and TamgaVK3D's constructor signature

### Frame Loop
- **D-09:** Frame loop lives inside the platform module as a struct/callback system — user provides update and render callbacks, calls `loop.run()`
- **D-10:** Fixed timestep for update, variable timestep for render; delta time accessible to user code
- **D-11:** Clean start/stop lifecycle with proper resource cleanup

### Cross-Cutting Standards
- **D-12:** Error propagation via Orhon error unions on all initialization paths (WIN-10)
- **D-13:** HiDPI awareness via pixel density flag and correct pixel dimensions in resize events (WIN-09)
- **D-14:** Compiler bugs logged in `docs/bugs.txt`, language ideas in `docs/ideas.txt` before any workaround (XC-05, XC-06)

### Claude's Discretion
- Internal bridge function naming conventions
- Exact frame loop callback signature design
- Whether cursor lock/hide is a Window method or standalone function
- Display info query struct field layout

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing SDL3 Bridge
- `src/TamgaSDL3/tamga_sdl3.orh` — Current public API: Window struct, Event struct, init/quit, timing functions
- `src/TamgaSDL3/tamga_sdl3.zig` — Zig sidecar: SDL3 C interop, window creation, event handling, timing

### Existing VK3D Consumer
- `src/TamgaVK3D/tamga_vk3d.orh` — Shows how downstream modules consume WindowHandle (currently `Ptr(u8)`)
- `src/TamgaVK3D/tamga_vk3d.zig` — Shows internal SDL3 cast pattern (`*c.SDL_Window` on line 700)

### Integration Tests
- `src/test/test_sdl3.orh` — Current SDL3 usage patterns, event loop, window creation
- `src/test/test_vulkan.orh` — Current renderer + window integration pattern

### Project Entry Point
- `src/main.orh` — Module main with build metadata

### Bug/Ideas Tracking
- `docs/bugs.txt` — Known compiler and upstream bugs
- `docs/ideas.txt` — Language feature requests and ideas

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `tamga_sdl3.zig` — Working SDL3 C bridge with `SDL_Init`, `SDL_CreateWindow`, `SDL_PollEvent`, `SDL_GetTicks`, `SDL_Delay`, `SDL_Vulkan_CreateSurface`, `SDL_Vulkan_GetInstanceExtensions`. Core bridge functions are validated and working.
- `tamga_sdl3.orh` — Existing bridge declarations for Window, Event, init/quit. Structure needs refactoring but the bridge pattern itself is proven.
- `tamga_vk3d.zig` — Demonstrates the SDL_Window handle consumption pattern from the renderer side, confirming the opaque handle approach works end-to-end.

### Established Patterns
- **Bridge pattern:** `.orh` declares `bridge func` / `bridge struct`, `.zig` implements via `@cImport("SDL3/SDL.h")`. Confirmed working.
- **Linking:** `#linkC "SDL3"` directive works (confirmed in `docs/bugs.txt`).
- **Module structure:** Each library is a directory under `src/` with an anchor `.orh` file matching the module name.
- **Test pattern:** `src/test/` contains integration tests that import library modules directly.

### Integration Points
- **TamgaVK3D** consumes `WindowHandle` for Vulkan surface creation — signature change from `Ptr(u8)` to `WindowHandle` required
- **TamgaVK3D** calls `SDL_Vulkan_CreateSurface` and `SDL_Vulkan_GetInstanceExtensions` internally via its own `.zig` sidecar — these stay in VK3D's bridge, not the platform layer
- **Future modules** (TamgaAudio, TamgaVK2D) will depend on the platform layer for initialization and event handling

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

None — analysis stayed within phase scope

### Research Topics for Downstream
- SDL3 Gamepad API surface (`SDL_OpenGamepad`, `SDL_GetGamepadAxis`, gamepad events)
- SDL3 Text Input API (`SDL_StartTextInput`, `SDL_EVENT_TEXT_INPUT`, UTF-8 handling)
- SDL3 Display/Monitor query API (`SDL_GetDisplays`, `SDL_GetDisplayBounds`, `SDL_GetDisplayContentScale`)
- Orhon tagged union / sum type support for event system design

</deferred>

---

*Phase: 01-platform-foundation*
*Context gathered: 2026-03-25*
