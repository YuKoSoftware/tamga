---
phase: 01-platform-foundation
plan: 02
subsystem: tamga_sdl3
tags: [sdl3, orhon-api, events, window, bitfield, enum, bridge, zig-bridge]

requires:
  - phase: 01-platform-foundation plan 01
    provides: tamga_sdl3.zig complete SDL3 translation bridge with RawEvent, Window, gamepad, display, timing functions

provides:
  - Complete Tamga-native public API for SDL3 platform layer in tamga_sdl3.orh
  - WindowHandle opaque struct type (workaround for missing type alias support)
  - WindowFlags bitfield(u64) for type-safe window creation flags
  - Scancode enum with sequential indices (SDL3 translation in Zig sidecar)
  - EventKind discriminator enum + Event struct for all 14 event types
  - Typed payload structs for all event types (keyboard, mouse, gamepad, text, window)
  - pollEvent() returning (null | Event) — zero SDL3 leakage in public API
  - initPlatform() returning (Error | bool) — error union per D-12/WIN-10
  - Window bridge struct with getHandle() → WindowHandle, getPixelWidth/Height, getDisplayScale
  - DisplayInfo struct + getDisplayInfo() replacing mutable out-pointer pattern
  - RawEvent bridge struct with 20 getter methods for Zig sidecar field access
  - SDL scancode translation table in tamga_sdl3.zig (SDL3 integers → sequential Orhon indices)
  - MouseButton translation in tamga_sdl3.zig (SDL 1/2/3 → Orhon 0/1/2)
  - Compiler bugs documented in docs/bugs.txt (4 new open issues)

affects:
  - src/TamgaVK3D/tamga_vk3d.orh (consumes Window.getHandle() → Ptr(u8) via .handle field)
  - src/test/test_sdl3.orh (updated to new event API)
  - src/test/test_vulkan.orh (updated to new event API)
  - Phase 02 (VK3D) — downstream renderer uses WindowHandle from this module
  - Phase 03 (Audio) — imports tamga_sdl3 for timing (getTicksNS, delayNS)

tech-stack:
  added: []
  patterns:
    - "EventKind enum + Event struct fallback for type-safe event dispatch (union-of-structs blocked by compiler bug)"
    - "SDL3 scancode → Orhon sequential index translation table in Zig sidecar"
    - "Struct-based opaque handle (WindowHandle) as workaround for missing type alias support"
    - "DisplayInfo return struct replacing mutable out-pointer bridge parameters"
    - "RawEvent getter methods on Zig struct matching bridge struct declarations in .orh"

key-files:
  created: []
  modified:
    - src/TamgaSDL3/tamga_sdl3.orh
    - src/TamgaSDL3/tamga_sdl3.zig
    - src/test/test_sdl3.orh
    - src/test/test_vulkan.orh

key-decisions:
  - "EventKind enum + flat Event struct used instead of union-of-structs: `is` operator fails on cross-module types (codegen bug)"
  - "Scancode enum uses sequential values 0..64 — SDL3 integer translation lives in tamga_sdl3.zig (sdlScancodeToOrhon)"
  - "MouseButton enum uses sequential 0=Left/1=Middle/2=Right — SDL3 1/2/3 translated in pollRawEvent"
  - "WindowHandle is a struct with pub handle: Ptr(u8) — type alias syntax not yet supported by compiler"
  - "initPlatform() returns (Error | bool) not (Error | Unit) — Unit type not recognized as bridge return type"
  - "getDisplayBounds replaced by getDisplayInfo() returning DisplayInfo struct — mutable &i32 params violate bridge safety"
  - "tamga_vk3d.orh keeps Ptr(u8) for Renderer.create — cross-module type refs in bridge signatures not yet supported"

requirements-completed: [WIN-01, WIN-02, WIN-03, WIN-04, WIN-05, WIN-06, WIN-07, WIN-08, WIN-09, WIN-10, WIN-11, WIN-12, WIN-13, WIN-14, XC-01, XC-02, XC-03, XC-04]

