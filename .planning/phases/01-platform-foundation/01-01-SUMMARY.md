---
phase: 01-platform-foundation
plan: 01
subsystem: tamga_sdl3
tags: [sdl3, zig-bridge, events, input, gamepad, hidpi, timing]
dependency_graph:
  requires: []
  provides: [tamga_sdl3.zig complete bridge layer]
  affects: [src/TamgaSDL3/tamga_sdl3.orh (plan 02), src/TamgaVK3D/tamga_vk3d.zig (Window.getHandle unchanged)]
tech_stack:
  added: []
  patterns: [RawEvent discriminated struct, SDL3 -> primitive translation layer, error union init]
key_files:
  created: []
  modified:
    - src/TamgaSDL3/tamga_sdl3.zig
decisions:
  - "initPlatform always inits VIDEO | EVENTS | GAMEPAD together — GAMEPAD cannot be added post-init"
  - "RawEvent uses u8 tag constants (not Zig enum) so Orhon bridge can read as plain integer"
  - "getPixelWidth/getPixelHeight use SDL_GetWindowSizeInPixels — separate from logical size for HiDPI correctness"
  - "cursor hide/show are module-level functions, not Window methods (matches SDL3 API design)"
  - "openGamepad returns ?*anyopaque — null on failure, avoids error union for non-critical resource"
metrics:
  duration: 2m
  completed_date: "2026-03-25T19:23:34Z"
  tasks_completed: 1
  tasks_total: 1
  files_changed: 1
---

# Phase 01 Plan 01: Rewrite tamga_sdl3.zig — Complete SDL3 Zig Bridge Summary

**One-liner:** Complete rewrite of tamga_sdl3.zig from a thin constant-exporting bridge into a proper SDL3 C-to-primitive translation layer with RawEvent translator, HiDPI queries, gamepad/text-input/cursor/display APIs, and error-union lifecycle.

## What Was Built

The `tamga_sdl3.zig` sidecar file was completely rewritten. It is now the single point where SDL3 C types are consumed and translated into primitive Zig types that can cross the Orhon bridge boundary without leaking SDL3 internals.

### Key Components

**RawEvent translator** — A flat `RawEvent` struct with a `u8` tag discriminator (16 TAG_ constants: TAG_NONE=0 through TAG_WINDOW_CLOSE=15). `pollRawEvent(out: *RawEvent) bool` handles the full SDL3 event union: keyboard, mouse motion/buttons, all gamepad events (axis/button/added/removed), text input, window resize (both logical and pixel), pixel-size-changed (HiDPI), window close, and quit. All fields are primitive types — no `c.SDL_*` types in any output.

**Window struct** — Kept the existing `create`/`destroy`/`setTitle`/`getWidth`/`getHeight`/`getHandle` pattern and added:
- `getPixelWidth` / `getPixelHeight` via `SDL_GetWindowSizeInPixels` (HiDPI correctness per WIN-09)
- `getDisplayScale` via `SDL_GetWindowDisplayScale`
- `setRelativeMouseMode` for cursor lock (WIN-08)
- `startTextInput` / `stopTextInput` for Unicode text input mode (WIN-11)

**Cursor functions** — `hideCursor()` / `showCursor()` at module level (matches SDL3 API where cursor is not per-window).

**Gamepad functions** — `openGamepad(id: u32) ?*anyopaque` and `closeGamepad(handle: *anyopaque)`.

**Display info functions** — `getDisplayCount()`, `getDisplayBounds(index, out_x, out_y, out_w, out_h)`, `getDisplayContentScale(index)`, `getDisplayName(index, out_buf, buf_len)` — all using `SDL_GetDisplays` internally with proper cleanup via `defer c.SDL_free(displays)`.

**Lifecycle** — `initPlatform() anyerror!void` returns error union (not bool) per D-12/WIN-10. Always initializes `SDL_INIT_VIDEO | SDL_INIT_EVENTS | SDL_INIT_GAMEPAD` together (GAMEPAD cannot be added after init). `quitPlatform()` / `getErrorMessage()`.

**Timing** — `getTicksNS() u64` and `delayNS(ns: u64)` for nanosecond-precision game loop (LOOP-01/02).

### What Was Removed

- All old `pub const` exports: `INIT_VIDEO`, `INIT_AUDIO`, `INIT_EVENTS`, all `WINDOW_*` flags, all `EVENT_*` constants, all `SCANCODE_*` constants, `MOUSE_LEFT/MIDDLE/RIGHT`
- Old `Event` struct with flat accessor pattern (`getType()`, `getScancode()`, etc.)
- Old `Renderer` struct (SDL2-style software renderer; Tamga uses Vulkan)
- Old `init(flags: u32) bool` replaced by `initPlatform() anyerror!void`
- Old `quit()` replaced by `quitPlatform()`
- Old `getTicks() u64` replaced by `getTicksNS() u64`
- Old `delay(ms: u32)` replaced by `delayNS(ns: u64)`

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Rewrite tamga_sdl3.zig — RawEvent translator and complete SDL3 bridge | f473a63 | src/TamgaSDL3/tamga_sdl3.zig |

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| `initPlatform` always inits GAMEPAD at startup | SDL3 requires GAMEPAD subsystem at init time; cannot add post-init (Pitfall 4 from research) |
| RawEvent uses `u8` tag constants, not Zig enum | Orhon bridge reads tag as plain integer; enums would require cast on every bridge call |
| `getPixelWidth`/`getPixelHeight` use `SDL_GetWindowSizeInPixels` | Logical and pixel sizes diverge on HiDPI displays; correct pixel dims required for Vulkan swapchain |
| Cursor functions at module level, not Window methods | SDL3's `SDL_HideCursor`/`SDL_ShowCursor` are global, not per-window — module-level matches the API |
| `openGamepad` returns `?*anyopaque` (null on failure) | Gamepad open failure is non-fatal; error union would require try-expressions at every gamepad-added event |

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all functions have complete implementations. No placeholder values, hardcoded empties, or TODO markers.

## Requirements Addressed

WIN-01, WIN-02, WIN-03, WIN-04, WIN-05, WIN-06, WIN-08, WIN-09, WIN-10, WIN-11, WIN-14, XC-03, XC-05, XC-06

## Self-Check

File exists: `src/TamgaSDL3/tamga_sdl3.zig` — FOUND
Commit f473a63 — FOUND

## Self-Check: PASSED
