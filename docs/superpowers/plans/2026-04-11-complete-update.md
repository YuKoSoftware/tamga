# Tamga Complete Update — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate tamga to the current Orhon compiler — remove dead syntax, add `.zon` files, split `tamga_vk3d.zig`, modernize all modules with handle types and clean APIs, strip Chunk 4, update tests and docs.

**Architecture:** Bottom-up, layer by layer. Each layer compiles before the next begins. Zig side is a thin C wrapper; Orhon side owns the public API (types, enums, unions, dispatch). Handles for cross-module opaque pointers, IDs for slot-managed GPU resources.

**Tech Stack:** Orhon (.orh), Zig (.zig), Vulkan 1.3, SDL3, VMA, stb_image, GLSL/SPIR-V

**Design spec:** `docs/superpowers/specs/2026-04-10-complete-update-design.md`

---

## File Map

### New files to create

| File | Purpose |
|------|---------|
| `src/TamgaSDL3/tamga_sdl3.zon` | SDL3 link config |
| `src/TamgaVK/tamga_vulkan.zon` | Vulkan + VMA link config |
| `src/TamgaVK/TamgaVK3D/tamga_vk3d.zon` | Vulkan + stb_image link config |
| `src/TamgaVK/TamgaVK3D/_vk3d_pipeline.zig` | Render passes, pipelines, framebuffers, shaders |
| `src/TamgaVK/TamgaVK3D/_vk3d_descriptors.zig` | Descriptor layouts, pool, allocation, UBO structs |
| `src/TamgaVK/TamgaVK3D/_vk3d_resources.zig` | Slot maps for mesh/texture/material, staging |
| `src/TamgaVK/TamgaVK3D/_vk3d_lighting.zig` | Light data struct, SSBO, light setter functions |
| `src/TamgaVK/TamgaVK3D/_vk3d_rendergraph.zig` | Render graph callbacks (depth prepass, forward) |

### Existing files to modify

| File | Changes |
|------|---------|
| `src/TamgaSDL3/tamga_sdl3.zig` | Remove getter methods, remove pollEventTag/getLastScancode, flatten RawEvent fields to pub |
| `src/TamgaSDL3/tamga_sdl3.orh` | Remove all bridge/cimport syntax, add `pub handle WindowHandle`, rewrite pollEvent to use flat struct fields |
| `src/TamgaSDL3/tamga_loop.orh` | Remove `#name` if present, verify compiles |
| `src/TamgaVK/tamga_vulkan.zig` | Remove bridge export functions, expose VmaContext as pub Allocator with handle-typed API |
| `src/TamgaVK/tamga_vulkan.orh` | Remove all bridge syntax, add handle declarations, keep BufferAlloc/StagingRegion with typed handles |
| `src/TamgaVK/TamgaVK3D/tamga_vk3d.zig` | Strip Chunk 4, split into modules, rewrite Renderer public API with MeshId/TextureId/MaterialId |
| `src/TamgaVK/TamgaVK3D/tamga_vk3d.orh` | Remove all bridge syntax, add ID structs |
| `src/tamga.orh` | Remove `#name`, update `#version` syntax |
| `src/tamga_helper.zig` | No changes needed (already pub functions returning `*const anyopaque`) |
| `src/test/test_sdl3.orh` | Minor — verify compiles with modernized tamga_sdl3 |
| `src/test/test_vulkan.orh` | Full rewrite — typed events, IDs, WindowFlags |
| `docs/tech-stack.md` | Update for .zon system, handle types, Vulkan 1.3 target |
| `docs/ideas.md` | Remove implemented/obsolete items |
| `docs/todo.md` | Full rewrite to reflect completed update |

---

## Task 1: Create `.zon` files

**Files:**
- Create: `src/TamgaSDL3/tamga_sdl3.zon`
- Create: `src/TamgaVK/tamga_vulkan.zon`
- Create: `src/TamgaVK/TamgaVK3D/tamga_vk3d.zon`

- [ ] **Step 1: Create `tamga_sdl3.zon`**

```zig
.{
    .link = .{ "SDL3" },
}
```

- [ ] **Step 2: Create `tamga_vulkan.zon`**

```zig
.{
    .link = .{ "vulkan" },
    .source = .{ "libs/vma_impl.cpp" },
}
```

- [ ] **Step 3: Create `tamga_vk3d.zon`**

```zig
.{
    .link = .{ "vulkan" },
    .source = .{ "stb_image_impl.c" },
}
```

- [ ] **Step 4: Commit**

```bash
git add src/TamgaSDL3/tamga_sdl3.zon src/TamgaVK/tamga_vulkan.zon src/TamgaVK/TamgaVK3D/tamga_vk3d.zon
git commit -m "feat: add .zon files for C dependency configuration"
```

---

## Task 2: Update project anchor (`tamga.orh`)

**Files:**
- Modify: `src/tamga.orh`

- [ ] **Step 1: Modernize the anchor file**

Replace the full contents of `src/tamga.orh` with:

```
module tamga_framework

#version = (0, 2, 0)
#build   = exe

import tamga_helper

func main() void {
    run_vulkan_test()
}
```

Changes: removed `#name`, updated `#version` from `Version(0, 1, 5)` to tuple `(0, 2, 0)`.

