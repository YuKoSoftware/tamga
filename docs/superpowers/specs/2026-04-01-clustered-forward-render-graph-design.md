# Clustered Forward Render Graph — Design Spec

**Date:** 2026-04-01
**Scope:** tamga_vk3d Wave 4 — replace single-pass Phong renderer with clustered forward pipeline

## Overview

Three-pass clustered forward rendering pipeline, managed by an internal render graph
in tamga_vk3d. The graph declares passes, resource dependencies, and barriers at init time.
Per-frame execution flows: depth prepass → light culling compute → forward shading.

Target: maximum performance forward renderer supporting hundreds of dynamic lights
(point, spot, directional) with zero overdraw and compute-based light culling.

## Render Graph Architecture

The render graph is an internal system inside tamga_vk3d. It replaces the current
hardcoded render pass with a declarative pass/resource structure.

### Structure

```
RenderGraph
  ├── Pass declarations (ordered)
  │   ├── DepthPrepass    (graphics, depth-only)
  │   ├── LightCulling    (compute)
  │   └── ForwardShading  (graphics, color + depth read)
  │
  ├── Resource declarations (graph-owned)
  │   ├── depth_buffer     (written by DepthPrepass, read by LightCulling + ForwardShading)
  │   ├── cluster_grid     (SSBO, written by LightCulling, read by ForwardShading)
  │   ├── light_list       (SSBO, written by LightCulling, read by ForwardShading)
  │   ├── msaa_color       (written by ForwardShading)
  │   └── resolve_target   (swapchain image, resolved from msaa_color)
  │
  └── Barrier insertion (automatic, derived from resource read/write declarations)
```

### Key Design Choices

- **Baked at init** — graph compiled at renderer creation and swapchain resize, not per-frame.
  Pass structure is static; only data flowing through passes changes each frame.
- **Concrete pass structs** — GraphicsPass and ComputePass are concrete structs with execute
  callbacks, not dynamic polymorphism.
- **Auto barriers** — each resource declares its writers and readers. The graph inserts
  vkCmdPipelineBarrier between passes automatically.
- **Separate VkRenderPasses** — depth prepass and forward shading are separate render passes,
  not subpasses. The compute pass must run between them (breaks subpass chains), and separate
  passes are simpler for the graph model and portable across all hardware.
- **Graph-owned resources** — all resources except the swapchain image are allocated and
  destroyed by the graph.

## Pass 1: Depth Prepass

Renders all opaque geometry with a depth-only pipeline.

- **Vertex shader:** transforms position by model/view/projection (same vertex format, only
  position consumed)
- **Fragment shader:** empty (depth write is automatic)
- **Depth test:** LESS, write enabled
- **Color attachments:** none
- **MSAA:** matches forward pass sample count (depth buffer reusable)
- **Output:** populated depth buffer with closest opaque surfaces

The renderer iterates the same mesh list twice (depth prepass + forward). No extra user
API needed — draw() collects meshes, graph executes both passes.

Separate VkPipeline with no fragment output and no color blend state.

### Why Separate

- Compute pass needs min/max depth per cluster tile — requires complete depth buffer
- Forward pass runs depth-test EQUAL with write disabled — zero overdraw
- Net cost: extra vertex pass. Net gain: zero overdraw + tight cluster depth bounds.

## Pass 2: Light Culling Compute

Reads the depth buffer, divides the frustum into 3D clusters, assigns lights to clusters.

### Cluster Grid

- Screen divided into 2D tiles (default 16x16 pixels)
- Depth divided into slices using exponential distribution (near-dense, far-sparse)
- Grid dimensions: `ceil(width/16) x ceil(height/16) x 24 slices`
- For 1920x1080: 120 x 68 x 24 = ~196K clusters
- Configurable at renderer init (tile size, slice count)

### Inputs

- **Depth buffer** (sampler2D, from prepass) — min/max depth per tile
- **Light buffer** (SSBO) — all active lights, uploaded once per frame. Per-light struct:
  position, radius, color, type (point/spot), direction + inner/outer angles (spot).
  Default max 256 lights, configurable.
- **Camera data** (UBO) — inverse projection matrix for view-space cluster bounds

### Outputs

- **Light grid** (SSBO) — per-cluster uint2: offset into light index list + count
- **Light index list** (SSBO) — flat array of light indices with global atomic counter.
  Sized with reasonable cap (e.g. 1M entries = 4MB). Clusters that overflow silently cap.

### Compute Dispatch

Two-phase within one dispatch:

1. **Depth reduction:** one workgroup per tile, threads sample depth buffer,
   atomicMin/Max in shared memory for tile min/max depth
2. **Light assignment:** threads divided across depth slices per tile, test each light's
   bounding sphere (point) or cone (spot) against cluster AABB, append to light index
   list with atomic counter

Workgroup size: 16x16x1

## Pass 3: Forward Shading

Main color pass. Renders all opaque geometry with full material shading, sampling the
cluster light grid per-fragment.

### Pipeline

- **Vertex shader:** same as current (model/view/projection, pass through normal/uv/color)
- **Fragment shader:** computes cluster index from gl_FragCoord, reads light grid, iterates
  assigned lights, accumulates Blinn-Phong
- **Depth test:** EQUAL, write disabled (zero overdraw — prepass wrote correct depth)
- **Color attachment:** MSAA color, resolves to swapchain image

