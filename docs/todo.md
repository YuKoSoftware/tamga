# Tamga Framework — Current Work

## Clustered Forward Renderer (Wave 4)

Design spec: `docs/superpowers/specs/2026-04-01-clustered-forward-render-graph-design.md`

### Completed

**Chunk 1: Render graph library**
- RenderGraph struct in `tamga_vulkan.zig` (callback-based pass execution, auto barrier insertion)
- Draw calls collected into a list in VulkanContext, executed by graph during endFrame
- `forwardPassCallback` records all queued draws
- Graph rebuilt on swapchain resize

**Chunk 2: Light SSBO migration + spot lights**
- Replaced fixed LightUBO (4 dir + 8 point, 528 bytes) with variable SSBO (up to 256 lights)
- Unified `LightData` struct (80 bytes, 5x vec4): position_range, direction_type, color, attenuation, spot_params
- Type field distinguishes directional (0), point (1), spot (2)
- Blinn-Phong replaces Phong in `mesh.frag.glsl`
- Added `setSpotLight` bridge function, `setLightCounts` now takes 3 params (dir, point, spot)
- Descriptor set 0 binding 1 changed from UNIFORM_BUFFER to STORAGE_BUFFER

**Chunk 3: Depth prepass**
- Depth-only render pass (`createDepthRenderPass`) + framebuffers (`createDepthFramebuffers`)
- Depth pipeline (`createDepthPipeline`) — vertex-only, no color attachments, depth LESS + write
- `depthPrepassCallback` iterates draw list with depth pipeline (no material binding)
- Forward render pass loads depth (LOAD, not CLEAR), depth test EQUAL + write disabled (zero overdraw)
- Image barrier between depth prepass and forward pass (depth write → depth read)
- Depth image has SAMPLED_BIT usage (for future compute sampling)
- Forward pass uses DEPTH_STENCIL_READ_ONLY_OPTIMAL layout

### In Progress — Chunk 4: Light Culling Compute Pass

**What's done:**
- `light_cull.comp.glsl` written and compiled to `assets/shaders/light_cull.comp.spv`
  - 16x16 workgroups, phase 1 depth reduction (atomicMin/Max), phase 2 light-cluster intersection
  - Push constants for cluster config (tiles_x/y, depth_slices, near/far, screen dims, sample_count)
  - Reads: depth texture (sampler2DMS), camera UBO, light SSBO
  - Writes: light grid SSBO (uvec2 per cluster), light index list SSBO (atomic counter + flat array)
- VulkanContext fields added: compute_pipeline, compute_pipeline_layout, compute_descriptor_set_layout, compute_descriptor_sets, light_grid_ssbo, light_index_ssbo, depth_sampler, cluster config
- Zig functions written: createClusterResources, destroyClusterResources, createComputeResources, allocateComputeDescriptorSets, destroyComputeResources
- Set 0 stage flags updated to include COMPUTE_BIT
- Descriptor pool updated with STORAGE_BUFFER pool size

**What's NOT done:**
- Compute callback function (`lightCullCallback`) — needs to: clear atomic counter, bind compute pipeline + descriptors, push cluster config constants, dispatch workgroups
- Wire compute pass into `buildRenderGraph` between depth prepass (pass 0) and forward (pass 1)
- Update `endFrame` to set user_data for pass 2 (compute)
- Wire createClusterResources + createComputeResources + allocateComputeDescriptorSets into Renderer.create
- Wire destroy/cleanup into Renderer.destroy and cleanupSwapchain/recreateSwapchain
- Update depth prepass barrier: transition to DEPTH_STENCIL_READ_ONLY_OPTIMAL (for compute sampling)
- Add barrier after compute: cluster SSBOs COMPUTE_WRITE → FRAGMENT_READ (prep for Chunk 5)
- Build and test

**Blocker discovered:** tamga_vk3d.zig is 3200+ lines and growing. Zig sidecar files can't be split (compiler copies only the anchor-matching .zig to generated dir, and Zig blocks @import outside module path). Logged in `docs/ideas.md` as "multi-file Zig sidecars." Options: move compute infra to tamga_vulkan module, or accept large file until compiler adds support.

### Pending — Chunk 5: Clustered Forward Shading + Cleanup

- Write `forward.vert.glsl` and `forward.frag.glsl` with cluster lookup
- Forward fragment shader: compute cluster index from gl_FragCoord, read light grid, iterate assigned lights
- Add descriptor set 2 to forward pipeline layout (light grid + light index list SSBOs, read-only fragment)
- Replace old mesh shaders with new forward shaders
- Delete old `mesh.vert.glsl` and `mesh.frag.glsl`
- Bump tamga_vk3d version
- Full integration test

## Project Structure

```
src/TamgaVK/
  tamga_vulkan.orh/zig     — VMA allocator + render graph + (future: compute helpers)
  libs/                    — vulkan headers, vk_mem_alloc.h, vma_impl.cpp
  shaders3D/               — shader source (.glsl only)
  TamgaVK3D/               — tamga_vk3d module (3D renderer, 3200+ lines)
  TamgaVK2D/               — future 2D renderer
  TamgaVKCompute/          — future compute utilities
assets/
  shaders/                 — compiled .spv (runtime)
  textures/                — textures
  models/sponza/           — glTF test scene (gitignored, licensed)
```
