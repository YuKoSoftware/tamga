---
phase: 01-platform-foundation
plan: 03
subsystem: tamga_sdl3, tamga_vk3d
tags: [frame-loop, game-loop, fixed-timestep, event-loop, window-handle, integration-tests, bridge]

requires:
  - phase: 01-platform-foundation plan 02
    provides: Complete tamga_sdl3 public API with WindowHandle, EventKind+Event dispatch, initPlatform error union

provides:
  - Fixed-timestep frame loop (tamga_loop.orh) in tamga_sdl3 module
  - LoopConfig struct with on_event(Event)/on_update(f64)/on_render(f64) callbacks
  - Loop struct with create/run/stop/destroy lifecycle
  - tamga_vk3d.orh updated to accept tamga_sdl3.WindowHandle in Renderer.create (D-08, WIN-13)
  - tamga_vk3d.zig sidecar updated to extract .handle from WindowHandle struct
  - test_sdl3.orh: integration test exercising typed event API and error-union init
  - test_vulkan.orh: integration test passing WindowHandle to Renderer.create directly

affects:
  - src/TamgaSDL3/tamga_loop.orh (new file)
  - src/TamgaVK3D/tamga_vk3d.orh (Renderer.create signature updated)
  - src/TamgaVK3D/tamga_vk3d.zig (create() function updated)
  - src/test/test_sdl3.orh (rewritten with typed API)
  - src/test/test_vulkan.orh (rewritten with WindowHandle flow)
  - Phase 02 (VK3D full renderer) — inherits the WindowHandle bridge pattern

tech-stack:
  added: []
  patterns:
    - "Fixed-timestep game loop with 250ms spiral-of-death clamp and interpolation alpha"
    - "Function pointer fields in Orhon struct for frame loop callbacks (func(T) void)"
    - "Cross-module type reference in bridge signature: tamga_sdl3.WindowHandle in tamga_vk3d.orh"
    - "Zig sidecar imports tamga_sdl3_bridge.zig for WindowHandle type identity (not tamga_sdl3.zig)"
    - "D-08 complete: VK3D caller passes win.getHandle() — no .handle field access needed"

key-files:
  created:
    - src/TamgaSDL3/tamga_loop.orh
  modified:
    - src/TamgaVK3D/tamga_vk3d.orh
    - src/TamgaVK3D/tamga_vk3d.zig
    - src/test/test_sdl3.orh
    - src/test/test_vulkan.orh

key-decisions:
  - "cross-module bridge type refs work when import is present: tamga_sdl3.WindowHandle in bridge sig compiles with import tamga_sdl3 at top"
  - "VK3D Zig sidecar must import tamga_sdl3_bridge.zig (not tamga_sdl3.zig) for WindowHandle type identity — Orhon generates values from bridge types"
  - "250ms frame-time clamp chosen as spiral-of-death threshold (RESEARCH.md recommendation)"
  - "LoopConfig.on_event takes Event (not a union type) due to existing EventKind+Event struct design from Plan 02"

requirements-completed: [LOOP-01, LOOP-02, LOOP-03, WIN-13, XC-01, XC-02, XC-05, XC-06]

duration: 6min
completed: "2026-03-25"
---

# Phase 01 Plan 03: Frame Loop, VK3D WindowHandle, Integration Tests Summary

**Fixed-timestep frame loop in tamga_sdl3 module + VK3D updated to accept tamga_sdl3.WindowHandle directly + integration tests exercising the complete platform API with error-union init**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-25T19:53:41Z
- **Completed:** 2026-03-25T19:59:35Z
- **Tasks:** 2 of 2
- **Files modified:** 5 (1 created, 4 updated)

## Accomplishments

- Implemented `tamga_loop.orh` — a fixed-timestep frame loop with configurable Hz, spiral-of-death prevention, and callback system for event/update/render
- Updated `tamga_vk3d.orh` to import `tamga_sdl3` and use `tamga_sdl3.WindowHandle` in `Renderer.create` — D-08 fully realized
- Discovered and fixed: the VK3D Zig sidecar must import `tamga_sdl3_bridge.zig` (not the generated `tamga_sdl3.zig`) to match the type identity that Orhon codegen produces for `WindowHandle`
- Rewrote both integration tests to use the new typed event API, error-union init dispatch, and direct `win.getHandle()` pass to `Renderer.create`