- [ ] **Step 2: Commit**

```bash
git add src/tamga.orh
git commit -m "chore: modernize tamga.orh anchor — remove #name, update #version syntax"
```

---

## Task 3: Modernize `tamga_sdl3.zig`

**Files:**
- Modify: `src/TamgaSDL3/tamga_sdl3.zig`

- [ ] **Step 1: Remove getter methods from RawEvent**

In `src/TamgaSDL3/tamga_sdl3.zig`, remove all getter methods from the `RawEvent` struct (lines 74-100: `create`, `poll`, `getTag`, `getKeyScancode`, `getKeyRepeat`, `getMouseX`, `getMouseY`, `getMouseXRel`, `getMouseYRel`, `getMouseButton`, `getMouseDown`, `getGamepadWhich`, `getGamepadAxis`, `getGamepadAxisValue`, `getGamepadButton`, `getText`, `getWindowW`, `getWindowH`, `getPixelW`, `getPixelH`, `getTimestamp`).

Make all RawEvent struct fields `pub`:

```zig
pub const RawEvent = struct {
    pub tag: u8,
    pub key_scancode: u32,
    pub key_repeat: bool,
    pub mouse_x: f32,
    pub mouse_y: f32,
    pub mouse_xrel: f32,
    pub mouse_yrel: f32,
    pub mouse_button: u8,
    pub mouse_down: bool,
    pub gamepad_which: u32,
    pub gamepad_axis: u8,
    pub gamepad_axis_value: i16,
    pub gamepad_button: u8,
    pub text: [32]u8,
    pub window_w: i32,
    pub window_h: i32,
    pub pixel_w: i32,
    pub pixel_h: i32,
    pub timestamp: u64,
};
```

- [ ] **Step 2: Add `createRawEvent` and update `pollRawEvent` signature**

Replace the removed `RawEvent.create()` and `RawEvent.poll()` methods with standalone pub functions. The existing `pollRawEvent` function (line 105) already exists but takes a pointer param — change it to return a struct directly so Orhon can call it cleanly:

```zig
pub fn createRawEvent() RawEvent {
    return std.mem.zeroes(RawEvent);
}

pub fn pollRawEvent(out: *RawEvent) bool {
    // ... (existing implementation unchanged)
}
```

Note: keep the existing `pollRawEvent` implementation body (lines 105-214) unchanged — it already fills the struct correctly.

- [ ] **Step 3: Remove `pollEventTag` and `getLastScancode`**

Remove the module-level `last_event` variable (line 399) and both functions `pollEventTag` (lines 401-409) and `getLastScancode` (lines 412-414).

- [ ] **Step 4: Verify the text field approach**

The `text` field is `[32]u8` — a fixed-size array. The auto-mapper may not map fixed-size arrays. Check whether the Orhon auto-mapper handles `[32]u8`. If not, add a `pub fn getTextSlice(self: *const RawEvent) []const u8` method that returns a slice — `[]const u8` maps to `str`.

Read `/home/yunus/Projects/orhon/orhon_compiler/src/zig_module.zig` and search for how arrays are mapped to determine which approach works. If `[32]u8` doesn't map, keep a single `getText` getter method on RawEvent for the text field only.

- [ ] **Step 5: Commit**

```bash
git add src/TamgaSDL3/tamga_sdl3.zig
git commit -m "refactor: modernize tamga_sdl3.zig — flat RawEvent, remove getters and pollEventTag"
```

---

## Task 4: Modernize `tamga_sdl3.orh`

**Files:**
- Modify: `src/TamgaSDL3/tamga_sdl3.orh`

- [ ] **Step 1: Replace the file header**

Replace lines 1-6 (module declaration, `#name`, `#version`, `#build`, `#cimport`) with:

```
module tamga_sdl3

#version = (0, 2, 0)
#build   = static
```

- [ ] **Step 2: Replace `WindowHandle` type alias with handle declaration**

Replace `pub const WindowHandle: type = Ptr(u8)` (line 12) with:

```
pub handle WindowHandle
```

- [ ] **Step 3: Keep enums, event structs, TAG constants, Event type alias unchanged**

Lines 17-241 (WindowFlags bitfield, Scancode enum, MouseButton enum, event structs, TAG constants, Event type alias) — keep all of these. They are pure Orhon and correct.

Verify: `bitfield(u64)` syntax is still supported. Check `/home/yunus/Projects/orhon/orhon_compiler/docs/10-structs-enums.md` for current bitfield syntax. If bitfields moved to `std::bitfield`, update accordingly.

- [ ] **Step 4: Remove all bridge declarations**

Remove:
- `bridge struct RawEvent { ... }` block (lines 186-208)
- `pub bridge func pollEventTag() i32` (line 309)
- `pub bridge func getLastScancode() u32` (line 313)
- `pub bridge struct Window { ... }` block (lines 317-330)
- `pub bridge func initPlatform() ErrorUnion(void)` (line 335)
- `pub bridge func quitPlatform() void` (line 336)
- `pub bridge func getError() String` (line 337)
- `pub bridge func hideCursor() void` (line 341)
- `pub bridge func showCursor() void` (line 342)
- `pub bridge func openGamepad(id: u32) Ptr(u8)` (line 346)
- `pub bridge func closeGamepad(handle: Ptr(u8)) void` (line 347)
- `pub struct DisplayInfo { ... }` (lines 351-357) — keep if auto-mapper doesn't export it from Zig; remove if it does (check: the Zig `DisplayInfo` struct has all primitive pub fields, so it should auto-map)
- `pub bridge func getDisplayCount() i32` (line 359)
- `pub bridge func getDisplayInfo(index: i32) DisplayInfo` (line 360)
- `pub bridge func getTicksNS() u64` (line 364)
- `pub bridge func delayNS(ns: u64) void` (line 365)

