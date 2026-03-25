# Phase 01: Platform Foundation - Research

**Researched:** 2026-03-25
**Domain:** SDL3 windowing/input, Orhon language type system, fixed-timestep game loop
**Confidence:** HIGH (working codebase + official SDL3 docs verified)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Restructure `tamga_sdl3` into a two-layer design: internal bridge layer (`.zig` sidecar talking to SDL3 C API) and public Orhon API layer that wraps it with Tamga-native types
- **D-02:** No SDL3 constants, structs, or enums leak above the module boundary — all public types are Tamga-native (Orhon enums, structs, named types)
- **D-03:** Downstream modules (TamgaVK3D, TamgaAudio, etc.) import only the public Tamga types, never internal SDL3 bindings
- **D-04:** Replace the current flat accessor pattern (`event.getType()` + type-specific getters) with a type-safe structured event model
- **D-05:** Event system must cover keyboard, mouse, gamepad, text input, window resize, and close events — all with typed payloads
- **D-06:** Event design should use Orhon's type system (tagged union if supported, otherwise typed structs with dispatcher) to prevent wrong-getter-on-wrong-event bugs
- **D-07:** Formalize `Ptr(u8)` as a named opaque `WindowHandle` type — the sole surface exposed to downstream renderer modules
- **D-08:** `WindowHandle` replaces raw `Ptr(u8)` in both TamgaSDL3's public API and TamgaVK3D's constructor signature
- **D-09:** Frame loop lives inside the platform module as a struct/callback system — user provides update and render callbacks, calls `loop.run()`
- **D-10:** Fixed timestep for update, variable timestep for render; delta time accessible to user code
- **D-11:** Clean start/stop lifecycle with proper resource cleanup
- **D-12:** Error propagation via Orhon error unions on all initialization paths (WIN-10)
- **D-13:** HiDPI awareness via pixel density flag and correct pixel dimensions in resize events (WIN-09)
- **D-14:** Compiler bugs logged in `docs/bugs.txt`, language ideas in `docs/ideas.txt` before any workaround (XC-05, XC-06)

### Claude's Discretion

- Internal bridge function naming conventions
- Exact frame loop callback signature design
- Whether cursor lock/hide is a Window method or standalone function
- Display info query struct field layout

### Deferred Ideas (OUT OF SCOPE)

None — analysis stayed within phase scope.

Research topics for downstream phases (not this phase):
- SDL3 Gamepad API deeper dive (axis deadzones, rumble)
- SDL3 Text Input IME handling edge cases
- SDL3 Display/Monitor query for multi-monitor layouts
- Orhon tagged union / sum type support investigation (see findings below)

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| WIN-01 | Create window with title, size, and flags (resizable, fullscreen, borderless, Vulkan) | SDL3 bridge already creates windows; needs Tamga-native flag enums replacing raw `u64` constants |
| WIN-02 | Window resize events propagated | `SDL_EVENT_WINDOW_RESIZED` and `SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED` documented; need typed `WindowResized` event payload |
| WIN-03 | Window close / quit events trigger clean shutdown | `SDL_EVENT_WINDOW_CLOSE_REQUESTED` + `SDL_EVENT_QUIT` both exist; needs typed `WindowClose` event + `Quit` event |
| WIN-04 | Keyboard input: key down/up with scancodes | Already in bridge (`EVENT_KEY_DOWN`, `getScancode`); needs `KeyDown`/`KeyUp` typed event structs with full scancode enum |
| WIN-05 | Mouse input: position, delta, button press/release | Already in bridge (motion + button events); needs typed `MouseMotion`, `MouseButton` event structs |
| WIN-06 | Gamepad/controller input via SDL3 Gamepad API | NOT in current bridge; needs `SDL_OpenGamepad`, `SDL_EVENT_GAMEPAD_AXIS_MOTION`, `SDL_EVENT_GAMEPAD_BUTTON_DOWN/UP`, `SDL_EVENT_GAMEPAD_ADDED/REMOVED` added to `.zig` sidecar |
| WIN-07 | Event polling loop with timing and delta time helpers | `SDL_GetTicks()` already in bridge; fixed-timestep loop needs `SDL_GetPerformanceCounter` / `SDL_GetTicksNS` for sub-millisecond precision |
| WIN-08 | Cursor hide/show/lock (relative mouse mode) | `SDL_SetWindowRelativeMouseMode`, `SDL_HideCursor`, `SDL_ShowCursor` documented; not yet in bridge |
| WIN-09 | HiDPI / pixel density awareness | `SDL_WINDOW_HIGH_PIXEL_DENSITY` flag already in bridge; resize event must use `SDL_GetWindowSizeInPixels` for pixel dims, not logical dims |
| WIN-10 | Error propagation on initialization failure | Orhon `(Error | T)` union pattern confirmed working in existing bridge; apply consistently |
| WIN-11 | Text input events (Unicode) | `SDL_StartTextInput(window)`, `SDL_EVENT_TEXT_INPUT`, `event.text.text` (UTF-8 string) — not yet in bridge |
| WIN-12 | Full SDL3 abstraction — no SDL3 types leak | Requires complete public API rewrite; bridge layer stays internal, public layer exports only Tamga types |
| WIN-13 | Window handle exposed as opaque type | `getHandle()` already returns `Ptr(u8)`; needs `WindowHandle` named type alias + VK3D signature update |
| WIN-14 | Multiple monitor / display info query | `SDL_GetDisplays`, `SDL_GetDisplayBounds`, `SDL_GetDisplayContentScale`, `SDL_GetDisplayName` — not yet in bridge; needs `DisplayInfo` struct |
| XC-01 | All APIs easy to use — complexity inside libraries | Research confirms: window creation, event loop, frame loop must be trivial from user code |
| XC-02 | Each component independent library module | Existing `tamga_sdl3` module structure is correct; maintain clean boundary |
| XC-03 | All native bindings via Zig bridge only | Confirmed: `.orh` `bridge` declarations + `.zig` sidecar is the only valid pattern |
| XC-04 | Cross-platform: Linux, Windows, macOS | SDL3 handles this; `#linkC "SDL3"` directive is confirmed cross-platform; no platform-specific code in `.orh` files |
| XC-05 | Orhon compiler bugs logged in docs/bugs.txt | Established pattern from bugs.txt; apply throughout |
| XC-06 | No workarounds — fix compiler first | Project policy; implementation must follow this strictly |
| LOOP-01 | Configurable frame loop with fixed timestep update and variable render | Fixed-timestep game loop algorithm documented below; callback pattern confirmed feasible with Orhon function pointers |
| LOOP-02 | Delta time accessible to user code | `SDL_GetTicksNS` (nanoseconds) preferred for precision; expose as `f64` seconds in public API |
| LOOP-03 | Clean start/stop lifecycle | `defer` + `destroy()` pattern confirmed working in existing test code |

