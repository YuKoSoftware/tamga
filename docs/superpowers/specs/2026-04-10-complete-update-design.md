# Tamga Complete Update — Design Spec

**Date:** 2026-04-10
**Status:** In progress — paused at Section 4 pending compiler gap GAP-001

---

## Context

All tamga code is outdated against the current Orhon compiler. The `bridge` keyword and
`#cimport` directive no longer exist. The entire C interop model has been replaced by the
`.zon`-based Zig module system (compiler doc 14). Every `.zig` file in `src/` is auto-discovered
as an Orhon module, C dependencies are declared via paired `.zon` files.

This spec covers a full update of tamga to the current compiler, including:
- Rewriting all `.orh` files to remove dead syntax (`bridge`, `#cimport`)
- Adding `.zon` files for C dependencies
- Splitting the 3200-line `tamga_vk3d.zig` into focused modules
- Stripping incomplete Chunk 4 (compute pipeline) code for a clean baseline
- Full docs cleanup
- Logging every compiler shortcoming encountered

---

## Decisions Made

- **Strip Chunk 4:** Remove incomplete light culling compute pass code. Get a clean, compiling
  baseline first. Re-approach Chunk 4 fresh after the update.
- **Split tamga_vk3d.zig:** Break the 3200-line monolith into logical Zig modules during
  the update, not later.
- **Full docs cleanup:** Update all docs to reflect new baseline. Remove stale renderer spec.
  Clean ideas.md and bugs.md of resolved items.
- **Log all gaps:** Every compiler shortcoming gets logged in `docs/compiler-gaps.md`.
  No workarounds, no hacks.
- **Approach:** Hybrid (C) — quick API sketch for all modules, then bottom-up implementation
  with build verification at each layer.

---

## Section 1: New Module System Migration

### What changes

The old system had `.orh` files declare `bridge struct` and `bridge func` to manually define
the Zig interface, plus `#cimport` for C dependencies. The new system eliminates all of that.

### Impact on each `.orh` file

- **`tamga_sdl3.orh`** (365 lines) — ~60% bridge declarations disappear. What remains: pure
  Orhon code (event dispatch logic, type aliases, the `Event` union type, tag constants,
  `pollEvent()`). `#cimport` for SDL3 moves to `tamga_sdl3.zon`.

- **`tamga_vulkan.orh`** (44 lines) — Almost entirely bridge declarations. Becomes near-empty
  or eliminated, since the `.zig` file exports everything. `#cimport` moves to
  `tamga_vulkan.zon`.

- **`tamga_vk3d.orh`** (117 lines) — Bridge declarations for Renderer/Mesh/Texture/Material
  go away. `#cimport` moves to `.zon` files.

- **`tamga.orh`** (13 lines) — Anchor file. Remove `#cimport` if present, verify imports.

- **`tamga_loop.orh`** (117 lines) — Pure Orhon, no bridge syntax. Minimal changes needed.

### New `.zon` files

| File | Contents |
|------|----------|
| `src/TamgaSDL3/tamga_sdl3.zon` | `.{ .link = .{ "SDL3" } }` |
| `src/TamgaVK/tamga_vulkan.zon` | `.{ .link = .{ "vulkan" }, .source = .{ "libs/vma_impl.cpp" } }` |
| `src/TamgaVK/TamgaVK3D/tamga_vk3d.zon` | `.{ .link = .{ "vulkan" }, .source = .{ "stb_image_impl.c" } }` |

After the split, each new `.zig` file that does `@cImport` for Vulkan headers needs its own
`.zon` with `.link = .{ "vulkan" }`.

### `.orh` files post-migration

`.orh` files become thin consumers that import the auto-generated Zig modules and add
pure-Orhon convenience APIs on top (like typed event dispatch). Files that were 100% bridge
declarations may be eliminated if the Zig module's auto-generated API is sufficient.

---

## Section 2: `tamga_vk3d.zig` Split

### Proposed modules

| New file | Responsibility | Approx lines |
|----------|---------------|-------------|
| `tamga_vk3d.zig` | Anchor — VulkanContext struct, create/destroy, swapchain, frame lifecycle | ~800 |
| `tamga_vk3d_pipeline.zig` | Render passes, pipeline creation (forward + depth prepass), framebuffers, shader loading | ~500 |
| `tamga_vk3d_descriptors.zig` | Descriptor set layouts, pool, allocation, updates, UBO structs (Camera, Material) | ~400 |
| `tamga_vk3d_resources.zig` | Mesh creation/destruction, texture loading (stb_image), material management, staging | ~500 |
| `tamga_vk3d_lighting.zig` | LightData struct, light SSBO, setDirLight/setPointLight/setSpotLight, light counts | ~300 |
| `tamga_vk3d_rendergraph.zig` | RenderGraph struct, pass registration, callbacks, barriers, depth prepass + forward callbacks | ~400 |

