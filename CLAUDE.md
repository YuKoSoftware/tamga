# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About Orhon

Orhon is a compiled, memory-safe language that transpiles to Zig. It has ownership/borrow checking without lifetime annotations, explicit error handling without exceptions, and compile-time generics. The compiler (`orhon`) is available in PATH.

Requires Zig 0.15.x installed globally.

## Commands

```bash
orhon build             # debug build for native platform
orhon run               # build and run
orhon test              # run all test { } blocks
orhon fmt               # format all .orh files
orhon debug             # show project info: modules, files, source directory
orhon gendoc            # generate Markdown docs from /// comments (pub items)
orhon build -fast       # max speed optimization
orhon build -verbose    # show raw Zig compiler output (for debugging codegen)
orhon build -linux_x64 -win_x64  # cross-compile multi-target
```

Output goes to `bin/`. Cache lives in `.orh-cache/` and `zig-cache/` — both belong in `.gitignore`, never edit `.orh-cache/generated/` manually.

## Project Structure

Every project is rooted at `src/main.orh` with `module main`. Source files live in `src/` at any depth — directory layout is purely organizational; the compiler groups files by their `module` declaration, not their path.

```
src/
    main.orh            # module main — #build, #name, #version here only
    player.orh          # module main — additional file
    math/math.orh       # module math — anchor file (must match module name)
    math/vectors.orh    # module math — additional file
```

**Anchor file rule:** exactly one file per module must be named `<modulename>.orh`. Only the anchor file can contain metadata (`#build`, `#name`, `#version`, `#dep`).

**Build types:** `#build = exe` | `#build = static` | `#build = dynamic`

**Imports:**
```
import math             # project-local module
import std::alpha       # stdlib module
import std::alpha as io # with alias
```

No circular imports ever. Everything is private by default; `pub` exposes symbols outside the module.

## Zig Reference

Zig version: **0.15.2**
- Language reference: https://ziglang.org/documentation/0.15.0/
- Community guide: https://zig.guide/
- Source repo: https://codeberg.org/ziglang/zig

## Zig Bridge (Native Bindings)

All C/system interop goes through Zig. Each bridged module has a `.zig` sidecar alongside its anchor `.orh` file:

```
src/
    sdl.orh     # bridge declarations
    sdl.zig     # Zig implementation (C interop, SDL calls, etc.)
```

```
// sdl.orh
module sdl

bridge func windowCreate(title: String, w: i32, h: i32) Ptr(u8)
bridge struct Renderer {
    bridge func create(win: Ptr(u8)) Renderer
    bridge func draw(self: &Renderer) void
}
```

**Bridge safety:** mutable `&T` cannot cross the bridge in either direction (except `self: &BridgeStruct` on methods). Use `const &T` for read borrows or pass by value.

**External deps** declared in anchor file — the compiler never fetches them, place them manually:
```
#dep "./libs/sdl3"  Version(3, 0, 0)
```

## Dual Purpose

This project serves two equally important goals:

1. **Real framework** — a genuinely usable, production-quality game/multimedia library for Orhon
2. **Language stress test** — Orhon is young and actively developed; this framework is a primary vehicle for discovering compiler bugs, missing features, and language rough edges

When something doesn't compile or behaves unexpectedly, it may be a compiler bug rather than a code mistake. Log it in `docs/bugs.txt`. When a pattern feels awkward or requires a workaround, log it in `docs/ideas.txt` as potential language feedback.

**Never work around compiler bugs by writing bad code** — if a valid language construct is broken, note it and find a clean alternative, or leave a comment marking the workaround as temporary.

## Framework Design Goals

- Written in pure Orhon; native bindings (SDL3, Vulkan) via the Zig bridge only
- Highly modular — each component (renderer, audio, ECS, physics) is an independent library module
- Support both immediate and retained GUI modes
- Cross-platform, lean and fast — no hacks or workarounds

## Planned Components

- Window/input (SDL3 bridge)
- Vulkan and OpenGL rendering
- Standalone 2D renderer (Vulkan, performance-optimized)
- Standalone 3D renderer (Vulkan, performance-optimized)
- WAV player (sound effects) and OGG player (music)
- Physics engine (lightweight)
- ECS library with attachable Orhon scripts (Godot-style)
- Game loop
- 3D model loader