</phase_requirements>

---

## Summary

Phase 1 refactors and extends the existing `tamga_sdl3` module from a thin C bridge into a two-layer architecture: an internal Zig bridge that speaks raw SDL3 C, and a public Orhon API that exposes only Tamga-native types. The existing bridge is a solid foundation — window creation, basic events, Vulkan integration, and the `#linkC "SDL3"` directive are all confirmed working.

The primary work is: (1) designing Tamga-native types for window flags, event payloads, and error results; (2) adding missing SDL3 functionality — gamepad API, text input, cursor control, display info, and pixel-size-correct resize events; and (3) implementing a fixed-timestep frame loop using Orhon function pointers and SDL3 high-precision timing.

The Orhon type system supports arbitrary union types (`(KeyEvent | MouseEvent | GamepadEvent | ...)`), `match` on integers/strings, `enum`, `struct`, `bitfield`, and function pointers — which are sufficient to build the type-safe event system required by D-04/D-06. There are NO tagged unions (Rust-style `enum Foo { Bar(i32), Baz(String) }`) as a named construct; the union-with-`is` pattern (`(TypeA | TypeB)`) IS the discriminated union mechanism.

**Primary recommendation:** Design the public event API as a `(KeyDown | KeyUp | MouseMotion | MouseButton | GamepadAxis | GamepadButton | GamepadAdded | GamepadRemoved | TextInput | WindowResized | WindowClose | Quit)` union type returned by a polling function, translated from raw `SDL_Event` in the Zig sidecar.

---

## Project Constraints (from CLAUDE.md)

These directives are mandatory. The planner must verify all tasks comply.

| Directive | Implication for This Phase |
|-----------|---------------------------|
| Pure Orhon for library code; C/system interop only through Zig bridge | All new SDL3 API calls go in `.zig` sidecar only; no `@cImport` in `.orh` files |
| `#linkC "SDL3"` in anchor file | Already present in `tamga_sdl3.orh`; do not remove |
| No SDL3 types leak above module boundary (D-02) | Public `.orh` declarations must not reference any `c.SDL_*` type |
| Compiler bugs logged in `docs/bugs.txt` before workaround | Log any Orhon union/enum limitation encountered during event type design |
| Language ideas in `docs/ideas.txt` | Log any language friction (e.g., "wish we had named tagged unions") |
| No workarounds — fix compiler first | If a language feature is broken, stop, fix it, then return |
| Never edit `.orh-cache/generated/` manually | Cache is managed by `orhon build` only |
| Anchor file rule: exactly one file per module named `<modulename>.orh` | The `tamga_sdl3.orh` file is the anchor; additional files are `module tamga_sdl3` files in the same directory |
| `orhon test` runs all `test { }` blocks | Integration tests in `src/test/` are the validation mechanism |

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SDL3 | 3.x system | Window, input, events, timing, Vulkan surface | Already working; `#linkC "SDL3"` confirmed; complete rewrite of SDL2 with better Vulkan integration |
| Zig | 0.15.x | Bridge / C interop layer | Required by Orhon compiler; `@cImport` / `@cInclude` is the only supported C interop path |
| Orhon compiler | current | Build system | `orhon build` compiles `.orh` + `.zig` sidecar |

### SDL3 Functions Required (new additions to bridge)

| Function | Purpose | Event/Use |
|----------|---------|-----------|
| `SDL_GetWindowSizeInPixels` | Pixel-correct dimensions for HiDPI | WIN-09, WIN-02 |
| `SDL_GetWindowDisplayScale` | DPI scale factor | WIN-09 |
| `SDL_SetWindowRelativeMouseMode` | Cursor lock for 3D viewports | WIN-08 |
| `SDL_HideCursor` / `SDL_ShowCursor` | Cursor visibility | WIN-08 |
| `SDL_StartTextInput(window)` | Enable text input mode | WIN-11 |
| `SDL_StopTextInput(window)` | Disable text input mode | WIN-11 |
| `SDL_OpenGamepad` | Open a gamepad device | WIN-06 |
| `SDL_CloseGamepad` | Release a gamepad device | WIN-06 |
| `SDL_GetGamepads` | Enumerate connected gamepads | WIN-06 |
| `SDL_GetDisplays` | List connected displays | WIN-14 |
| `SDL_GetDisplayName` | Display name string | WIN-14 |
| `SDL_GetDisplayBounds` | Display position/size | WIN-14 |
| `SDL_GetDisplayContentScale` | DPI scale for display | WIN-14 |
| `SDL_GetTicksNS` | Nanosecond-precision timer | LOOP-01, LOOP-02 |
| `SDL_DelayNS` | Sub-millisecond sleep | LOOP-01 |