### Code stripped (Chunk 4 incomplete)

- `light_cull.comp.glsl` and compiled `.spv`
- Compute pipeline, compute descriptor sets, cluster resources
- `createClusterResources`, `destroyClusterResources`, `createComputeResources`,
  `allocateComputeDescriptorSets`, `destroyComputeResources`
- Cluster config fields from VulkanContext
- All light culling dispatch code

### Inter-module imports

Split modules use `@import("sibling.zig")` for shared types. Files prefixed with `_` are
private (not exposed as Orhon modules). Shared internal types can live in `_vk3d_types.zig`.

### `.zon` files for split modules

Each `.zig` file that `@cImport`s Vulkan headers needs its own `.zon` with
`.link = .{ "vulkan" }`. Files that don't directly import C headers don't need a `.zon`.

---

## Section 3: Handle/ID Architecture

### Core principle

The Zig side owns all GPU resources. Orhon code holds typed IDs — lightweight value types
that map perfectly through the auto-mapper. No opaque pointers (`*anyopaque`) cross the
Zig-Orhon boundary.

### Handle types

| ID Type | Wraps | Owned by |
|---------|-------|----------|
| `MeshId` | VkBuffer pair + index count | Renderer |
| `TextureId` | VkImage + VkImageView + VkSampler | Renderer |
| `MaterialId` | UBO + descriptor set + texture ref | Renderer |

Each is `struct { id: u32 }` — maps cleanly, type-safe.

### Resource storage

Renderer holds flat arrays (or slot maps) internally. `createMesh()` allocates a slot,
stores Vulkan objects, returns the ID. `destroyMesh()` frees the slot. Draw calls look up
by ID.

### What crosses the Zig-Orhon boundary

- **IDs** — `u32` in a typed struct. Always safe.
- **Scalars** — `f32`, `u32`, `bool` for parameters. Always safe.
- **Strings** — `[]const u8` → `str` for file paths. Maps cleanly.
- **Float arrays** — Matrices (`[16]f32`), positions (`[3]f32`). Need verification that
  fixed-size arrays map. If not, wrap in structs or pass individual floats.

### Why not opaque pointer wrapping

The stdlib pattern (wrap `*anyopaque` in a named struct) works for self-contained modules
like `SMP` allocator. But for a framework where modules compose — renderer needs Window,
GUI needs Window, audio needs Window — the handles must cross module boundaries through
Orhon code. This leads to the cross-module type mapping gap (GAP-001).

The handle/ID pattern avoids the problem entirely for GPU resources. But the SDL Window
still needs to be passed cross-module, which is blocked by GAP-001.

---

## Section 4: Cross-Module Type Passing (BLOCKED)

### The problem

Multiple tamga libraries need SDL3's Window. Orhon application code creates the window
and passes it to each library. But the auto-mapper skips functions whose parameters use
types from sibling Zig modules (qualified names like `sdl.Window` → `field_access` →
unmappable).

### Compiler gap logged

See `docs/compiler-gaps.md` GAP-001. The compiler already injects sibling imports — it just
doesn't resolve their types in function signatures.

### Blocked until

GAP-001 is fixed in orhon_compiler. No interim workaround — the alternatives (passing raw
`usize`, adding indirection layers) are hacks that violate the project's design philosophy.

### What can proceed without this fix

- `.zon` file creation (no code dependency)
- Docs cleanup (no code dependency)
- Chunk 4 stripping (removes code, doesn't add)
- `tamga_vk3d.zig` split (internal refactor, doesn't change public API yet)
- `tamga_sdl3` modernization (self-contained module, no cross-module types)
- `tamga_loop.orh` syntax verification (pure Orhon)

### What's blocked

- `tamga_vk3d` public API (Renderer.create needs Window)
- `tamga_vulkan` public API (Allocator.create needs Vulkan handles from Renderer)
- Test files (need to create Window and pass to Renderer)
- Any future cross-library integration (GUI, audio, etc.)

---

## Remaining Design Sections (TODO)

These sections need to be designed once GAP-001 is resolved:

- **Section 5: SDL3 module modernization** — what the `.orh` reduces to, event system design
- **Section 6: Vulkan module modernization** — VMA allocator API under new system
- **Section 7: Test file updates** — how test files change
- **Section 8: Docs cleanup plan** — what changes in each doc file
- **Section 9: Build verification strategy** — how to verify at each step

---

## Open Questions

1. Do fixed-size arrays (`[16]f32`, `[3]f32`) map through the auto-mapper? Affects how
   camera matrices and positions are passed.
2. After the split, does each `.zig` file that becomes an Orhon module need its own `.orh`
   anchor, or is the `.zig` file sufficient as the module definition?
3. How does the build system handle `.zon` files for split modules — does each `.zig` get
   its own `.zon`, or can they share?