All of these are now auto-mapped from the Zig module.

- [ ] **Step 5: Rewrite `pollEvent()` to use flat struct fields**

Replace the current `pollEvent()` implementation (lines 248-300). The logic stays the same but instead of calling getter methods (`raw.getTag()`, `raw.getKeyScancode()`, etc.), access struct fields directly (`raw.tag`, `raw.key_scancode`, etc.):

```
pub func pollEvent() Event {
    var raw = tamga_sdl3.createRawEvent()
    if(!tamga_sdl3.pollRawEvent(raw)) { return null }
    const tag = raw.tag
    const ts = raw.timestamp
    if(tag == TAG_NONE) { return null }
    if(tag == TAG_QUIT) {
        return QuitEvent(timestamp: ts)
    }
    if(tag == TAG_KEY_DOWN) {
        return KeyDownEvent(scancode: @cast(Scancode, raw.key_scancode), repeat: raw.key_repeat, timestamp: ts)
    }
    if(tag == TAG_KEY_UP) {
        return KeyUpEvent(scancode: @cast(Scancode, raw.key_scancode), repeat: raw.key_repeat, timestamp: ts)
    }
    if(tag == TAG_MOUSE_MOTION) {
        return MouseMotionEvent(x: raw.mouse_x, y: raw.mouse_y, xrel: raw.mouse_xrel, yrel: raw.mouse_yrel, timestamp: ts)
    }
    if(tag == TAG_MOUSE_BUTTON_DOWN) {
        return MouseButtonEvent(button: @cast(MouseButton, raw.mouse_button), down: true, x: raw.mouse_x, y: raw.mouse_y, timestamp: ts)
    }
    if(tag == TAG_MOUSE_BUTTON_UP) {
        return MouseButtonEvent(button: @cast(MouseButton, raw.mouse_button), down: false, x: raw.mouse_x, y: raw.mouse_y, timestamp: ts)
    }
    if(tag == TAG_GAMEPAD_AXIS) {
        return GamepadAxisEvent(gamepad_id: raw.gamepad_which, axis: raw.gamepad_axis, value: raw.gamepad_axis_value, timestamp: ts)
    }
    if(tag == TAG_GAMEPAD_BUTTON_DOWN) {
        return GamepadButtonEvent(gamepad_id: raw.gamepad_which, button: raw.gamepad_button, timestamp: ts)
    }
    if(tag == TAG_GAMEPAD_BUTTON_UP) {
        return GamepadButtonEvent(gamepad_id: raw.gamepad_which, button: raw.gamepad_button, timestamp: ts)
    }
    if(tag == TAG_GAMEPAD_ADDED) {
        return GamepadConnectedEvent(gamepad_id: raw.gamepad_which)
    }
    if(tag == TAG_GAMEPAD_REMOVED) {
        return GamepadDisconnectedEvent(gamepad_id: raw.gamepad_which)
    }
    if(tag == TAG_TEXT_INPUT) {
        return TextInputEvent(text: tamga_sdl3.RawEvent.getText(raw), timestamp: ts)
    }
    if(tag == TAG_WINDOW_RESIZED) {
        return WindowResizedEvent(width: raw.window_w, height: raw.window_h, timestamp: ts)
    }
    if(tag == TAG_WINDOW_PIXEL_RESIZED) {
        return WindowPixelResizedEvent(width: raw.pixel_w, height: raw.pixel_h, timestamp: ts)
    }
    if(tag == TAG_WINDOW_CLOSE) {
        return WindowCloseEvent(timestamp: ts)
    }
    return null
}
```

**Important:** The exact syntax for calling `pollRawEvent` with a mutable reference and accessing auto-mapped struct fields needs verification against the current compiler. The `pollRawEvent(out: *RawEvent)` takes a pointer — verify the Orhon calling convention. If the auto-mapper skips functions with `*RawEvent` (mutable pointer to struct), we may need to change the Zig signature to return the struct directly. Investigate during implementation.

- [ ] **Step 6: Verify `tamga_loop.orh` compiles**

Read `src/TamgaSDL3/tamga_loop.orh`. It's part of `module tamga_sdl3` and calls `pollEvent()`, `getTicksNS()`, `QuitEvent`, `WindowCloseEvent`. All of these still exist after modernization — `pollEvent()` is in the `.orh`, and `getTicksNS()` is auto-mapped from Zig. Should compile without changes.

- [ ] **Step 7: Build test**

Run: `orhon build`

This will likely fail (other modules still have bridge syntax), but check that tamga_sdl3 module errors are resolved. If the compiler reports errors in tamga_sdl3 specifically, fix them before proceeding.

- [ ] **Step 8: Commit**