### Cluster Lookup (fragment shader)

```
tile = ivec2(gl_FragCoord.xy) / tile_size
slice = int(log(depth / near) * scale)
cluster_index = tile.x + tile.y * grid_width + slice * grid_width * grid_height
light_data = light_grid[cluster_index]  // offset + count
for i in 0..light_data.count:
    light = lights[light_index_list[light_data.offset + i]]
    accumulate shading
```

### Shading Model: Blinn-Phong

Replaces current Phong:
- Current: `reflect(-lightDir, normal)` dot `viewDir`
- New: `normalize(lightDir + viewDir)` dot `normal`
- Cheaper (no reflect), more physically plausible at grazing angles

### Light Types

- **Directional:** skip clustering, always applied to all fragments. Direction + color.
- **Point:** position + color + quadratic attenuation (constant/linear/quadratic) + range.
  Culled against cluster AABB via bounding sphere.
- **Spot:** point light + direction + inner/outer cone angles. Smooth falloff via
  `smoothstep(cos(outer), cos(inner), cos(theta))`. Culled against cluster AABB via
  bounding cone.

### Descriptor Layout

- Set 0: camera UBO + light SSBO (SSBO replaces current light UBO for variable count)
- Set 1: per-material UBO + texture sampler (unchanged)
- Set 2: light grid SSBO + light index list SSBO (read-only in fragment)
- Push constants: model matrix (unchanged, 64 bytes, vertex stage)

### Transparency

Not in scope. Transparent objects require a separate forward pass after the clustered
opaque pass. The render graph architecture supports adding this as a 4th pass later.

## Resource Lifecycle & Barriers

### Allocation

All graph resources allocated at graph build time (renderer init / swapchain resize).
Double-buffered where needed: light SSBO (CPU writes frame N while GPU reads frame N-1).
Cluster SSBOs can alias per-frame since compute finishes before forward reads.

### SSBO Sizing

| Buffer | Size |
|--------|------|
| Light buffer | 256 x sizeof(LightData), resized via setMaxLights() |
| Light grid | num_clusters x 8 bytes (uint2 per cluster) |
| Light index list | 1M entries x 4 bytes = 4MB (global atomic counter, capped) |

### Barrier Schedule

| Transition | Src Stage | Dst Stage | Access |
|------------|-----------|-----------|--------|
| After depth prepass | LATE_FRAGMENT_TESTS | COMPUTE_SHADER | DEPTH_WRITE -> SHADER_READ |
| After light culling | COMPUTE_SHADER | FRAGMENT_SHADER | SHADER_WRITE -> SHADER_READ |
| After forward shading | COLOR_ATTACHMENT_OUTPUT | BOTTOM_OF_PIPE | COLOR_WRITE -> MEMORY_READ |

Depth buffer layout transition: DEPTH_STENCIL_ATTACHMENT_OPTIMAL -> SHADER_READ_ONLY_OPTIMAL
(between prepass and compute), then back to DEPTH_STENCIL_READ_ONLY_OPTIMAL for forward pass.

### Swapchain Resize

Graph detects resize via VK_ERROR_OUT_OF_DATE_KHR, rebuilds all graph-owned resources at
new dimensions, recomputes cluster grid dimensions.

## Shaders

Five shader files replace the current two (mesh.vert.glsl, mesh.frag.glsl):

| File | Type | Purpose |
|------|------|---------|
| depth_prepass.vert.glsl | Vertex | Position transform only |
| depth_prepass.frag.glsl | Fragment | Empty (depth write automatic) |
| light_cull.comp.glsl | Compute | Depth reduction + light-to-cluster assignment |
| forward.vert.glsl | Vertex | Full vertex transform + attribute passthrough |
| forward.frag.glsl | Fragment | Cluster lookup + Blinn-Phong + texture sampling |

Old mesh.vert.glsl and mesh.frag.glsl are deleted.

All shaders compiled to .spv via glslangValidator, stored in assets/shaders/, loaded at runtime.

## API Changes

### Unchanged

- Renderer.create(), destroy()
- beginFrame(), endFrame()
- draw(mesh, material, model_matrix)
- createMesh(), destroyMesh()
- loadTexture(), destroyTexture()
- createMaterial(), destroyMaterial()
- setCamera()

### Modified (internal only, same signatures)

- setDirLight() — writes to SSBO instead of UBO
- setPointLight() — writes to SSBO instead of UBO
- setLightCounts() — writes to SSBO instead of UBO

### New

- `setSpotLight(index, pos_x, pos_y, pos_z, dir_x, dir_y, dir_z, r, g, b, inner_angle, outer_angle, range)` — spot light support
- `setMaxLights(max: i32)` — optional, resizes light buffer. Default 256. Must call before first frame.
- `setClusterConfig(tile_size: i32, depth_slices: i32)` — optional, overrides 16px/24 slices default. Must call before first frame.

### Internal (not exposed)

Render graph, pass objects, cluster SSBOs, barrier management — all internal to Zig
implementation. User calls beginFrame -> draw -> endFrame as before.

### Test Update

test_vulkan.orh updated to add a spot light alongside the existing directional light.

## Scope Notes

- Depth prepass pulled from Wave 5 into this wave (architecturally required for cluster bounds)
- Wave 5 becomes: pipeline cache + debug geometry
- Transparency (separate forward pass) is a future addition, not this wave