### SDL3 Event Types Required (new additions to bridge)

| Event | Union Variant | Data |
|-------|--------------|------|
| `SDL_EVENT_WINDOW_RESIZED` | `WindowResized` | logical w, h |
| `SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED` | `WindowPixelResized` | pixel w, h (HiDPI) |
| `SDL_EVENT_WINDOW_CLOSE_REQUESTED` | `WindowClose` | — |
| `SDL_EVENT_GAMEPAD_AXIS_MOTION` | `GamepadAxis` | which, axis, value (-32768..32767) |
| `SDL_EVENT_GAMEPAD_BUTTON_DOWN` | `GamepadButtonDown` | which, button |
| `SDL_EVENT_GAMEPAD_BUTTON_UP` | `GamepadButtonUp` | which, button |
| `SDL_EVENT_GAMEPAD_ADDED` | `GamepadAdded` | which (SDL_JoystickID) |
| `SDL_EVENT_GAMEPAD_REMOVED` | `GamepadRemoved` | which |
| `SDL_EVENT_TEXT_INPUT` | `TextInput` | text (UTF-8, up to 32 bytes) |

---

## Architecture Patterns

### Recommended Module Structure

```
src/TamgaSDL3/
    tamga_sdl3.orh          # anchor + bridge declarations (public API only — Tamga types)
    tamga_sdl3.zig          # Zig sidecar (all SDL3 C interop, no Orhon-facing types)
    tamga_loop.orh          # module tamga_sdl3 — frame loop struct + callback system
```

The frame loop is a separate `.orh` file in the same module (same `module tamga_sdl3` declaration). This keeps `tamga_sdl3.orh` from becoming a monolith while keeping the loop inside the platform module as required by D-09.

### Pattern 1: Two-Layer Bridge Architecture

**What:** The `.zig` sidecar speaks raw SDL3 C. The public `.orh` declarations are pure Tamga types. No `c.SDL_*` types cross the bridge boundary.

**When to use:** Always. This is the only compliant pattern for D-02/D-03.

**Bridge layer (internal, in `.zig`):**
```zig
// tamga_sdl3.zig  (extract — internal, never exposed)
const c = @cImport(@cInclude("SDL3/SDL.h"));

// Translate SDL_Event union into a flat discriminated struct
pub const RawEvent = struct {
    tag: u8,              // discriminator: 0=none, 1=keydown, 2=keyup, etc.
    key_scancode: u32,
    key_repeat: bool,
    mouse_x: f32,
    mouse_y: f32,
    mouse_xrel: f32,
    mouse_yrel: f32,
    mouse_button: u8,
    mouse_down: bool,
    gamepad_which: u32,
    gamepad_axis: u8,
    gamepad_axis_value: i16,
    gamepad_button: u8,
    text: [32]u8,
    window_w: i32,
    window_h: i32,
    pixel_w: i32,
    pixel_h: i32,
};

pub fn pollRawEvent(out: *RawEvent) bool {
    var ev: c.SDL_Event = undefined;
    if (!c.SDL_PollEvent(&ev)) return false;
    // translate ev into out fields using ev.type switch
    // ...
    return true;
}
```

**Public layer (Orhon, in `.orh`):**
```
// tamga_sdl3.orh  (public API — Tamga-native types only)
pub type WindowHandle = Ptr(u8)   // opaque — downstream never casts this

pub enum(u8) WindowFlag {
    Resizable
    Fullscreen
    Borderless
    Vulkan
    HighPixelDensity
}

pub bitfield(u32) WindowFlags {
    Resizable
    Fullscreen
    Borderless
    Vulkan
    HighPixelDensity
}

pub struct KeyDownEvent {
    pub scancode: Scancode   // Tamga enum, not SDL scancode int
    pub repeat: bool
    pub timestamp: u64
}

// ... other event payload structs

pub type Event = (
    | KeyDown(KeyDownEvent)     // Orhon union type syntax TBD — see Pitfall 1
    | KeyUp(KeyUpEvent)
    | MouseMotion(MouseMotionEvent)
    | MouseButton(MouseButtonEvent)
    | GamepadAxis(GamepadAxisEvent)
    | GamepadButtonDown(GamepadButtonEvent)
    | GamepadButtonUp(GamepadButtonEvent)
    | GamepadAdded(u32)
    | GamepadRemoved(u32)
    | TextInput(String)
    | WindowResized(i32, i32)
    | WindowPixelResized(i32, i32)
    | WindowClose
    | Quit
)
```

### Pattern 2: Event Union with `is` Dispatch

**What:** Orhon's union type `(A | B | C)` combined with `if(event is KeyDown)` / `match` is the type-safe dispatch mechanism.

**When to use:** All event handling in user code.

**User code (callers of TamgaSDL3):**
```
while(true) {
    const ev = platform.pollEvent()
    if(ev is null) { break }
    if(ev is KeyDown) {
        const kd = ev.value
        if(kd.scancode == Scancode.Escape) { running = false }
    }
    if(ev is MouseMotion) {
        const mm = ev.value
        camera.yaw += mm.xrel * sensitivity
    }
    if(ev is GamepadAxis) {
        const ga = ev.value
        // ga.axis, ga.value, ga.gamepad_id
    }
}
```