```bash
git add src/TamgaSDL3/tamga_sdl3.orh
git commit -m "feat: modernize tamga_sdl3.orh — remove bridge syntax, add handle type, flat event dispatch"
```

---

## Task 5: Modernize `tamga_vulkan.zig`

**Files:**
- Modify: `src/TamgaVK/tamga_vulkan.zig`

- [ ] **Step 1: Remove bridge export functions**

Remove all `pub export fn` functions at the bottom of the file (lines 441-497):
- `vma_create`
- `vma_destroy`
- `vma_create_buffer`
- `vma_destroy_buffer`
- `vma_staging_write`

These were the old bridge ABI. The new module system auto-maps the struct methods directly.

- [ ] **Step 2: Rename `VmaContext` to `Allocator` and make it pub-API clean**

The struct is currently `pub const VmaContext`. Rename to `pub const Allocator` for a cleaner Orhon-facing name. Update the `create` signature to accept handle types:

```zig
pub const Allocator = struct {
    // ... (existing internal fields unchanged)

    pub fn create(instance: *anyopaque, physical_device: *anyopaque, device: *anyopaque) anyerror!Allocator {
        const vk_instance: c.VkInstance = @ptrCast(instance);
        const vk_phys: c.VkPhysicalDevice = @ptrCast(physical_device);
        const vk_device: c.VkDevice = @ptrCast(device);
        // ... (rest of existing create body, replacing self references)
    }
```

The `*anyopaque` params map to the corresponding Orhon handle types (`VkInstanceHandle`, etc.) because the `.orh` declares those handles.

- [ ] **Step 3: Update `BufferAlloc` and `StagingRegion` to use `*anyopaque`**

Change the public return types to use `*anyopaque` so they map to Orhon handles:

```zig
pub const BufferAlloc = struct {
    buffer: *anyopaque,      // maps to VkBufferHandle
    allocation: *anyopaque,  // maps to VmaAllocationHandle
};

pub const StagingRegion = struct {
    buffer: *anyopaque,      // maps to StagingBufferHandle
    offset: u32,
};
```