duration: 23min
completed: "2026-03-25"
---

# Phase 01 Plan 02: Tamga-Native SDL3 Public API Summary

**Complete tamga_sdl3.orh rewrite exposing only Tamga-native types — WindowHandle struct, WindowFlags bitfield, EventKind+Event dispatch, typed payload structs, error-union init — zero SDL3 leakage**

## Performance

- **Duration:** 23 min
- **Started:** 2026-03-25T19:26:52Z
- **Completed:** 2026-03-25T19:49:28Z
- **Tasks:** 1 of 1
- **Files modified:** 4

## Accomplishments

- Rewrote `tamga_sdl3.orh` from a thin constant-exporting bridge into a complete Tamga-native public API with zero SDL3 symbol leakage
- Designed and implemented EventKind enum + Event struct pattern for type-safe event dispatch across all 14 event categories
- Added RawEvent getter methods to `tamga_sdl3.zig` (20 accessors) enabling bridge struct field access from Orhon
- Discovered and documented 4 Orhon compiler limitations in `docs/bugs.txt`: type alias syntax, enum explicit values, Unit type in bridge, `is` operator cross-module

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite tamga_sdl3.orh — Tamga-native public API with typed events** - `254cfbd` (feat)

## Files Created/Modified

- `src/TamgaSDL3/tamga_sdl3.orh` - Complete rewrite: WindowHandle, WindowFlags, Scancode, MouseButton, EventKind, Event, typed payload structs, RawEvent bridge, Window bridge, all lifecycle/cursor/gamepad/display/timing functions
- `src/TamgaSDL3/tamga_sdl3.zig` - Added: SDL3 scancode translation table + sdlScancodeToOrhon(), MouseButton translation, RawEvent getter methods (create/poll/getTag/.../getTimestamp), DisplayInfo struct + getDisplayInfo(), WindowHandle struct, initPlatform() returns bool on success, getError() renamed from getErrorMessage()
- `src/test/test_sdl3.orh` - Updated to new API: initPlatform/quitPlatform, pollEvent with EventKind dispatch, delayNS
- `src/test/test_vulkan.orh` - Updated to new API: same pattern, plus win.getHandle().handle for Renderer.create

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| EventKind enum + flat Event struct | union-of-structs `is` dispatch broken for cross-module types — parser rejects `module.Type` after `is`, codegen fails on unqualified cross-module type names |
| Scancode sequential indices | Compiler rejects explicit enum values (`A = 4`). Translation happens in Zig sidecar, preserving correctness |
| MouseButton sequential (0/1/2) | Same limitation. SDL3 1/2/3 → 0/1/2 translation in pollRawEvent |
| WindowHandle as struct | `pub type Alias = T` syntax not supported — struct wrapper provides the named type requirement |
| initPlatform returns (Error | bool) | `Unit` type not recognized in bridge return position — `bool` with `true` on success satisfies D-12/WIN-10 error union requirement |
| getDisplayInfo() returns DisplayInfo | `&i32` mutable refs violate bridge safety rule — struct return cleanly avoids all out-pointer params |
| tamga_vk3d keeps Ptr(u8) | Cross-module type reference in bridge func signature (`tamga_sdl3.WindowHandle`) not yet supported |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] EventKind enum fallback for union-of-structs dispatch**
- **Found during:** Task 1 (pollEvent implementation)
- **Issue:** `is` operator with cross-module types fails: parser rejects `module.Type` after `is`; codegen fails on unqualified cross-module struct names
- **Fix:** Implemented RESEARCH.md Pitfall 1 fallback design (EventKind enum + Event struct). All typed payload structs retained as public API. All original structs still useful
- **Files modified:** `src/TamgaSDL3/tamga_sdl3.orh`, `src/test/test_sdl3.orh`, `src/test/test_vulkan.orh`
- **Committed in:** 254cfbd

