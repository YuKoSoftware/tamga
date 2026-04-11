# Tamga Complete Update — Design Spec

**Date:** 2026-04-10
**Updated:** 2026-04-11 — Sections 3-4 revised (handle type, GAP-001 resolved), Sections 5-9 added
**Status:** Design complete — ready for implementation planning

---

## Context

All tamga code is outdated against the current Orhon compiler. The `bridge` keyword and
`#cimport` directive no longer exist. The entire C interop model has been replaced by the
`.zon`-based Zig module system (compiler doc 14). Every `.zig` file in `src/` is auto-discovered
as an Orhon module, C dependencies are declared via paired `.zon` files.

Two new compiler features (2026-04-11) unblock the full migration:
- **Cross-module Zig type mapping** — the auto-mapper resolves sibling module types in
  function signatures (GAP-001 fix)
- **Handle type** — `pub handle Name` declares safe, nominally-typed opaque pointers
  for FFI boundaries

This spec covers a full update of tamga to the current compiler, including:
- Rewriting all `.orh` files to remove dead syntax (`bridge`, `#cimport`)
- Adding `.zon` files for C dependencies
- Splitting the 3200-line `tamga_vk3d.zig` into focused modules
- Stripping incomplete Chunk 4 (compute pipeline) code for a clean baseline
- Reorganizing to use current Orhon features (handles, typed enums, unions)
- Full docs cleanup
- Logging every compiler shortcoming encountered

---

## Design Philosophy

Each tamga module is an **independent building block** — usable standalone, but designed for
100% compatibility when composed together. Modules communicate through typed handles and
IDs, never raw pointers.

**Zig side**: thin wrapper around C libraries (SDL3, Vulkan, VMA, stb_image). Handles unsafe
FFI, exports clean mappable types.

**Orhon side**: owns the public API — type definitions, enums, unions, dispatch logic,
convenience layers. All consumer-facing design lives in Orhon.

---

## Decisions Made

- **Strip Chunk 4:** Remove incomplete light culling compute pass code. Get a clean, compiling
  baseline first. Re-approach Chunk 4 fresh after the update.
- **Split tamga_vk3d.zig:** Break the 3200-line monolith into logical Zig modules during
  the update, not later.
- **Full docs cleanup:** Update all docs to reflect new baseline. Remove stale entries.
- **Log all gaps:** Every compiler shortcoming gets logged in `docs/compiler-gaps.md`.
  No workarounds, no hacks.
- **Approach:** Hybrid — API sketch + bottom-up implementation with build verification
  at each layer.
- **Handles for cross-module types, IDs for slot resources** — two reference patterns
  matched to their use case (see Section 3).
- **Orhon owns event types** — Zig exports flat data, Orhon defines typed structs/enums/unions
  (see Section 5).
- **All modules stay public** — each is an independent building block, even tamga_vulkan's
  low-level allocation API (see Section 6).

---

## Section 1: New Module System Migration

### What changes

The old system had `.orh` files declare `bridge struct` and `bridge func` to manually define
the Zig interface, plus `#cimport` for C dependencies. The new system eliminates all of that.

### Impact on each `.orh` file

- **`tamga_sdl3.orh`** (365 lines) — ~60% bridge declarations disappear. What remains: pure
  Orhon code (event dispatch logic, type aliases, the `Event` union type, tag constants,
  `pollEvent()`). `#cimport` for SDL3 moves to `tamga_sdl3.zon`.

- **`tamga_vulkan.orh`** (44 lines) — Almost entirely bridge declarations. Becomes handle and
  struct definitions only. `#cimport` moves to `tamga_vulkan.zon`.

- **`tamga_vk3d.orh`** (117 lines) — Bridge declarations for Renderer/Mesh/Texture/Material
  go away. Becomes ID type definitions only. `#cimport` moves to `.zon` files.

- **`tamga.orh`** (13 lines) — Anchor file. Remove `#name`, update `#version` syntax.

- **`tamga_loop.orh`** (117 lines) — Pure Orhon, no bridge syntax. Verify it compiles.

### New `.zon` files

