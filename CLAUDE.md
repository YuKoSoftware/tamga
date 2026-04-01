# Tamga Framework

A collection of multimedia, gaming, and GUI libraries for the Orhon programming language.
Sits above Orhon's standard library as higher-level building blocks — windowing, rendering,
audio, and GUI. Also serves as a primary stress test for the Orhon compiler.

## Rules

- no workarounds
- no hacky code
- comments stay up to date
- always cleanup, no lingering stale code or comments
- clean and correct code
- always log bugs and other problems
- correct mechanics
- modular and maintainable code
- keep project well organized
- keep code well organized
- keep documentation up to date and well organized
- always be clear what you want to implement
- always be clear about the changes
- only well researched changes, don't step into the dark

## Design Goals

- Written in pure Orhon; native bindings (SDL3, Vulkan) via the Zig bridge only
- Highly modular — each component (renderer, audio, ECS, physics) is an independent library module
- Cross-platform, lean and fast — no hacks or workarounds
- API must be easy to use from the caller's perspective

## Component Design Notes

### Rendering
- Vulkan only, optimized for Vulkan
- Separate 2D and 3D renderers (each optimized for its domain)
- Clustered forward rendering
- Mesh optimizer, glTF 2.0 only, gltfpack
- No vendor-specific GPU paths

### GUI
- Work on retained mode first
- Should be based on ECS
- Should be usable as a standalone GUI library
- Node-based system for UI layout

### ECS
- Optimized for performance

### Physics
- Consider Jolt (high performance, unlikely we can do better)

### Game AI
- GOAP + Utility AI — offered separately
- High performance, easy to use

### Audio
- SDL3 core audio + stb_vorbis for OGG

### Pathfinding
- Most common algorithms, high performance

### Database
- LMDB for fast database

## Planned Components

- Window/input (SDL3 bridge) — **done** (tamga_sdl3)
- Vulkan 3D renderer — **done** (tamga_vk3d: textures, materials, Phong lighting)
- VMA GPU memory allocator — **done** (tamga_vk, formerly tamga_vulkan)
- Game loop — **done** (tamga_sdl3: fixed-timestep with variable render)
- Standalone 2D renderer (Vulkan, performance-optimized)
- Audio (WAV + OGG via SDL3 core + stb_vorbis)
- GUI library (pure Orhon over 2D renderer)

## Docs

- `docs/tech-stack.md` — full technology stack, library versions, alternatives considered
- `docs/bugs.md` — compiler bugs discovered while building Tamga
- `docs/ideas.md` — language design ideas from building Tamga

## About Orhon

The compiler is at `/home/yunus/Projects/orhon/orhon_compiler`.
Check its docs, update Tamga code and docs accordingly to the latest spec.

Orhon is a compiled, memory-safe language that transpiles to Zig. It has ownership/borrow
checking without lifetime annotations, explicit error handling without exceptions, and
compile-time generics. The compiler (`orhon`) is available in PATH.

Requires Zig 0.15.x installed globally.

## Commands

```bash
orhon build             # debug build for native platform
orhon run               # build and run
orhon test              # run all test { } blocks
orhon fmt               # format all .orh files
orhon debug             # show project info
orhon build -fast       # max speed optimization
orhon build -verbose    # show raw Zig compiler output
```

Output goes to `bin/`. Cache lives in `.orh-cache/` and `zig-cache/` — both in `.gitignore`.

## Project Structure

Every project is rooted at `src/main.orh` with `module main` (note: a breaking change to
rename `module main` to `module <project_name>` is in design stage). Source files live in `src/`
at any depth — directory layout is purely organizational; the compiler groups files by their
`module` declaration, not their path.

**Anchor file rule:** exactly one file per module must be named `<modulename>.orh`.
Only the anchor file can contain metadata (`#build`, `#name`, `#version`, `#dep`).

**Imports:**
```
import math             # project-local module (namespaced: math.func())
use math                # scope-merged import (func() directly)
import std::console     # stdlib module
```

No circular imports. Everything is private by default; `pub` exposes symbols.

## Zig Bridge (Native Bindings)

All C/system interop goes through Zig. Each bridged module has a `.zig` sidecar
alongside its anchor `.orh` file.

**Bridge safety:** mutable `mut& T` cannot cross the bridge in either direction
(except `self: mut& BridgeStruct` on methods). Use `const& T` for read borrows or pass by value.

## Syntax Notes (Current Compiler)

- References: `self: mut& T` (mutable), `self: const& T` (read-only) — no bare `&T`
- Error unions: `ErrorUnion(T)` not `(Error | T)`; null unions: `NullUnion(T)` not `(null | T)`
- Multi-type nullable: `NullUnion((A | B | C))`
- Compiler intrinsics use `@` prefix: `@cast(T, x)`, `@copy`, `@move`, `@swap`, `@assert`, `@size`, `@align`, `@typename`, `@typeid`
- Module naming: primary exe module must match project folder name (no `module main`)
- Address-of: `mut& x` not `&x`
- Collections require `use std::collections`

When compiler docs are stale, update them in `/home/yunus/Projects/orhon/orhon_compiler/docs/`.

## Conventions

- **All runtime assets live in `assets/`** — organized by category: `assets/shaders/`,
  `assets/textures/`, etc.
- **Test binaries must be portable** — no hardcoded source paths. All file references
  use short CWD-relative paths into `assets/`.

## Dual Purpose

1. **Real framework** — genuinely usable, production-quality game/multimedia library for Orhon
2. **Language stress test** — discovers compiler bugs, missing features, and language rough edges

When something doesn't compile or behaves unexpectedly, it may be a compiler bug — log it
in `docs/bugs.md`. When a pattern feels awkward, log it in `docs/ideas.md`.

**Never work around compiler bugs by writing bad code.**
