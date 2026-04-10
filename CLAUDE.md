# Tamga — Claude Project Instructions

## What This Project Is

Tamga is a multimedia/gaming framework library collection for the Orhon programming language.
Dual purpose: stress-test the Orhon compiler with real-world code, and build a high-quality
modern framework. Built with Orhon (`.orh`) and Zig bridge sidecars (`.zig`). Builds via
`orhon build`.

---

## Build & Test

```bash
orhon build              # build the project
orhon run                # build and run
```

Per-library test files live in `src/test/test_*.orh` — run manually as needed.
No automated test suite (tests are visual/GPU-dependent).

---

## Design Philosophy

- **Vulkan 1.3 only, 64-bit only** — no backwards compatibility with older Vulkan versions
- High performance, clean architecture — no hacks, no workarounds
- When better approaches exist, research and adopt them rather than patching around limitations
- Every design choice must be justified — if the current approach isn't the best, change it
- Code must be clean, organized, and well-structured

---

## Anti-Hallucination Rules

- Never guess Orhon syntax — check orhon_compiler's PEG grammar
  (`/home/yunus/Projects/orhon/orhon_compiler/src/peg/orhon.peg`) and language spec docs
  (`/home/yunus/Projects/orhon/orhon_compiler/docs/01-basics.md` through `docs/15-testing.md`)
- Never guess Zig APIs — use zig-mcp tools (`search_std_lib`, `get_std_lib_item`) or
  WebFetch to verify before using any std lib function not already present in this project
- Never guess Vulkan or SDL3 APIs — check official docs (Khronos Vulkan registry, SDL wiki)
  or use context7 before using any API not already in the codebase
- Never assume orhon_compiler behavior — read its source when in doubt
- If unsure about anything, look it up; don't extrapolate
- If a tool returns no result for an API, it doesn't exist — don't use it

---

## Mandatory Read-Before-Edit

- Always read a file before modifying it — the full relevant section, not just a few lines
- Read orhon_compiler language spec docs before changing Orhon syntax usage
- Read `docs/tech-stack.md` before making technology choices
- Read the relevant module's existing code before adding to it

---

## Code Quality Rules

- Keep changes minimal — don't refactor surrounding code unless asked
- Match existing patterns in the file being edited (naming, error handling style, structure)
- No hacks, no workarounds — if something can't be done cleanly, flag it and discuss
- Never add features, abstractions, or "improvements" beyond what was requested
- Large files are a smell — flag when files grow beyond manageable size

---

## Workflow Rules

### Documentation rule
Each doc file has one specific purpose — no overlap. Before creating a new doc,
check that no existing file covers the topic. README is introduction only.

### Verification discipline
- After meaningful changes: run `orhon build` to check compilation
- Never claim "this should work" — verify it
- After completing any change touching 3+ files or adding a new feature, run a
  code review via `superpowers:requesting-code-review` before claiming done

### Research rule
Before making architecture or API decisions, research current best practices.
Don't default to whatever's already there if it's outdated. Use WebSearch,
context7, or official documentation to verify that a chosen approach is still
the recommended one.

---

## Project Structure

```
src/
  tamga.orh                  — framework anchor (module tamga_framework)
  tamga_helper.zig           — main helper sidecar
  TamgaSDL3/                 — SDL3 window, input, event dispatch, game loop
  TamgaVK/                   — VMA allocator, render graph, Vulkan core
    TamgaVK3D/               — 3D renderer (textures, materials, lighting)
    TamgaVK2D/               — 2D renderer (planned)
    TamgaVKCompute/          — Compute utilities (planned)
    libs/                    — Vulkan headers, VMA
    shaders3D/               — GLSL shader sources
  TamgaCore/                 — Math, BVH, Pathfinding (planned)
  TamgaAI/                   — GOAP, Utility AI (planned)
  TamgaAudio/                — Audio (planned)
  TamgaECS/                  — Entity Component System (planned)
  TamgaGUI/                  — GUI (planned)
  TamgaNET/                  — Networking (planned)
  TamgaPhysics/              — Physics (planned)
  test/                      — Per-library test files
assets/
  shaders/                   — Compiled .spv files (runtime)
  textures/                  — Texture files
docs/
  tech-stack.md              — Technology choices and rationale
  todo.md                    — Current work and tasks
  ideas.md                   — Language and framework ideas
  bugs.md                    — Compiler bugs found via tamga
```

---

## References

- Orhon compiler source: `/home/yunus/Projects/orhon/orhon_compiler` — the authority on
  language syntax, semantics, and behavior
- Orhon language spec: `/home/yunus/Projects/orhon/orhon_compiler/docs/01-basics.md`
  through `docs/15-testing.md`
- PEG grammar: `/home/yunus/Projects/orhon/orhon_compiler/src/peg/orhon.peg`
- Zig docs: https://ziglang.org/documentation/master/
- Vulkan spec: https://registry.khronos.org/vulkan/
- SDL3 docs: https://wiki.libsdl.org/SDL3/