**2. [Rule 3 - Blocking] Scancode sequential translation (enum values not supported)**
- **Found during:** Task 1 (Scancode enum definition)
- **Issue:** Compiler rejects `A = 4` inside enum body — explicit integer assignments not supported
- **Fix:** Sequential enum values (0..64) with SDL3 scancode → Orhon index translation table in `tamga_sdl3.zig`
- **Files modified:** `src/TamgaSDL3/tamga_sdl3.orh`, `src/TamgaSDL3/tamga_sdl3.zig`
- **Committed in:** 254cfbd

**3. [Rule 3 - Blocking] WindowHandle as struct (type alias not supported)**
- **Found during:** Task 1 (WindowHandle definition)
- **Issue:** `pub type WindowHandle = Ptr(u8)` rejected with "unexpected 'type'"
- **Fix:** `pub struct WindowHandle { pub handle: Ptr(u8) }` — struct wrapper, inner field is the opaque pointer
- **Files modified:** `src/TamgaSDL3/tamga_sdl3.orh`, `src/TamgaSDL3/tamga_sdl3.zig`
- **Committed in:** 254cfbd

**4. [Rule 2 - Missing Critical] initPlatform uses (Error | bool) not (Error | Unit)**
- **Found during:** Task 1 (lifecycle function declaration)
- **Issue:** `Unit` type not recognized in bridge return position
- **Fix:** Changed to `(Error | bool)` with Zig sidecar returning `true` on success — D-12/WIN-10 error union requirement still satisfied
- **Files modified:** `src/TamgaSDL3/tamga_sdl3.orh`, `src/TamgaSDL3/tamga_sdl3.zig`
- **Committed in:** 254cfbd

**5. [Rule 2 - Missing Critical] getDisplayBounds replaced by getDisplayInfo()**
- **Found during:** Task 1 (display info function declaration)
- **Issue:** `getDisplayBounds(index, &i32, &i32, &i32, &i32)` violates bridge safety rule: mutable `&T` not allowed across bridge
- **Fix:** `getDisplayInfo(index: i32) DisplayInfo` returns a struct with x/y/width/height/scale
- **Files modified:** `src/TamgaSDL3/tamga_sdl3.orh`, `src/TamgaSDL3/tamga_sdl3.zig`
- **Committed in:** 254cfbd

---

**Total deviations:** 5 auto-fixed (3 blocking compiler limitations, 2 missing critical)
**Impact on plan:** All fixes required by compiler limitations or bridge safety rules. No scope creep. All plan objectives met with equivalent functionality.

## Issues Encountered

- Orhon compiler cache not automatically invalidated when sidecar `.zig` files change — required manual cache deletion (`rm -rf .orh-cache`) to pick up Zig changes
- SDL3 `SDL_Scancode` is `c_uint`, not `c_int` — `sdlScancodeToOrhon` signature required `c_uint` parameter type
- Compiler error output is suppressed when stdout is not a TTY — build errors only visible in interactive terminal sessions

## Known Stubs

None — all functions are fully implemented. EventKind dispatch API is complete and functional. The EventKind enum + Event struct is a full implementation, not a stub.

## Compiler Bugs Logged

The following Orhon compiler limitations were encountered and documented in `docs/bugs.txt`:

1. **`pub type Alias = T` not supported** — type alias declarations rejected by parser
2. **Enum explicit integer values not supported** — `Variant = N` syntax rejected in typed enum bodies
3. **`Unit` type not recognized in bridge return** — cannot express "error or nothing" without bool workaround
4. **`is` operator cross-module type dispatch broken** — parser rejects `module.Type` after `is`; codegen fails on unqualified cross-module struct names

## Next Phase Readiness

- Platform layer public API complete: zero SDL3 leakage above tamga_sdl3 module boundary
- All downstream modules must import tamga_sdl3 for window and event handling
- tamga_vk3d currently uses `Ptr(u8)` for window handle (not WindowHandle struct) — will need update when cross-module bridge types are supported
- EventKind dispatch is ergonomic; compiler-first workflow should address `is` operator limitations

---
*Phase: 01-platform-foundation*
*Completed: 2026-03-25*