### Pattern 3: Fixed-Timestep Frame Loop

**What:** Classic fixed-update / variable-render game loop. Update runs at a fixed rate (e.g., 60 Hz); render runs as fast as possible with interpolation alpha.

**Algorithm:**
```
const FIXED_STEP_NS: u64 = 16_666_667   // ~60 Hz in nanoseconds

var accumulator: u64 = 0
var last_time: u64 = SDL_GetTicksNS()

while(running) {
    const now: u64 = SDL_GetTicksNS()
    var frame_time: u64 = now - last_time
    // clamp to prevent spiral of death (> 250 ms)
    if(frame_time > 250_000_000) { frame_time = 250_000_000 }
    last_time = now
    accumulator += frame_time

    // process events
    while(accumulator >= FIXED_STEP_NS) {
        update_callback(FIXED_STEP_NS_AS_F64_SECONDS)
        accumulator -= FIXED_STEP_NS
    }

    const alpha: f64 = cast(f64, accumulator) / cast(f64, FIXED_STEP_NS)
    render_callback(alpha)
}
```

**Orhon callback signature (Claude's discretion — recommended):**
```
pub struct LoopConfig {
    pub fixed_hz: f64
    pub on_event: func(Event) void
    pub on_update: func(f64) void     // dt in seconds
    pub on_render: func(f64) void     // alpha 0..1 interpolation factor
}

pub struct Loop {
    pub func create(config: LoopConfig) Loop
    pub func run(self: &Loop) void
    pub func stop(self: &Loop) void
    pub func destroy(self: &Loop) void
}
```

### Pattern 4: WindowHandle as Opaque Type

**What:** `WindowHandle` is a named `Ptr(u8)` — downstream modules receive it and pass it straight to their own Zig sidecar, which casts it to `*c.SDL_Window`.

**In `tamga_sdl3.orh`:**
```
pub type WindowHandle = Ptr(u8)

pub bridge struct Window {
    // ...
    bridge func getHandle(self: const &Window) WindowHandle
}
```

**In `tamga_vk3d.orh` (downstream — after Phase 1 update):**
```
import tamga_sdl3

pub bridge struct Renderer {
    bridge func create(window: tamga_sdl3.WindowHandle, debug_mode: bool) (Error | Renderer)
    // ...
}
```

**In `tamga_vk3d.zig` (already does this):**
```zig
// line 700 pattern — unchanged, still valid
ctx.sdl_window = @ptrCast(@alignCast(window_handle));
```

### Anti-Patterns to Avoid

- **Exposing raw `u32` event type integer:** The old `getType()` + switch pattern allows calling `getScancode()` on a mouse event. Replace entirely with the typed union.
- **Exposing raw `u64` SDL window flags:** User code should never write `WINDOW_RESIZABLE | WINDOW_VULKAN`; use `WindowFlags(Resizable, Vulkan)` bitfield constructor.
- **Calling `SDL_GetWindowSize` for pixel operations:** Always use `SDL_GetWindowSizeInPixels` when pixel-accurate dimensions are needed (Vulkan swapchain size, HiDPI-correct rendering).
- **Using `SDL_GetTicks` (milliseconds) for the frame loop:** Use `SDL_GetTicksNS` for nanosecond precision. `SDL_GetTicks` rounds to ms, causing jitter in the fixed-timestep accumulator.
- **Putting SDL3 event constants in `.orh` as `pub bridge const`:** These are internal constants; translate them in the `.zig` sidecar, never expose them.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Window management | Custom window abstraction | SDL3 via Zig bridge | SDL3 handles OS differences, DPI, Vulkan surface integration |
| Input handling | Raw platform input | SDL3 event system | SDL3 unifies keyboard, mouse, gamepad, text input across all platforms |
| High-precision timer | Platform-specific timer | `SDL_GetTicksNS` | SDL3 provides nanosecond precision cross-platform |
| Cursor management | Platform cursor API | `SDL_SetWindowRelativeMouseMode`, `SDL_HideCursor` | SDL3 handles Wayland/X11/Win32 differences |
| Display enumeration | Platform display API | `SDL_GetDisplays` / `SDL_GetDisplayBounds` | SDL3 abstracts OS monitor APIs |
| Gamepad database | Custom gamepad mapping | SDL3 Gamepad API | SDL3 ships `gamecontrollerdb.txt` — 1000+ controller mappings; do not attempt to replicate |
| Text input / IME | Raw keyboard → char | `SDL_StartTextInput` + `SDL_EVENT_TEXT_INPUT` | IME handling (CJK, emoji) is extremely platform-specific; SDL3 handles it |

**Key insight:** SDL3 is specifically designed to abstract the exact problems this phase needs to solve. Every item in this table represents years of cross-platform work that ships free with SDL3.

---

## Common Pitfalls

### Pitfall 1: Orhon Union Syntax for Named Variant Payloads

**What goes wrong:** Orhon's union type `(TypeA | TypeB)` is confirmed working. However, the examples only show unions of existing named types like `(Error | i32)` or `(null | i32)`. There is NO confirmed syntax for named payload variants like `KeyDown(KeyDownEvent)` or `WindowResized(i32, i32)`. Attempting `| KeyDown(KeyDownEvent)` syntax may not compile.

**Why it happens:** Orhon is a young language. The tagged union with variant names may not be implemented yet, or may have different syntax.

**How to avoid:** Design the event payload structs first (`KeyDownEvent`, `MouseMotionEvent`, etc. as distinct struct types). Then create the union as `(KeyDownEvent | KeyUpEvent | MouseMotionEvent | ...)`. Dispatch using `if(ev is KeyDownEvent)`. The struct name becomes the discriminator tag — no separate variant name needed.

**Backup design if union-of-structs doesn't work:**
```
// Fallback: typed wrapper struct with discriminator enum
pub enum(u8) EventKind {
    KeyDown
    KeyUp
    MouseMotion
    MouseButton
    GamepadAxis
    GamepadButtonDown
    GamepadButtonUp
    GamepadAdded
    GamepadRemoved
    TextInput
    WindowResized
    WindowClose
    Quit
}

pub struct Event {
    pub kind: EventKind
    pub key: KeyDownEvent        // only valid when kind == KeyDown or KeyUp
    pub mouse_motion: MouseMotionEvent
    pub mouse_button: MouseButtonEvent
    pub gamepad_axis: GamepadAxisEvent
    pub gamepad_button: GamepadButtonEvent
    pub text: String
    pub window_w: i32
    pub window_h: i32
}
```
This is less type-safe but guaranteed to work with confirmed Orhon features. Log the finding in `docs/ideas.txt`.

**Warning signs:** Compiler error on `(KeyDownEvent | KeyUpEvent)` union type declaration, or on `if(ev is KeyDownEvent)` when `ev` is such a union.

### Pitfall 2: SDL_GetWindowSize vs SDL_GetWindowSizeInPixels

**What goes wrong:** `SDL_GetWindowSize` returns logical (point) coordinates. On a macOS Retina display with 2x density, a 1280x800 window has logical size 1280x800 but pixel size 2560x1600. Passing logical size to Vulkan swapchain extent causes rendering at half resolution.

**Why it happens:** SDL3 README-highdpi explicitly documents this split. The Vulkan renderer must use pixel sizes.

**How to avoid:** The resize event in the public Tamga API must carry pixel dimensions (from `SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED` or `SDL_GetWindowSizeInPixels`), not logical dimensions. Document this clearly in the `WindowPixelResized` event payload.

**Warning signs:** Blurry rendering on macOS; Vulkan swapchain creation error on HiDPI displays.

### Pitfall 3: SDL_EVENT_QUIT vs SDL_EVENT_WINDOW_CLOSE_REQUESTED

**What goes wrong:** `SDL_EVENT_QUIT` fires when the application should exit (all windows closed, OS session ending). `SDL_EVENT_WINDOW_CLOSE_REQUESTED` fires when the user clicks the X button on a specific window. The existing bridge only handles `SDL_EVENT_QUIT`. Missing `WINDOW_CLOSE_REQUESTED` means click-X doesn't work unless the app also responds to QUIT.

**Why it happens:** SDL3 made window close a separate event from application quit.

**How to avoid:** Handle both in the bridge's `pollRawEvent`; expose both as union variants. The frame loop's default quit logic should respond to both.

### Pitfall 4: SDL_INIT_GAMEPAD is Required for Gamepad Events

**What goes wrong:** SDL3 gamepad events silently don't fire if `SDL_Init` was called without `SDL_INIT_GAMEPAD`. The current bridge passes `INIT_VIDEO` only (from test code: `tamga_sdl3.init(tamga_sdl3.INIT_VIDEO)`).

**Why it happens:** SDL3 subsystems are opt-in.

**How to avoid:** The platform layer should initialize with `SDL_INIT_VIDEO | SDL_INIT_EVENTS | SDL_INIT_GAMEPAD` (and optionally `SDL_INIT_AUDIO` for when TamgaAudio is initialized). Make this a detail of the platform `init()` call, not something the user has to bitOR together. This is consistent with D-02 (no SDL constants in user code).

### Pitfall 5: Fixed-Timestep Spiral of Death

**What goes wrong:** If `on_update` takes longer than `FIXED_STEP_NS`, the accumulator grows unboundedly, causing progressively more update calls per frame, making things worse — the "spiral of death."

**Why it happens:** The fixed-timestep loop must clamp the frame time.

**How to avoid:** Cap `frame_time` to 250ms (15 frames) before adding to accumulator. This causes time to slow down under heavy load rather than spiral. Documented in the algorithm above.

### Pitfall 6: Text Input Must Be Explicitly Started/Stopped

**What goes wrong:** `SDL_EVENT_TEXT_INPUT` events never arrive even after the bridge is set up, because `SDL_StartTextInput(window)` was never called.

**Why it happens:** SDL3 text input is disabled by default to avoid IME popups when not needed.

**How to avoid:** The `Window` struct (or a standalone platform function) must expose `startTextInput()` / `stopTextInput()` methods. User calls them when activating a text field.

### Pitfall 7: Gamepad Axis Deadzone

**What goes wrong:** Gamepad axes return non-zero values even at rest due to hardware imprecision, causing unintended movement.

**Why it happens:** Physical controllers have small "drift" at rest.

**How to avoid:** This is a caller responsibility, not a framework responsibility — document it in the API. The framework reports raw `-32768..32767` axis values; the game/GUI code applies its own deadzone threshold. Do not silently clamp values in the framework.

---

## Code Examples

Verified patterns from existing codebase and official SDL3 docs:

### Window Creation (existing, confirmed working)
```zig
// Source: src/TamgaSDL3/tamga_sdl3.zig (confirmed working)
const handle = c.SDL_CreateWindow(@ptrCast(&buf), @intCast(w), @intCast(h), flags) orelse {
    return SdlError.SdlFailed;
};
```

### WindowHandle Opaque Cast (existing, confirmed working)
```zig
// Source: src/TamgaVK3D/tamga_vk3d.zig line 700
ctx.sdl_window = @ptrCast(@alignCast(window_handle));
```
This pattern remains valid after the `WindowHandle` rename — `Ptr(u8)` maps to `*anyopaque` in Zig.

### Pixel-Size Window Query (new, SDL3 docs verified)
```zig
// Source: SDL3 wiki — SDL_GetWindowSizeInPixels
pub fn getPixelWidth(self: *const Window) i32 {
    var w: c_int = 0;
    var h: c_int = 0;
    _ = c.SDL_GetWindowSizeInPixels(self.handle, &w, &h);
    return @intCast(w);
}
pub fn getPixelHeight(self: *const Window) i32 {
    var w: c_int = 0;
    var h: c_int = 0;
    _ = c.SDL_GetWindowSizeInPixels(self.handle, &w, &h);
    return @intCast(h);
}
```

### Relative Mouse Mode (new, SDL3 docs verified)
```zig
// Source: SDL3 wiki — SDL_SetWindowRelativeMouseMode
pub fn setRelativeMouseMode(self: *Window, enabled: bool) bool {
    return c.SDL_SetWindowRelativeMouseMode(self.handle, enabled);
}
```

### Text Input Enable/Disable (new, SDL3 docs verified)
```zig
// Source: SDL3 wiki — SDL_StartTextInput
pub fn startTextInput(self: *Window) void {
    _ = c.SDL_StartTextInput(self.handle);
}
pub fn stopTextInput(self: *Window) void {
    _ = c.SDL_StopTextInput(self.handle);
}
```

### Gamepad Event Translation (new, SDL3 docs verified)
```zig
// Source: SDL3 wiki — SDL_GamepadAxisEvent struct
// In the pollRawEvent translator:
c.SDL_EVENT_GAMEPAD_AXIS_MOTION => {
    out.tag = TAG_GAMEPAD_AXIS;
    out.gamepad_which = @intCast(ev.gaxis.which);
    out.gamepad_axis = @intCast(ev.gaxis.axis);
    out.gamepad_axis_value = ev.gaxis.value;  // Sint16 -32768..32767
},
c.SDL_EVENT_GAMEPAD_BUTTON_DOWN => {
    out.tag = TAG_GAMEPAD_BUTTON_DOWN;
    out.gamepad_which = @intCast(ev.gbutton.which);
    out.gamepad_button = @intCast(ev.gbutton.button);
},
```

### Text Input Event Translation (new, SDL3 docs verified)
```zig
// Source: SDL3 wiki — SDL_TextInputEvent (event.text.text is UTF-8)
c.SDL_EVENT_TEXT_INPUT => {
    out.tag = TAG_TEXT_INPUT;
    const src = std.mem.span(ev.text.text[0..]);
    const len = @min(src.len, out.text.len - 1);
    @memcpy(out.text[0..len], src[0..len]);
    out.text[len] = 0;
},
```

### Display Info Query (new, SDL3 docs verified)
```zig
// Source: SDL3 wiki — SDL_GetDisplays, SDL_GetDisplayBounds
pub fn getDisplayCount() i32 {
    var count: c_int = 0;
    const displays = c.SDL_GetDisplays(&count);
    if (displays != null) c.SDL_free(displays);
    return @intCast(count);
}
pub fn getDisplayBounds(display_index: i32, out_x: *i32, out_y: *i32, out_w: *i32, out_h: *i32) bool {
    // SDL_GetDisplays returns 0-terminated array of SDL_DisplayID
    var count: c_int = 0;
    const displays = c.SDL_GetDisplays(&count) orelse return false;
    defer c.SDL_free(displays);
    if (display_index >= count) return false;
    var rect: c.SDL_Rect = undefined;
    const ok = c.SDL_GetDisplayBounds(displays[@intCast(display_index)], &rect);
    if (ok) {
        out_x.* = @intCast(rect.x);
        out_y.* = @intCast(rect.y);
        out_w.* = @intCast(rect.w);
        out_h.* = @intCast(rect.h);
    }
    return ok;
}
```

### Orhon Error Union Pattern (existing, confirmed working)
```
// Source: src/TamgaSDL3/tamga_sdl3.orh + src/test/test_sdl3.orh
pub bridge func create(title: String, w: i32, h: i32, flags: WindowFlags) (Error | Window)
```
```
// Caller:
const result = Window.create("My App", 1280, 720, WindowFlags(Resizable, Vulkan))
if(result is Error) {
    console.println(result.Error)
    return
}
var win = result.value
defer { win.destroy() }
```

### Orhon Bitfield for Window Flags (confirmed working from example code)
```
// Source: src/example/advanced.orh — bitfield pattern confirmed
pub bitfield(u32) WindowFlags {
    Resizable
    Fullscreen
    Borderless
    Vulkan
    HighPixelDensity
}
```
The Zig sidecar maps `WindowFlags` bits to SDL3 `SDL_WINDOW_*` flag constants internally.

---

## State of the Art

| Old Approach (current bridge) | New Approach (Phase 1) | Impact |
|-------------------------------|----------------------|--------|
| `pub bridge const INIT_VIDEO: u32` exposed | `init()` calls the right SDL subsystems internally | User never sees SDL init flags |
| `pub bridge const WINDOW_RESIZABLE: u64` | `pub bitfield WindowFlags` | Type-safe, Tamga-native flags |
| `pub bridge const EVENT_KEY_DOWN: u32` | Removed from public API; internal only | SDL constants no longer exported |
| `event.getType()` + switch on raw u32 | Typed union `(KeyDownEvent | MouseMotionEvent | ...)` | Wrong-accessor-on-wrong-event impossible |
| `window.getHandle() Ptr(u8)` | `window.getHandle() WindowHandle` (named type) | Semantic clarity; downstream sees intent |
| `SDL_GetTicks()` (ms) in frame loop | `SDL_GetTicksNS()` (ns) | Sub-millisecond precision for fixed timestep |
| No gamepad support | Full SDL3 Gamepad API | Completes WIN-06 |
| No text input support | `SDL_StartTextInput` + TEXT_INPUT event | Completes WIN-11 |
| No display info | `SDL_GetDisplays` + query functions | Completes WIN-14 |
| No cursor control | `SDL_SetWindowRelativeMouseMode` | Completes WIN-08 |

**Deprecated/removed in this phase:**
- All `pub bridge const EVENT_*`, `SCANCODE_*`, `MOUSE_*`, `WINDOW_*`, `INIT_*` constants — move to internal bridge, never expose publicly
- `event.getType() u32`, `event.getScancode() u32`, `event.getMouseX() f32`, etc. — replaced by typed union dispatch
- Raw `Ptr(u8)` return from `getHandle()` — replaced by `WindowHandle` type alias

---

## Open Questions

1. **Orhon union-of-structs syntax for named event variants**
   - What we know: `(Error | i32)` and `(null | String)` unions work; `if(x is Error)` dispatch works
   - What's unclear: Can you create `(KeyDownEvent | MouseMotionEvent | GamepadAxisEvent)` as a return type and dispatch on the concrete struct type? Does Orhon support struct-typed union variants or only primitives + named types?
   - Recommendation: Test this first in a small prototype before designing the full event API. If it works, use union-of-structs. If not, fall back to the `EventKind` enum + single `Event` struct with all payload fields.

2. **`type` alias syntax in Orhon**
   - What we know: `pub bridge struct Window` and `pub bridge const INIT_VIDEO: u32` are confirmed
   - What's unclear: Does Orhon support `pub type WindowHandle = Ptr(u8)` as a type alias? Or must `WindowHandle` be a bridge struct wrapping the pointer?
   - Recommendation: If type aliases aren't supported, use a single-field `pub bridge struct WindowHandle { bridge func get(self: const &WindowHandle) Ptr(u8) }` or simply define the concept at the `.zig` level. Either way the important property is that the public `.orh` API declares `WindowHandle` as the return type.

3. **`func` type in Orhon struct fields for callbacks**
   - What we know: `func(i32) i32` function pointer type is confirmed in `data_types.orh`; struct fields exist
   - What's unclear: Can a struct field hold a `func(Event) void` function pointer where `Event` is a complex union type? Any compiler limits on function pointer argument types?
   - Recommendation: Start with the simplest callback form. If complex signatures cause issues, log in `docs/bugs.txt` and simplify the callback type.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| SDL3 system library | All windowing/input | Assumed (existing code compiles) | 3.x | None — required |
| Zig | Orhon bridge compilation | Assumed (per CLAUDE.md) | 0.15.x | None — required |
| Orhon compiler | Build | Per PATH (not found in research env) | current | — |
| Vulkan SDK (for validation layers) | TamgaVK3D (Phase 2, not this phase) | Not checked | — | — |

Note: The research environment does not have `orhon` in PATH, but CLAUDE.md states the compiler is available in the developer's PATH. All environment checks skipped — the developer's machine is the execution environment.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Orhon built-in `test` blocks + `assert()` |
| Config file | None — `orhon test` discovers all `test { }` blocks automatically |
| Quick run command | `orhon test` |
| Full suite command | `orhon test` (same — runs all test blocks in all modules) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| WIN-01 | Window creates with Tamga-native flags, returns `WindowHandle` | Integration (manual visual) | `orhon test` (smoke) | ❌ Wave 0: update `src/test/test_sdl3.orh` |
| WIN-02 | Resize event delivers pixel dimensions | Integration (manual resize) | `orhon test` | ❌ Wave 0: add resize test case |
| WIN-03 | Close event triggers clean shutdown, no crash | Integration (manual close) | `orhon test` | ❌ Wave 0: add close test case |
| WIN-04 | KeyDown/KeyUp events carry `Scancode` enum value | Integration (manual key) | `orhon test` | ❌ Wave 0: update test_sdl3.orh |
| WIN-05 | MouseMotion and MouseButton events carry typed payloads | Integration (manual mouse) | `orhon test` | ❌ Wave 0: update test_sdl3.orh |
| WIN-06 | Gamepad events fire when controller connected/used | Integration (manual gamepad) | `orhon test` | ❌ Wave 0: add gamepad test |
| WIN-07 | Event loop runs; delta time is f64 seconds | Unit (automated timing check) | `orhon test` | ❌ Wave 0: add timing unit test |
| WIN-08 | Cursor hides/locks, mouse motion still fires | Integration (manual) | `orhon test` | ❌ Wave 0: add cursor test |
| WIN-09 | Resize event pixel dims != logical dims on HiDPI | Integration (HiDPI machine) | `orhon test` | ❌ Wave 0: add pixel size bridge func test |
| WIN-10 | Init failure returns `Error`, not crash | Unit | `orhon test` | ❌ Wave 0: add error case test |
| WIN-11 | Text input events fire after `startTextInput()` | Integration (manual typing) | `orhon test` | ❌ Wave 0: add text input test |
| WIN-12 | No `SDL_*` symbol in `tamga_sdl3.orh` public declarations | Static (code review) | manual | ❌ Wave 0: verify by inspection |
| WIN-13 | `Renderer.create` accepts `WindowHandle`, builds successfully | Compilation | `orhon build` | ❌ Wave 0: update test_vulkan.orh signature |
| WIN-14 | Display info query returns at least 1 display with valid bounds | Unit | `orhon test` | ❌ Wave 0: add display test |
| XC-01 | User code needs no imports beyond `tamga_sdl3` | Code review | manual | — |
| XC-02 | `tamga_sdl3` compiles as standalone library (no other tamga deps) | Compilation | `orhon build` | — |
| XC-03 | No `@cImport` or C types in `.orh` files | Static code review | manual grep | — |
| XC-04 | Build succeeds on Linux (primary); Windows/macOS noted | Compilation | `orhon build` | — |
| XC-05 | Bugs logged in `docs/bugs.txt` | Process | manual | ✅ exists |
| XC-06 | No workarounds in code | Code review | manual | — |
| LOOP-01 | Frame loop runs update at fixed rate, render at variable rate | Integration (run + observe) | `orhon test` | ❌ Wave 0: add loop test |
| LOOP-02 | Delta time accessible in callbacks as f64 seconds | Unit | `orhon test` | ❌ Wave 0: add dt test |
| LOOP-03 | `loop.destroy()` cleans up without crash | Unit | `orhon test` | ❌ Wave 0: add lifecycle test |

### Sampling Rate
- **Per task commit:** `orhon build` (compilation gate)
- **Per wave merge:** `orhon test` (all test blocks)
- **Phase gate:** All test blocks green + manual integration walkthrough (open window, handle all event types, run loop 5 seconds, clean quit) before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `src/test/test_sdl3.orh` — update to use new typed event API, add WIN-01 through WIN-11 coverage
- [ ] `src/test/test_platform_loop.orh` — LOOP-01/02/03 coverage (new file, `module main`)
- [ ] `src/test/test_display.orh` — WIN-14 display info query test (new file, `module main`)
- [ ] `src/test/test_vulkan.orh` — update `Renderer.create` call to use `WindowHandle` type (WIN-13)

---

## Sources

### Primary (HIGH confidence)
- `/home/yunus/Projects/orhon/tamga_framework/src/TamgaSDL3/tamga_sdl3.zig` — confirmed working SDL3 bridge patterns
- `/home/yunus/Projects/orhon/tamga_framework/src/TamgaSDL3/tamga_sdl3.orh` — confirmed public API structure
- `/home/yunus/Projects/orhon/tamga_framework/src/TamgaVK3D/tamga_vk3d.zig` — confirmed `WindowHandle` cast pattern
- `/home/yunus/Projects/orhon/tamga_framework/src/example/*.orh` — confirmed Orhon language features: union types, bitfield, enum, struct, function pointers, match, error handling
- `/home/yunus/Projects/orhon/tamga_framework/docs/bugs.txt` — confirmed `#linkC` works, duplicate import bug fixed in v0.8.2
- [SDL3 README-highdpi](https://wiki.libsdl.org/SDL3/README-highdpi) — HiDPI pixel vs logical size distinction
- [SDL_GetWindowSizeInPixels](https://wiki.libsdl.org/SDL3/SDL_GetWindowSizeInPixels) — pixel dimension API
- [SDL_EVENT_WINDOW_RESIZED](https://wiki.libsdl.org/SDL3/SDL_EVENT_WINDOW_RESIZED) — resize event data fields
- [SDL_StartTextInput](https://wiki.libsdl.org/SDL3/SDL_StartTextInput) — text input enable/disable
- [SDL_TextInputEvent](https://wiki.libsdl.org/SDL3/SDL_TextInputEvent) — text event structure
- [SDL_SetWindowRelativeMouseMode](https://wiki.libsdl.org/SDL3/SDL_SetWindowRelativeMouseMode) — cursor lock API
- [SDL_GamepadAxisEvent](https://wiki.libsdl.org/SDL3/SDL_GamepadAxisEvent) — gamepad axis struct
- [SDL_GetDisplays](https://wiki.libsdl.org/SDL3/SDL_GetDisplays) — display enumeration
- [SDL_GetDisplayBounds](https://wiki.libsdl.org/SDL3/SDL_GetDisplayBounds) — display geometry
- [SDL_GetDisplayContentScale](https://wiki.libsdl.org/SDL3/SDL_GetDisplayContentScale) — DPI scale

### Secondary (MEDIUM confidence)
- [SDL3 Gamepad API overview](https://wiki.libsdl.org/SDL3/CategoryGamepad) — gamepad event family
- [SDL3 window events summary](https://deepwiki.com/libsdl-org/SDL/2.2-event-processing-and-window-events) — verified against SDL source header
- [SDL_GamepadAxisEvent openSUSE manpage](https://manpages.opensuse.org/Tumbleweed/SDL3-devel-doc/SDL_GamepadAxisEvent.3type.en.html) — confirmed struct fields

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — working codebase; SDL3 functions verified via official wiki
- Architecture: HIGH — two-layer bridge confirmed by existing VK3D pattern; union type dispatch confirmed by example code
- Event API design: MEDIUM — the union-of-structs approach is architecturally sound but Orhon union syntax limits are an open question (see Open Questions)
- Pitfalls: HIGH — all documented pitfalls verified via official SDL3 docs or observed in existing codebase
- Frame loop algorithm: HIGH — standard game loop algorithm; SDL_GetTicksNS verified in SDL3 docs

**Research date:** 2026-03-25
**Valid until:** 2026-06-25 (SDL3 stable; Orhon compiler changes more frequently — re-verify union syntax question before implementation)
