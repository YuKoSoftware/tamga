---
phase: quick
plan: 260326-h4x
subsystem: tamga_sdl3
tags: [cleanup, compiler-bugs, event-system, api, sdl3]
dependency_graph:
  requires: []
  provides: [clean-event-dispatch, type-alias-windowhandle, explicit-scancodes, void-bridge-return]
  affects: [tamga_sdl3, tamga_vk3d, tamga_loop, test_sdl3, test_vulkan]
tech_stack:
  added: []
  patterns:
    - "Union-of-structs event dispatch via is operator (cross-module)"
    - "pub const Alias: type = T for type aliases"
    - "(Error | void) for void-returning bridge functions"
    - "NoEvent sentinel struct for event polling (workaround for null|MultiUnion codegen bug)"
key_files:
  created: []
  modified:
    - src/TamgaSDL3/tamga_sdl3.orh
    - src/TamgaSDL3/tamga_sdl3.zig
    - src/TamgaSDL3/tamga_loop.orh
    - src/TamgaVK3D/tamga_vk3d.zig
    - src/test/test_sdl3.orh
    - src/test/test_vulkan.orh
    - docs/bugs.txt (gitignored, local only)
decisions:
  - "Use NoEvent sentinel struct (not null) for empty event queue — (null|MultiUnion) codegen is broken"
  - "Keep scancode/button fields as u32/u8 — cast(Enum, int) generates @intCast not @enumFromInt"
  - "Event type alias uses pub const Alias: type = T syntax (not pub type Alias = T)"
  - "initPlatform return type is (Error | void) not (Error | Unit)"
metrics:
  duration: "~45 minutes"
  completed: "2026-03-26"
  tasks_completed: 2
  files_modified: 6
---

# Quick Task 260326-h4x Summary

Remove all 4 compiler bug workarounds from Phase 1 code now that the Orhon compiler has fixed the underlying issues.

**One-liner:** Removed 140-line scancode translation table + EventKind flat-struct dispatch, replaced with explicit enum values, union-of-structs is dispatch, type alias WindowHandle, and void bridge return.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Remove enum and type alias workarounds | b3a10e9 | tamga_sdl3.orh, tamga_sdl3.zig |
| 2 | Update downstream consumers and docs | e94e065 | tamga_vk3d.zig, tamga_loop.orh, test_sdl3.orh, test_vulkan.orh |

## What Changed

### Workaround 1 — Enum explicit values (FIXED)
- `Scancode` enum now uses real SDL3 integer values (`A = 4, Escape = 41, ...`)
- `MouseButton` enum uses SDL3 values (`Left = 1, Middle = 2, Right = 3`)
- Entire 140-line scancode translation table removed from tamga_sdl3.zig
- Mouse button offset arithmetic removed from pollRawEvent
- SDL3 scancodes pass through directly via `@intCast(ev.key.scancode)`

### Workaround 2 — union-of-structs is dispatch (FIXED)
- `EventKind` enum deleted (16 variants)
- `Event` flat struct deleted (11 fields, only one valid per event)
- New: `Event` type alias for 14-member arbitrary union
- `pollEvent()` constructs union variants directly — no zero-filling unused fields
- All event dispatch in tests/loop uses `ev is tamga_sdl3.KeyDownEvent` pattern
- Cross-module qualified `is` works: `ev is tamga_sdl3.QuitEvent`

### Workaround 3 — Unit type (FIXED)
- `initPlatform()` returns `(Error | void)` — correct void bridge semantics
- Zig sidecar returns `void` (no `return true`)
- Callers: `if(initResult is Error)` check still works as before

### Workaround 4 — Type alias (FIXED)
- `WindowHandle` is now `pub const WindowHandle: type = Ptr(u8)`
- Zig sidecar: `pub const WindowHandle = *anyopaque`
- `Window.getHandle()` returns `@ptrCast(self.handle)` directly
- `tamga_vk3d.zig` no longer accesses `.handle` field — uses pointer directly

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing] pub type syntax differs from plan**
- **Found during:** Task 1
- **Issue:** Plan specified `pub type WindowHandle = Ptr(u8)` but compiler uses `pub const WindowHandle: type = Ptr(u8)` (phase 18 implemented the latter syntax)
- **Fix:** Used `pub const` syntax as actually implemented
- **Files modified:** tamga_sdl3.orh

**2. [Rule 2 - Missing] Unit vs void**
- **Found during:** Task 1
- **Issue:** Plan specified `(Error | Unit)` but compiler fix used `void` as the non-error member
- **Fix:** Used `(Error | void)` as actually implemented in compiler phase 17
- **Files modified:** tamga_sdl3.orh, tamga_sdl3.zig

**3. [Rule 1 - Bug] (null | MultiUnion) codegen collapses to ?FirstType**
- **Found during:** Task 1
- **Issue:** `(null | QuitEvent | KeyDownEvent | ...)` generates `?QuitEvent` not a full union — typeToZig returns only the first non-null type
- **Fix:** Used `NoEvent` sentinel struct as first member of the arbitrary union. `pollEvent()` returns `(NoEvent | QuitEvent | ...)`. Callers: `if(ev is not tamga_sdl3.NoEvent)`
- **Files modified:** tamga_sdl3.orh
- **Logged as new bug:** docs/bugs.txt "OPEN: (null | MultiUnion) return type collapses to ?FirstType"

**4. [Rule 1 - Bug] cast(EnumType, int) generates @intCast not @enumFromInt**
- **Found during:** Task 1
- **Issue:** `cast(Scancode, raw.getKeyScancode())` generates `@as(Scancode, @intCast(...))` which Zig rejects — `@enumFromInt` is required for int-to-enum conversion
- **Fix:** Kept `scancode` and `button` fields as `u32`/`u8`. The Scancode/MouseButton enums still exist for comparison but the event struct fields use raw integers.
- **Files modified:** tamga_sdl3.orh
- **Logged as new bug:** docs/bugs.txt "OPEN: cast(EnumType, int) generates @intCast instead of @enumFromInt"

**5. [Rule 1 - Bug] Empty struct construction NoEvent() generates invalid Zig**
- **Found during:** Task 1
- **Issue:** `return NoEvent()` (empty struct) generates `NoEvent()` in Zig which is invalid — empty struct init in Zig is `NoEvent{}` not `NoEvent()`
- **Fix:** Added `pub empty: bool` dummy field to NoEvent, construct as `NoEvent(empty: false)`
- **Files modified:** tamga_sdl3.orh
- **Logged as new bug:** docs/bugs.txt "OPEN: Empty struct construction NoEvent() generates invalid Zig"

## Known Stubs

None — all functionality is fully wired. The `NoEvent.empty` field is a workaround for a compiler bug (empty struct construction), not a stub.

## Verification Results

- `orhon build` — PASS
- `orhon test` — PASS (all tests)
- No `EventKind` references in src/
- No `sdlScancodeToOrhon` in src/
- No `(Error | bool)` for initPlatform in src/
- No `pub struct WindowHandle { pub handle` in src/
- 4 original OPEN bugs marked FIXED in docs/bugs.txt
- 3 new compiler bugs documented in docs/bugs.txt

## Self-Check: PASSED

Commits verified:
- b3a10e9 — present in git log
- e94e065 — present in git log

Key files exist:
- src/TamgaSDL3/tamga_sdl3.orh — modified
- src/TamgaSDL3/tamga_sdl3.zig — modified
- src/TamgaVK3D/tamga_vk3d.zig — modified