| File | Contents |
|------|----------|
| `src/TamgaSDL3/tamga_sdl3.zon` | `.{ .link = .{ "SDL3" } }` |
| `src/TamgaVK/tamga_vulkan.zon` | `.{ .link = .{ "vulkan" }, .source = .{ "libs/vma_impl.cpp" } }` |
| `src/TamgaVK/TamgaVK3D/tamga_vk3d.zon` | `.{ .link = .{ "vulkan" }, .source = .{ "stb_image_impl.c" } }` |

### `.orh` files post-migration

`.orh` files become Orhon-native type definitions and convenience APIs. The Zig module's
auto-generated API provides the function signatures. `.orh` files add handles, ID types,
enums, unions, and dispatch logic on top.

---

## Section 2: `tamga_vk3d.zig` Split

### Proposed modules

| New file | Responsibility | Approx lines |
|----------|---------------|-------------|
| `tamga_vk3d.zig` | Anchor — Renderer struct, public API, swapchain, frame lifecycle | ~800 |
| `_vk3d_pipeline.zig` | Render passes, pipeline creation (forward + depth prepass), framebuffers, shader loading | ~500 |
| `_vk3d_descriptors.zig` | Descriptor set layouts, pool, allocation, updates, UBO structs (Camera, Material) | ~400 |
| `_vk3d_resources.zig` | Slot maps for meshes/textures/materials, staging, stb_image loading | ~500 |
| `_vk3d_lighting.zig` | LightData struct, light SSBO, setDirLight/setPointLight/setSpotLight, light counts | ~300 |
| `_vk3d_rendergraph.zig` | RenderGraph struct, pass registration, callbacks, barriers, depth prepass + forward callbacks | ~400 |

Private files (`_` prefix) are not auto-mapped to Orhon modules. Only `tamga_vk3d.zig`
is the public surface — it imports the private modules internally via `@import`.

### Code stripped (Chunk 4 incomplete)

- Compute pipeline, compute descriptor sets, cluster resources
- `createClusterResources`, `destroyClusterResources`, `createComputeResources`,
  `allocateComputeDescriptorSets`, `destroyComputeResources`
- Cluster config fields from VulkanContext
- All light culling dispatch code
- `light_cull.comp.glsl` stays in `shaders3D/` for future reference

### Inter-module imports

Split modules use `@import("_sibling.zig")` for shared types. Shared internal types
can live in `_vk3d_types.zig` if needed.

### `.zon` files for split modules

Only `tamga_vk3d.zig` needs a `.zon` — private `_` files are imported by it, not compiled
as separate modules.

---

## Section 3: Handle/ID Architecture

### Core principle

Zig owns all GPU/platform resources. Orhon code holds typed references — handles or IDs.
No raw `Ptr(u8)` crosses the Zig-Orhon boundary.

### Handles — for opaque platform/driver resources

Use `pub handle` for resources that are fundamentally pointers on the Zig side and need to
cross module boundaries. Orhon code never inspects them, just passes them around.

| Handle | Wraps | Module |
|--------|-------|--------|
| `WindowHandle` | SDL_Window* | tamga_sdl3 |
| `VkBufferHandle` | VkBuffer | tamga_vulkan |
| `VmaAllocationHandle` | VmaAllocation | tamga_vulkan |
| `StagingBufferHandle` | VkBuffer (staging) | tamga_vulkan |
| `VkInstanceHandle` | VkInstance | tamga_vulkan |
| `VkPhysicalDeviceHandle` | VkPhysicalDevice | tamga_vulkan |
| `VkDeviceHandle` | VkDevice | tamga_vulkan |

### IDs — for renderer-managed slot resources

Use `struct { pub id: u32 }` for resources the renderer owns in internal arrays/slot maps.
The ID is an index, not a pointer — the renderer resolves it internally.

| ID Type | Wraps | Module |
|---------|-------|--------|
| `MeshId` | vertex/index buffer pair + metadata | tamga_vk3d |
| `TextureId` | VkImage + VkImageView + VkSampler | tamga_vk3d |
| `MaterialId` | UBO + descriptor set + texture ref | tamga_vk3d |

### Why two patterns

- **Handles** for things that already are pointers in Zig and need to flow between modules.
  The `handle` type is exactly this — nominally typed `*anyopaque`, zero cost.
- **IDs** for things the renderer manages in slot maps. A `MeshId` is a slot index — there's
  no pointer to wrap.

### What crosses module boundaries