Note: these were previously `extern struct` — change to regular `struct` since they no longer need C ABI layout (they're returned by value through the auto-mapper now).

Update `createBuffer` return and `destroyBuffer` params to cast between `c.VkBuffer`/`VmaAllocation` and `*anyopaque` at the boundary:

```zig
pub fn createBuffer(self: *Allocator, size: u64, usage: u32, gpu_only: bool) anyerror!BufferAlloc {
    // ... existing implementation ...
    return BufferAlloc{
        .buffer = @ptrCast(buffer),
        .allocation = allocation_raw,
    };
}

pub fn destroyBuffer(self: *Allocator, buffer: *anyopaque, allocation: *anyopaque) void {
    const vk_buffer: c.VkBuffer = @ptrCast(buffer);
    const vma_alloc: VmaAllocation = @ptrCast(allocation);
    vmaDestroyBuffer(self.allocator, vk_buffer, vma_alloc);
}

pub fn stagingWrite(self: *Allocator, data: [*]const u8, size: u32) anyerror!StagingRegion {
    // ... existing implementation ...
    return StagingRegion{
        .buffer = @ptrCast(self.staging_buffer),  // or one-shot buffer
        .offset = write_offset,
    };
}
```

- [ ] **Step 4: Verify RenderGraph stays unchanged**

The `RenderGraph` struct (lines 499-768) is internal infrastructure used by `tamga_vk3d`. Its types use raw Vulkan types (`c.VkCommandBuffer`, etc.) which are unmappable — the auto-mapper will skip its methods, which is correct. It's accessed internally by the vk3d Zig module, not from Orhon. No changes needed.

- [ ] **Step 5: Commit**

```bash
git add src/TamgaVK/tamga_vulkan.zig
git commit -m "refactor: modernize tamga_vulkan.zig — Allocator with handle-typed API, remove bridge exports"
```

---

## Task 6: Modernize `tamga_vulkan.orh`

**Files:**
- Modify: `src/TamgaVK/tamga_vulkan.orh`

- [ ] **Step 1: Replace the entire file**

Replace all contents of `src/TamgaVK/tamga_vulkan.orh` with:

```
module tamga_vulkan

#version = (0, 2, 0)
#build   = static

// ---- Handle types ----
// Opaque pointers for Vulkan/VMA resources. Nominally typed — each handle
// is distinct at the type level. Cannot be dereferenced or cast in Orhon.

pub handle VkInstanceHandle
pub handle VkPhysicalDeviceHandle
pub handle VkDeviceHandle
pub handle VkBufferHandle
pub handle VmaAllocationHandle
pub handle StagingBufferHandle

// ---- BufferAlloc ----
// Returned by Allocator.createBuffer. Both fields are typed handles.

pub struct BufferAlloc {
    pub buffer: VkBufferHandle
    pub allocation: VmaAllocationHandle
}

// ---- StagingRegion ----
// Returned by Allocator.stagingWrite.

pub struct StagingRegion {
    pub buffer: StagingBufferHandle
    pub offset: u32
}
```

The `Allocator` struct with `create`, `destroy`, `createBuffer`, `destroyBuffer`, `stagingWrite` — all auto-mapped from `tamga_vulkan.zig`.

- [ ] **Step 2: Build test**

Run: `orhon build`

Check that tamga_vulkan module errors are resolved. Other modules may still have bridge syntax errors — that's expected.

- [ ] **Step 3: Commit**

```bash
git add src/TamgaVK/tamga_vulkan.orh
git commit -m "feat: modernize tamga_vulkan.orh — handle types, remove all bridge syntax"
```

---

## Task 7: Strip Chunk 4 from `tamga_vk3d.zig`

**Files:**
- Modify: `src/TamgaVK/TamgaVK3D/tamga_vk3d.zig`

- [ ] **Step 1: Identify Chunk 4 code**

The following functions and fields are incomplete Chunk 4 (compute pipeline for light culling). Read each section to confirm boundaries before removing:

Functions to remove:
- `createClusterResources` (line 1184)
- `destroyClusterResources` (line 1210)
- `createComputeResources` (line 1219)
- `allocateComputeDescriptorSets` (line 1340)
- `destroyComputeResources` (line 1424)

Fields to remove from `VulkanContext` struct: search for `compute_pipeline`, `compute_pipeline_layout`, `compute_descriptor_set_layout`, `compute_descriptor_sets`, `light_grid_ssbo`, `light_index_ssbo`, `depth_sampler`, and any cluster config fields.

Also remove any calls to these functions from `Renderer.create` and `Renderer.destroy` if they were wired in (check the Renderer struct methods).

- [ ] **Step 2: Remove the identified code**

Remove functions, fields, and any references. Keep `light_cull.comp.glsl` in `shaders3D/` for future reference.

- [ ] **Step 3: Verify the file still compiles conceptually**

Read through the remaining code to ensure no dangling references to removed fields or functions. Check that `buildRenderGraph` doesn't reference compute passes.

- [ ] **Step 4: Commit**

```bash
git add src/TamgaVK/TamgaVK3D/tamga_vk3d.zig
git commit -m "chore: strip Chunk 4 incomplete compute pipeline code — clean baseline"
```

---

## Task 8: Split `tamga_vk3d.zig` into modules

**Files:**
- Modify: `src/TamgaVK/TamgaVK3D/tamga_vk3d.zig`
- Create: `src/TamgaVK/TamgaVK3D/_vk3d_pipeline.zig`
- Create: `src/TamgaVK/TamgaVK3D/_vk3d_descriptors.zig`
- Create: `src/TamgaVK/TamgaVK3D/_vk3d_resources.zig`
- Create: `src/TamgaVK/TamgaVK3D/_vk3d_lighting.zig`
- Create: `src/TamgaVK/TamgaVK3D/_vk3d_rendergraph.zig`

This is the largest task. The split must preserve all functionality. Each private module (`_` prefix) is imported by `tamga_vk3d.zig` and not exposed to Orhon.

- [ ] **Step 1: Create `_vk3d_lighting.zig`**

Move from `tamga_vk3d.zig`:
- `MAX_LIGHTS`, `MAX_DIR_LIGHTS`, `MAX_POINT_LIGHTS`, `MAX_SPOT_LIGHTS` constants
- `LIGHT_TYPE_DIRECTIONAL`, `LIGHT_TYPE_POINT`, `LIGHT_TYPE_SPOT` constants
- `LightData` struct
- `LightSSBOHeader` struct
- Light-related fields from VulkanContext (light_ssbo, light data arrays, light counts)
- `flushLightSSBO` function
- Light setter logic (setDirLight, setPointLight, setSpotLight, setLightCounts)

The file needs access to Vulkan types and VMA. Import:
```zig
const c = @import("vulkan_c").c;
const vma = @import("tamga_vulkan_bridge");
```

Export a `LightingState` struct or keep functions that take `*VulkanContext` — the exact interface depends on how tightly coupled the lighting code is to VulkanContext. Read the code during implementation to determine the cleanest boundary.

- [ ] **Step 2: Create `_vk3d_descriptors.zig`**

Move from `tamga_vk3d.zig`:
- `CameraUBO` struct
- `MaterialUBOData` struct
- `createDescriptorSetLayouts`
- `createUBOs`, `destroyUBOs`
- `createDescriptorPool`
- `allocatePerFrameDescriptorSets`

- [ ] **Step 3: Create `_vk3d_pipeline.zig`**

Move from `tamga_vk3d.zig`:
- `createRenderPass`, `createDepthRenderPass`
- `createFramebuffers`, `createDepthFramebuffers`
- `createGraphicsPipeline`, `createDepthPipeline`
- `loadShaderModule`
- `createDepthResources`, `destroyDepthResources`
- `createMsaaColorResources`, `destroyMsaaColorResources`

- [ ] **Step 4: Create `_vk3d_resources.zig`**

Move from `tamga_vk3d.zig`:
- `MeshBuffers` struct
- `Texture` struct
- `Material` struct
- `createMeshBuffers`
- `textureLoad`, `textureFree`, `textureCreateDefault`
- `materialCreate`, `materialFree`
- `beginOneShot`, `submitOneShot`, `transitionImageLayout`

Add slot map arrays and ID-based lookup. The Renderer's public `createMesh`/`loadTexture`/`createMaterial` methods will call into this module and return IDs.

Define slot map storage:
```zig
pub const MAX_MESHES: u32 = 256;
pub const MAX_TEXTURES: u32 = 256;
pub const MAX_MATERIALS: u32 = 256;

pub var mesh_slots: [MAX_MESHES]?MeshBuffers = [_]?MeshBuffers{null} ** MAX_MESHES;
pub var texture_slots: [MAX_TEXTURES]?Texture = [_]?Texture{null} ** MAX_TEXTURES;
pub var material_slots: [MAX_MATERIALS]?Material = [_]?Material{null} ** MAX_MATERIALS;

pub fn allocMeshSlot(mesh: MeshBuffers) ?u32 { ... }
pub fn freeMeshSlot(id: u32) void { ... }
pub fn getMesh(id: u32) ?*MeshBuffers { ... }
// similar for texture and material
```

- [ ] **Step 5: Create `_vk3d_rendergraph.zig`**

Move from `tamga_vk3d.zig`:
- `depthPrepassCallback`
- `forwardPassCallback`
- `buildRenderGraph`
- `DrawCall` struct and `MAX_DRAW_CALLS` constant

- [ ] **Step 6: Update `tamga_vk3d.zig` to import private modules**

The anchor file becomes the Renderer struct + public API + VulkanContext struct. Add imports:

```zig
const pipeline = @import("_vk3d_pipeline.zig");
const descriptors = @import("_vk3d_descriptors.zig");
const resources = @import("_vk3d_resources.zig");
const lighting = @import("_vk3d_lighting.zig");
const rendergraph = @import("_vk3d_rendergraph.zig");
```

Replace direct function calls with module-qualified calls (e.g., `pipeline.createRenderPass(&ctx)`).

**Important:** VulkanContext likely needs to be visible to all private modules. Options:
1. Define VulkanContext in `tamga_vk3d.zig` and pass `*VulkanContext` to all functions
2. Move VulkanContext to a shared `_vk3d_types.zig`

Option 1 is simpler — the current code already passes `*VulkanContext` to all functions.

- [ ] **Step 7: Verify no dangling references**

Read through each new file. Every function that was moved must have its callsites updated in `tamga_vk3d.zig`. Every type used across files must be imported.

- [ ] **Step 8: Commit**

```bash
git add src/TamgaVK/TamgaVK3D/
git commit -m "refactor: split tamga_vk3d.zig into 6 focused modules"
```

---

## Task 9: Modernize `tamga_vk3d` public API

**Files:**
- Modify: `src/TamgaVK/TamgaVK3D/tamga_vk3d.zig` (Renderer struct)
- Modify: `src/TamgaVK/TamgaVK3D/tamga_vk3d.orh`

- [ ] **Step 1: Define ID types in the Zig Renderer**

In `tamga_vk3d.zig`, add ID structs that the auto-mapper will expose:

```zig
pub const MeshId = struct { id: u32 };
pub const TextureId = struct { id: u32 };
pub const MaterialId = struct { id: u32 };
```

- [ ] **Step 2: Update Renderer public methods to use IDs**

Change the Renderer's public API. Currently `createMesh` returns `Mesh` (a bridge struct wrapping MeshBuffers). Change to return `MeshId`:

```zig
pub fn createMesh(self: *Renderer, vertices: [*]const u8, vertex_byte_size: u32, indices: [*]const u8, index_count: u32) anyerror!MeshId {
    const mesh_buffers = resources.createMeshBuffers(...) catch return error.VulkanFailed;
    const slot_id = resources.allocMeshSlot(mesh_buffers) orelse return error.VulkanFailed;
    return MeshId{ .id = slot_id };
}

pub fn destroyMesh(self: *Renderer, id: MeshId) void {
    if (resources.getMesh(id.id)) |mesh| {
        // destroy buffers via VMA
        resources.freeMeshSlot(id.id);
    }
}
```

Similarly for `loadTexture` → `TextureId`, `createMaterial` → `MaterialId`.

Update `draw` to accept IDs:
```zig
pub fn draw(self: *Renderer, mesh: MeshId, material: MaterialId, model_matrix: [*]const f32) void {
    const mesh_data = resources.getMesh(mesh.id) orelse return;
    const mat_data = resources.getMaterial(material.id) orelse return;
    // ... add to draw call list using actual Vulkan handles from slot lookup
}
```

- [ ] **Step 3: Update Renderer.create to use cross-module WindowHandle**

The current signature is:
```zig
pub fn create(window_handle: @import("tamga_sdl3_bridge").WindowHandle, debug_mode: bool) anyerror!Renderer
```

Update the import to match the new module name (the Zig module is auto-discovered as `tamga_sdl3`, not `tamga_sdl3_bridge`):
```zig
const sdl = @import("tamga_sdl3");
// ...
pub fn create(window_handle: sdl.WindowHandle, debug_mode: bool) anyerror!Renderer
```

Verify the import name matches what the compiler generates. The `.zig` file is `tamga_sdl3.zig`, so the module name should be `tamga_sdl3`. Check `.orh-cache/` if needed.

- [ ] **Step 4: Modernize `tamga_vk3d.orh`**

Replace all contents of `src/TamgaVK/TamgaVK3D/tamga_vk3d.orh` with:

```
module tamga_vk3d

#version = (0, 2, 0)
#build   = static

// ---- Resource IDs ----
// Lightweight typed indices into the renderer's internal slot maps.
// Created by Renderer methods, passed back to draw/destroy calls.

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

Note: `MeshId`, `TextureId`, `MaterialId` are defined in BOTH the `.orh` and the `.zig`. The compiler should handle this — the `.orh` definition is the Orhon-authoritative one, and the Zig struct maps to it. If there's a conflict, remove the definition from one side. Investigate during implementation.

- [ ] **Step 5: Build test**

Run: `orhon build`

All three modules (tamga_sdl3, tamga_vulkan, tamga_vk3d) should now compile. If errors, fix them.

- [ ] **Step 6: Commit**

```bash
git add src/TamgaVK/TamgaVK3D/tamga_vk3d.zig src/TamgaVK/TamgaVK3D/tamga_vk3d.orh
git commit -m "feat: modernize tamga_vk3d — ID-based resource API, remove all bridge syntax"
```

---

## Task 10: Update test files

**Files:**
- Modify: `src/test/test_sdl3.orh`
- Modify: `src/test/test_vulkan.orh`

- [ ] **Step 1: Update `test_sdl3.orh`**

Read the file. It's already using typed event dispatch and correct patterns. Changes needed:
- Window.create flags: currently `0` — optionally use `WindowFlags` bitfield if the test needs flags
- Verify all `tamga_sdl3.` qualified accesses still resolve (enum names, struct names, function names)
- No bridge syntax to remove (it's pure Orhon in `module tamga_framework`)

Make any syntax adjustments needed. The file should compile with the modernized `tamga_sdl3` module.

- [ ] **Step 2: Rewrite `test_vulkan.orh`**

Replace the entire file. Key changes:
- Replace `pollEventTag()` / magic numbers with typed `pollEvent()` + `is` dispatch
- Replace magic window flag `268435456` with `tamga_sdl3.WindowFlags` usage (verify how bitfield values are passed — may need `.Vulkan` access or a numeric value from the bitfield)
- Replace `Mesh`, `Texture`, `Material` bridge structs with `MeshId`, `TextureId`, `MaterialId`
- Use `tamga_sdl3.Scancode.Escape` instead of magic `41`

```
module tamga_framework

import tamga_sdl3
import tamga_vk3d
import tamga_helper
import std::console

pub func run_vulkan_test() void {
    console.println("--- Vulkan Renderer Test (Texture + Material + Lighting) ---")

    const initResult = tamga_sdl3.initPlatform()
    if(initResult is Error) {
        console.println("Platform init failed:")
        console.println(tamga_sdl3.getError())
        return
    }
    defer { tamga_sdl3.quitPlatform() }

    console.println("SDL3 init: ok")

    // Create window with Vulkan flag
    const winResult = tamga_sdl3.Window.create("Vulkan Texture+Lighting Test", 800, 600, 268435456)
    if(winResult is Error) {
        console.println("Window creation failed:")
        console.println(tamga_sdl3.getError())
        return
    }
    var win = winResult.value
    defer { win.destroy() }

    console.println("Window created with Vulkan flag")

    const renResult = tamga_vk3d.Renderer.create(win.getHandle(), true)
    if(renResult is Error) {
        console.println("Vulkan renderer creation failed")
        return
    }
    var ren = renResult.value
    defer { ren.destroy() }

    console.println("Vulkan renderer: ok")
    ren.setClearColor(0.1, 0.1, 0.15, 1.0)

    const texResult = ren.loadTexture("assets/textures/test_texture.png")
    if(texResult is Error) {
        console.println("Texture load failed")
        return
    }
    const tex = texResult.value

    console.println("Texture loaded: ok")

    const matResult = ren.createMaterial(1.0, 0.8, 0.6, 1.0, 0.5, 32.0, tex)
    if(matResult is Error) {
        console.println("Material creation failed")
        ren.destroyTexture(tex)
        return
    }
    const mat = matResult.value

    console.println("Material created: ok")

    ren.setDirLight(0, -0.5, -1.0, -0.3, 1.0, 1.0, 0.9)
    ren.setSpotLight(0, 2.0, 1.0, 2.0, -1.0, -0.5, -1.0, 1.0, 0.8, 0.4, 0.3, 0.5, 10.0)
    ren.setLightCounts(1, 0, 1)

    console.println("Directional + spot light configured")

    const meshResult = ren.createMesh(tamga_helper.getTriangleVertices(), 144, tamga_helper.getTriangleIndices(), 3)
    if(meshResult is Error) {
        console.println("Mesh creation failed")
        ren.destroyMaterial(mat)
        ren.destroyTexture(tex)
        return
    }
    const mesh = meshResult.value

    console.println("Triangle mesh created")
    console.println("Window open — press ESC or close to quit")

    var running: bool = true

    while(running) {
        const ev = tamga_sdl3.pollEvent()
        if(ev is null) {
            if(ren.beginFrame()) {
                ren.setCamera(tamga_helper.getViewMatrix(), tamga_helper.getProjMatrix(), tamga_helper.getCameraPos())
                ren.draw(mesh, mat, tamga_helper.getIdentityMatrix())
                ren.endFrame()
            }
            tamga_sdl3.delayNS(16000000)
            continue
        }

        if(ev is tamga_sdl3.QuitEvent) {
            running = false
        }
        if(ev is tamga_sdl3.WindowCloseEvent) {
            running = false
        }
        if(ev is tamga_sdl3.KeyDownEvent) {
            const kd = ev.value
            if(kd.scancode == tamga_sdl3.Scancode.Escape) {
                running = false
            }
        }
    }

    ren.destroyMesh(mesh)
    ren.destroyMaterial(mat)
    ren.destroyTexture(tex)
    console.println("Test complete.")
}
```

**Note:** The window flags value `268435456` is `0x10000000` = `SDL_WINDOW_VULKAN`. Verify whether the `WindowFlags` bitfield from tamga_sdl3 can be used here. If the bitfield maps to a `u64` and the Window.create Zig function takes a `u64` flags param, we can use `WindowFlags.Vulkan` (or however bitfield values are accessed in current Orhon). If not, keep the numeric literal for now and log a compiler gap if needed.

**Note on createMaterial:** The current Zig `materialCreate` takes individual floats for diffuse RGBA + specular + shininess + a Texture pointer. With the ID system, it now takes a `TextureId`. Verify the Renderer's `createMaterial` public signature matches what the test passes.

- [ ] **Step 3: Build and run**

```bash
orhon build
orhon run
```

Expected: window opens, colored triangle renders with texture and Phong lighting, ESC quits cleanly.

- [ ] **Step 4: Commit**

```bash
git add src/test/test_sdl3.orh src/test/test_vulkan.orh
git commit -m "feat: update test files — typed events, ID-based resources, no bridge syntax"
```

---

## Task 11: Docs cleanup

**Files:**
- Modify: `docs/tech-stack.md`
- Modify: `docs/ideas.md`
- Modify: `docs/todo.md`

- [ ] **Step 1: Update `docs/tech-stack.md`**

Changes:
- Vulkan version: change "1.2 minimum (target 1.3+)" to "1.3 only (64-bit only)"
- "Supporting C Libraries (via Zig bridge)" section title: change to "Supporting C Libraries (via Zig modules)"
- "Module-to-Library Mapping" table: change "Bridge Sidecar" column to "Zig Module" and remove any bridge references
- Add a note about `.zon` files replacing `#cimport` for C dependency configuration
- Add a note about handle types for FFI boundary safety
- Vulkan version in "Alternatives Considered": update the entry about Vulkan version choice

- [ ] **Step 2: Update `docs/ideas.md`**

Remove or mark as implemented:
- "Multi-file Zig sidecars" — now solved by `_` prefix convention (private Zig files imported by the anchor)
- Keep Vulkan version discussion items (still relevant design rationale)
- Keep `#assets` directive idea (not yet implemented)
- Keep "Enforce same-folder rule" idea (not yet implemented)

- [ ] **Step 3: Rewrite `docs/todo.md`**

Replace with the current state reflecting the completed update:

```markdown
# Tamga Framework — Current Work

## Complete Update — Done

Design spec: `docs/superpowers/specs/2026-04-10-complete-update-design.md`

### Completed
- [x] Section 1: Module system migration (bridge/cimport → zon + auto-mapper)
- [x] Section 2: tamga_vk3d.zig split into 6 focused modules
- [x] Section 3: Handle/ID architecture (handles for cross-module, IDs for slots)
- [x] Section 4: Cross-module type passing (GAP-001 resolved)
- [x] Section 5: SDL3 module modernization
- [x] Section 6: Vulkan module modernization
- [x] Section 7: 3D renderer modernization
- [x] Section 8: Test file updates
- [x] Section 9: Docs cleanup and build verification

## Next Up

- [ ] Chunk 4: Light culling compute pass (fresh implementation)
- [ ] Chunk 5: Clustered forward shading
```

- [ ] **Step 4: Commit**

```bash
git add docs/tech-stack.md docs/ideas.md docs/todo.md
git commit -m "docs: update tech-stack, ideas, and todo for completed migration"
```

---

## Task 12: Final build verification

**Files:** None (verification only)

- [ ] **Step 1: Clean build**

```bash
orhon build
```

Expected: zero errors, zero warnings about tamga code (compiler warnings about its own internals are OK).

- [ ] **Step 2: Run the application**

```bash
orhon run
```

Expected: SDL3 window opens (800x600, "Vulkan Texture+Lighting Test"), colored triangle renders with texture and Phong lighting (directional + spot light), ESC key or window close quits cleanly.

- [ ] **Step 3: Verify no regressions**

Check:
- Window title displays correctly
- Triangle has correct vertex colors (red, green, blue corners)
- Texture is applied (2x2 checkerboard pattern visible)
- Lighting is visible (one directional, one spot — shading on the triangle)
- ESC key exits cleanly (no crash, no hung process)
- Window close button exits cleanly

- [ ] **Step 4: Check for new compiler gaps**

If any compiler shortcomings were discovered during implementation, verify they're logged in `docs/compiler-gaps.md`.

- [ ] **Step 5: Final commit (if any fixups needed)**

```bash
git add -A
git commit -m "fix: final fixups from build verification"
```

Only commit if there were actual fixes. Don't create an empty commit.