## Task Commits

Each task was committed atomically:

1. **Task 1: Create frame loop module (tamga_loop.orh)** — `434674e` (feat)
2. **Task 2: Update VK3D WindowHandle and rewrite integration tests** — `d46498b` (feat)

## Files Created/Modified

- `src/TamgaSDL3/tamga_loop.orh` — New: LoopConfig struct, Loop struct with fixed-timestep run(), stop(), destroy(), 250ms clamp, interpolation alpha
- `src/TamgaVK3D/tamga_vk3d.orh` — Updated: added `import tamga_sdl3`, changed Renderer.create param to `tamga_sdl3.WindowHandle`
- `src/TamgaVK3D/tamga_vk3d.zig` — Updated: create() accepts `@import("tamga_sdl3_bridge.zig").WindowHandle`, extracts `.handle` internally
- `src/test/test_sdl3.orh` — Rewritten: typed event API, getHandle(), pixel dims, display count, EventKind dispatch, error-union init
- `src/test/test_vulkan.orh` — Rewritten: pass `win.getHandle()` to `Renderer.create`, error-union init, typed event dispatch

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| LoopConfig.on_event takes Event struct | Event API from Plan 02 uses EventKind+Event (not union-of-structs) — loop must match existing design |
| 250ms spiral-of-death clamp | RESEARCH.md Pattern 3 recommendation — prevents runaway accumulation on slow frames |
| VK3D sidecar imports tamga_sdl3_bridge.zig | Orhon codegen produces bridge types (not generated types) — sidecar must use same type for identity match |
| Cross-module bridge type refs work with import | Discovered: `tamga_sdl3.WindowHandle` in bridge sig compiles when `import tamga_sdl3` present — Plan 02 may have been blocked by missing import |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] VK3D Zig sidecar WindowHandle type identity mismatch**
- **Found during:** Task 2 (build test of WindowHandle bridge param)
- **Issue:** `@import("tamga_sdl3.zig").WindowHandle` produces a different type identity than the `WindowHandle` Orhon codegen passes (which comes from `tamga_sdl3_bridge.zig`). First attempt used `tamga_sdl3.zig` import — Zig compiler rejected it with type mismatch
- **Fix:** Changed import to `@import("tamga_sdl3_bridge.zig").WindowHandle` — matches the type produced by Orhon codegen
- **Files modified:** `src/TamgaVK3D/tamga_vk3d.zig`
- **Committed in:** d46498b

**2. [Rule 3 - Blocking] Cache invalidation required after Zig sidecar change**
- **Found during:** Task 2 (initial build after sidecar update)
- **Issue:** Orhon compiler does not automatically invalidate cache when `.zig` sidecar files change — build succeeded with OLD bridge code
- **Fix:** Cleared `.orh-cache/` manually before rebuild (consistent with existing known issue in docs from Plan 01)
- **Files modified:** none (cache management)
- **Committed in:** d46498b (implicitly — build succeeds after cache clear)

## Issues Encountered

- Cache invalidation remains a recurring issue: Zig sidecar changes require `rm -rf .orh-cache` — this was already documented in Plan 01 SUMMARY
- The `tamga_sdl3.WindowHandle` cross-module bridge type now works (Plan 02 documented it as not working). Likely the missing `import tamga_sdl3` was the blocker in Plan 02, not a fundamental compiler limitation

## Known Stubs

None — all functions fully implemented. The frame loop is a working implementation, not a stub.

## Self-Check: PASSED

All created/modified files confirmed on disk. All task commits confirmed in git history:
- `434674e` — feat(01-03): implement fixed-timestep frame loop (tamga_loop.orh)
- `d46498b` — feat(01-03): update VK3D WindowHandle and rewrite integration tests