- Handles and IDs — always safe, typed
- Scalars (`f32`, `u32`, `bool`) — always safe
- Strings (`str`) — maps from `[]const u8`
- Structs with only mappable fields (`BufferAlloc`, `StagingRegion`, event structs)

---

## Section 4: Cross-Module Type Passing

### Resolved — GAP-001 fixed (2026-04-11)

The auto-mapper now resolves sibling Zig module types in function signatures. Both patterns:

```zig
// Alias pattern
const sdl = @import("tamga_sdl3.zig");
pub fn create(handle: sdl.WindowHandle) Renderer { ... }

// Inline pattern
pub fn create(handle: @import("tamga_sdl3.zig").WindowHandle) Renderer { ... }
```

Both produce: `pub func create(handle: tamga_sdl3.WindowHandle) Renderer`

### Cross-module type flow in tamga

```
tamga_sdl3          tamga_vulkan          tamga_vk3d
───────────         ────────────          ──────────
WindowHandle ──────────────────────────→ Renderer.create(handle: tamga_sdl3.WindowHandle)
                    VkBufferHandle ────→ (internal use by vk3d)
                    VmaAllocationHandle → (internal use by vk3d)
```

### Rules for new modules

- Cross-module types must be `pub` in the exporting module
- The Zig file uses `@import("sibling.zig")` — the compiler handles the rest
- Only types from sibling `.zig` files are resolved — Zig stdlib types remain unmappable
- Each module stays independently usable — cross-module types are for composition, not coupling

### Handle type enables clean cross-module flow

`pub handle WindowHandle` in `tamga_sdl3` is nominally typed — it can't be confused with
any other handle. When `tamga_vk3d` accepts it, the Orhon type system enforces correctness.
No raw pointer casts, no integer reinterpretation.

---

## Section 5: SDL3 Module Modernization

### What `tamga_sdl3.orh` becomes

The file goes from 365 lines (mixed bridge + Orhon) to pure Orhon.

**Removed entirely:**
- `#cimport` directive — moves to `tamga_sdl3.zon`
- `#name` directive — no longer exists
- `Version()` syntax — replaced by tuple `(0, 2, 0)`
- `bridge struct Window` — auto-mapped from Zig
- `bridge struct RawEvent` with 20+ getter methods — replaced by flat auto-mapped struct
- All `bridge func` declarations — auto-mapped from Zig
- `pub const WindowHandle: type = Ptr(u8)` — replaced by `pub handle WindowHandle`
- `pollEventTag()` / `getLastScancode()` — removed, typed `pollEvent()` is canonical

**Stays but modernized:**
- Event structs (KeyDownEvent, MouseMotionEvent, etc.) — stay as Orhon structs
- Scancode and MouseButton enums — stay
- `pollEvent()` function — stays, reads flat struct fields instead of getter methods
- TAG constants — stay, used by pollEvent dispatch
- Event union type alias — stays

**New:**
- `pub handle WindowHandle`
- `tamga_sdl3.zon` — `.{ .link = .{ "SDL3" } }`

### Zig side changes (`tamga_sdl3.zig`)

**RawEvent refactor**: Replace getter-method pattern with a flat public struct:

```zig
pub const RawEvent = struct {
    tag: u8 = 0,
    scancode: u32 = 0,
    key_repeat: bool = false,
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    mouse_xrel: f32 = 0,
    mouse_yrel: f32 = 0,
    mouse_button: u8 = 0,
    mouse_down: bool = false,
    gamepad_id: u32 = 0,
    gamepad_axis: u8 = 0,
    gamepad_axis_value: i16 = 0,
    gamepad_button: u8 = 0,
    window_w: i32 = 0,
    window_h: i32 = 0,
    pixel_w: i32 = 0,
    pixel_h: i32 = 0,
    timestamp: u64 = 0,
    // text: needs lifetime investigation — SDL3 may reuse internal buffer
};
```

All getter methods removed. `pollRawEvent` fills this struct, Orhon reads fields directly.

**Window**: Already a pub struct with pub methods — auto-maps cleanly. `getHandle()` returns
`WindowHandle` (`*anyopaque` handle type).

**Lifecycle/utility functions**: `initPlatform`, `quitPlatform`, `getError`, `hideCursor`,
`showCursor`, etc. — already pub functions, auto-map directly.

**pollEventTag / getLastScancode**: Removed entirely. Typed `pollEvent()` is the only API.

### `tamga_loop.orh` changes

