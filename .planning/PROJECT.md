# Tamga Framework

## What This Is

A comprehensive collection of multimedia, gaming, and GUI libraries for the Orhon programming language. Tamga sits above Orhon's standard library as the heavier, higher-level building blocks — windowing, rendering, audio, and GUI — that don't belong in a std but are essential for real applications. It also serves as a primary stress test for the Orhon compiler.

## Core Value

Provide a complete, high-performance set of modular libraries that let an Orhon developer open a window, render 2D and 3D graphics, play audio, and build GUI — the foundation everything else is built on.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Cross-platform windowing system with full SDL3 abstraction (swappable backend)
- [ ] Input handling (keyboard, mouse, gamepad) through the windowing abstraction
- [ ] Dedicated Vulkan 3D renderer optimized for high performance
- [ ] Dedicated Vulkan 2D renderer optimized for high performance
- [ ] GUI library supporting both retained mode and immediate mode (game UI + dev tools)
- [ ] Audio playback: WAV sound effects + OGG music streaming, volume control, basic mixing
- [ ] Audio architecture designed for future expansion (spatial audio, effects, DSP)
- [ ] All native bindings (SDL3, Vulkan) via Zig bridge only
- [ ] Each component is an independent library module
- [ ] Cross-platform support (Linux, Windows, macOS)

### Out of Scope

- OpenGL fallback renderer — deferred to future milestone, Vulkan-only for now
- Physics engine — future milestone (core libraries first)
- ECS library — future milestone (game engine territory)
- Networking — future milestone
- Animation system — future milestone
- 3D model loading — future milestone
- Game loop — game engine territory (Tamga engine project)

## Context

- Orhon is a young compiled language that transpiles to Zig; the compiler is actively developed
- This framework is a dual-purpose project: real usable library AND compiler stress test
- Compiler bugs may surface during development — these get logged, not worked around with bad code
- SDL3 is the underlying platform layer but must be fully abstracted — no SDL3 leakage into higher libraries
- Vulkan is the sole graphics backend for this milestone
- The future Tamga game engine (a separate project, Godot-inspired) will build on top of this framework
- Existing code: Vulkan 3D renderer prototype, SDL3 bridge, module structure established

## Constraints

- **Language**: Pure Orhon; C/system interop only through Zig bridge sidecar files
- **Graphics API**: Vulkan only (no OpenGL this milestone)
- **Platform layer**: SDL3 via Zig bridge, fully abstracted behind Orhon API
- **Build system**: Orhon compiler (`orhon build`), Zig 0.15.x
- **Modularity**: Each component must be an independent library module with clean boundaries

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Full SDL3 abstraction | Enable backend swapping later; keep libraries portable | — Pending |
| Vulkan-only renderers | Maximum performance, single backend to maintain | — Pending |
| Separate 2D and 3D renderers | Each optimized for its domain rather than one-size-fits-all | — Pending |
| GUI: explore unified library with mode switching | Simpler API surface if achievable; fall back to 2 libraries if not | — Pending |
| Audio: basic playback with extensible architecture | Ship essentials fast, design for future spatial/effects/DSP | — Pending |
| Core libraries first | Window, render, GUI, audio — the essentials before physics/ECS/networking | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-25 after initialization*