Minimal — pure Orhon, part of `module tamga_sdl3`. Verify it compiles with modernized
`tamga_sdl3`. No syntax changes expected.

### Open item: text field in RawEvent

`getText()` currently returns `String`. The flat struct needs a `text` field — `[]const u8`
maps to `str`, but the text data comes from SDL's internal buffer. Need to verify during
implementation whether the Zig side should copy the string or if SDL3 guarantees lifetime
across the poll boundary.

---

## Section 6: Vulkan Module Modernization

### What `tamga_vulkan.orh` becomes

Currently 44 lines, almost entirely bridge declarations. After modernization, handle and
struct definitions only.

**Removed:**
- `#cimport` directive — moves to `tamga_vulkan.zon`
- `#name` directive, `Version()` syntax
- `bridge struct Allocator` — auto-mapped from Zig
- `Ptr(u8)` usage in all structs

**Post-modernization `tamga_vulkan.orh`:**

```
module tamga_vulkan

#version = (0, 2, 0)
#build   = static

pub handle VkInstanceHandle
pub handle VkPhysicalDeviceHandle
pub handle VkDeviceHandle
pub handle VkBufferHandle
pub handle VmaAllocationHandle
pub handle StagingBufferHandle

pub struct BufferAlloc {
    pub buffer: VkBufferHandle
    pub allocation: VmaAllocationHandle
}

pub struct StagingRegion {
    pub buffer: StagingBufferHandle
    pub offset: u32
}
```

The `Allocator` struct with all methods — auto-mapped from the Zig side.

### Zig side changes (`tamga_vulkan.zig`)

**Handle types at public API boundary**: Use `*anyopaque` for types that map to Orhon handles.
VkBuffer, VmaAllocation, VkInstance, VkPhysicalDevice, VkDevice need thin wrappers or casts
at the public function boundary.

**Allocator.create signature**: Changes from three `Ptr(u8)` params to typed handles:
`create(instance: VkInstanceHandle, physical_device: VkPhysicalDeviceHandle, device: VkDeviceHandle) !Allocator`

**Internal**: VMA calls still use raw Vulkan types internally — handle wrapping is only at
the public API boundary.

### New: `tamga_vulkan.zon`

```zig
.{
    .link = .{ "vulkan" },
    .source = .{ "libs/vma_impl.cpp" },
}
```

### Independence

`tamga_vulkan` is usable standalone for custom GPU buffer management without the 3D renderer.

---

## Section 7: 3D Renderer Module Modernization

### What `tamga_vk3d.orh` becomes

Currently 117 lines, almost entirely bridge declarations. After modernization, ID type
definitions only.

**Post-modernization `tamga_vk3d.orh`:**

```
module tamga_vk3d

#version = (0, 2, 0)
#build   = static

pub struct MeshId {
    pub id: u32
}

pub struct TextureId {
    pub id: u32
}

pub struct MaterialId {
    pub id: u32
}
```

The Renderer struct with all methods — auto-mapped from the Zig side.

### Zig side — public API after split

`tamga_vk3d.zig` is the only public module. Key function signatures:

- `create(handle: sdl.WindowHandle, debug_mode: bool) !Renderer`
- `createMesh(self: *Renderer, vertices: [*]const u8, vertex_byte_size: u32, indices: [*]const u8, index_count: u32) !MeshId`
- `destroyMesh(self: *Renderer, id: MeshId) void`
- `loadTexture(self: *Renderer, path: [*:0]const u8) !TextureId`
- `destroyTexture(self: *Renderer, id: TextureId) void`
- `createMaterial(self: *Renderer, ...) !MaterialId`
- `destroyMaterial(self: *Renderer, id: MaterialId) void`
- `draw(self: *Renderer, mesh: MeshId, material: MaterialId, model_matrix: [*]const f32) void`
- `setCamera(self: *Renderer, view: [*]const f32, proj: [*]const f32, view_pos: [*]const f32) void`
- Light functions unchanged in signature

### ID resolution

The Renderer holds internal slot arrays. When Orhon calls `draw(meshId, materialId, matrix)`,
the Zig side looks up actual VkBuffer/descriptor set by slot index and issues the draw call.

### `.zon` file

```zig
// tamga_vk3d.zon
.{
    .link = .{ "vulkan" },
    .source = .{ "stb_image_impl.c" },
}
```

### Chunk 4 stripping

All incomplete compute pipeline code removed. `light_cull.comp.glsl` stays in `shaders3D/`
for future reference.

---

## Section 8: Test File Updates

### `test_vulkan.orh` — full rewrite

Changes:
- Replace `pollEventTag()` / `getLastScancode()` with typed `pollEvent()` + `is` dispatch
- Replace magic `268435456` with `WindowFlags.Vulkan` bitfield
- Replace `Mesh`, `Texture`, `Material` bridge structs with `MeshId`, `TextureId`, `MaterialId`
- `WindowHandle` is now a handle type — usage unchanged, type safety improved
- Vertex/matrix helper calls stay — `tamga_helper` auto-maps

### `test_sdl3.orh` — minor updates

Already uses typed event pattern. Verify it compiles against modernized `tamga_sdl3`.
Use `WindowFlags` bitfield if flags are needed.

### `tamga.orh` — project anchor

- Remove `#name`, update `#version` to tuple syntax
- `import tamga_helper` — auto-mapped, no bridge needed
- `main()` calls `run_vulkan_test()` — unchanged

### Test verification order

1. `test_sdl3` after `tamga_sdl3` modernization
2. `test_vulkan` after all modules modernized
3. Both must compile and run visually

---

## Section 9: Docs Cleanup & Build Verification

### Docs cleanup

| File | Action |
|------|--------|
| `docs/compiler-gaps.md` | Already updated — GAP-001 resolved, no open gaps |
| `docs/todo.md` | Full rewrite after implementation to reflect actual state |
| `docs/tech-stack.md` | Update for `.zon` module system, handle types, remove bridge references |
| `docs/ideas.md` | Remove implemented/irrelevant ideas, keep future items |
| `docs/bugs.md` | Remove resolved compiler bugs, keep tamga-specific bugs |

### Build verification strategy

Verification in layers, bottom-up. Each layer must compile before the next begins.

**Layer 0: Module infrastructure**
- Create all `.zon` files
- Update `#version` syntax in all `.orh` anchors
- Remove all `#name`, `#cimport` directives
- `orhon build` — validates `.zon` files (bridge syntax still present, expected failures)

**Layer 1: `tamga_sdl3`**
- Modernize `tamga_sdl3.zig` (flat RawEvent, remove getters)
- Modernize `tamga_sdl3.orh` (remove bridge, add handle, update pollEvent)
- Verify `tamga_loop.orh` compiles
- `orhon build` — tamga_sdl3 module compiles cleanly

**Layer 2: `tamga_vulkan`**
- Modernize `tamga_vulkan.zig` (handle types at API boundary)
- Modernize `tamga_vulkan.orh` (handle declarations, typed structs)
- `orhon build` — tamga_vulkan module compiles cleanly

**Layer 3: `tamga_vk3d`**
- Strip Chunk 4 incomplete code
- Split `tamga_vk3d.zig` into 6 files (1 public + 5 private)
- Modernize `tamga_vk3d.orh` (ID types, remove bridge)
- Create `.zon` for tamga_vk3d
- `orhon build` — tamga_vk3d module compiles cleanly

**Layer 4: Tests & anchor**
- Update `tamga.orh` anchor
- Update `test_vulkan.orh` (typed events, IDs, WindowFlags)
- Update `test_sdl3.orh` (minor)
- `orhon build` — full project compiles
- `orhon run` — window opens, triangle renders

**Failure protocol:**
- If `orhon build` fails at any layer, fix before proceeding
- If a failure reveals a new compiler gap, log in `docs/compiler-gaps.md` and assess severity
- Never skip a verification step

---

## Open Questions

1. **Text field lifetime in RawEvent** — does SDL3 guarantee the text buffer survives until
   the next poll call? Determines whether Zig copies the string or passes a view.
2. **Fixed-size array mapping** — do `[16]f32` and `[3]f32` map through the auto-mapper?
   Affects camera matrix and position passing. If not, keep pointer-based passing.
3. **Shared `.zon` for split modules** — does each `.zig` that `@cImport`s need its own `.zon`,
   or can private `_` files inherit from the anchor's `.zon`? Per doc 14, local `.c`/`.cpp`
   files are auto-detected, and `_` files aren't compiled as separate modules — so the
   anchor's `.zon` should suffice.
