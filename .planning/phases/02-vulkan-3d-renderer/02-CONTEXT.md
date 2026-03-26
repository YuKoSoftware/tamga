# Phase 2: Vulkan 3D Renderer - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

A developer can submit arbitrary 3D geometry with textures and lighting, resize the window without a crash, and get correct depth-tested output -- with a render graph that supports compute passes and deferred rendering at the engine layer.

Requirements: VK3-01 through VK3-16.

</domain>

<decisions>
## Implementation Decisions

### Render Graph Design
- **D-01:** Explicit pass objects -- user creates named pass objects (GraphicsPass, ComputePass), declares read/write attachments per pass. Graph sorts topologically and inserts Vulkan barriers automatically.
- **D-02:** Graph owns all attachments -- render targets declared by name + format + size policy (e.g., swapchain-relative). Graph allocates via VMA and handles resize. User never touches VkImage for intermediate targets.
- **D-03:** Graphics + Compute passes both fully implemented in Phase 2. Compute pass slots are callable from the engine layer (VK3-12, VK3-15).

### Geometry Submission API
- **D-04:** Mesh object model -- user creates Mesh objects from vertex/index data, binds a Material, submits draw commands: `renderer.draw(mesh, material, transform)`. Clean separation of data and rendering.
- **D-05:** Fixed standard vertex format: position (vec3), normal (vec3), UV (vec2), color (vec4). Covers Phong-lit textured meshes. Engine layer can extend later.
- **D-06:** Simple material struct -- holds texture reference + Phong lighting properties (diffuse color, specular, shininess). One pipeline per material type. User-facing, no Vulkan concepts exposed.

### VMA Integration
- **D-07:** Shared `tamga_vma` module -- single VMA allocator shared by VK3D and future VK2D. Thin module: VMA init/destroy + allocator handle. Both renderers allocate from the same memory pool.
- **D-08:** Ring buffer staging -- single large persistently-mapped staging buffer (8-16MB) used as a ring. Uploads write into the ring, GPU reads behind. Zero allocation overhead per upload.

### Shader & Pipeline Management
- **D-09:** Runtime .spv file loading -- load SPIR-V files at renderer init. Enables hot-reload during development, ready for custom shaders and engine-layer material system.
- **D-10:** Push constants for per-draw transforms, UBO for per-frame/per-scene data (camera, lights). Standard split for performance.
- **D-11:** File-backed pipeline cache -- serialize VkPipelineCache to disk on shutdown, reload on startup. Cache directory user-configurable.

### Claude's Discretion
- Descriptor set layout design (per-frame vs per-material vs per-object binding frequency)
- Debug geometry rendering implementation approach (VK3-09)
- Depth prepass integration strategy (VK3-13)
- MSAA resolve attachment management (VK3-07)
- Swapchain recreation flow on resize (VK3-06)
- Exact .spv file location convention and search path
- Ring buffer size and overflow strategy

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing VK3D Prototype
- `src/TamgaVK3D/tamga_vk3d.orh` -- Current public API: Renderer bridge struct with create/destroy/beginFrame/endFrame/setClearColor
- `src/TamgaVK3D/tamga_vk3d.zig` -- Zig sidecar: VulkanContext struct, instance/device/swapchain creation, render pass, framebuffers, command buffers, double-buffered sync, RenderGraph stub

### Platform Layer (Phase 1 output)
- `src/TamgaSDL3/tamga_sdl3.orh` -- WindowHandle type alias, Window bridge struct, Event union type, initPlatform
- `src/TamgaSDL3/tamga_sdl3.zig` -- SDL3 C bridge including SDL_Vulkan_CreateSurface and SDL_Vulkan_GetInstanceExtensions

### Integration Tests
- `src/test/test_vulkan.orh` -- Current VK3D test: window creation, renderer create/destroy, beginFrame/endFrame loop

### Requirements
- `.planning/REQUIREMENTS.md` -- VK3-01 through VK3-16 acceptance criteria

### Bug Tracking
- `docs/bugs.txt` -- Known compiler bugs (3 open: null|union collapse, cast enum, empty struct)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `tamga_vk3d.zig` VulkanContext: instance creation, physical device selection, logical device, swapchain, render pass, framebuffers, command pool/buffers, double-buffered sync -- all working and validated
- `tamga_vk3d.zig` RenderGraph stub: minimal pass execution framework, ready to be expanded into full declarative graph
- `tamga_vk3d.zig` debug messenger: validation layer support with severity-based logging
- `tamga_sdl3.zig` Vulkan surface: SDL_Vulkan_CreateSurface and GetInstanceExtensions working

### Established Patterns
- Bridge pattern: `.orh` declares bridge types, `.zig` implements via @cImport. Confirmed working for both SDL3 and Vulkan.
- `#linkC "vulkan"` and `#linkC "SDL3"` directives confirmed working
- Cross-module type references work: tamga_vk3d imports tamga_sdl3.WindowHandle
- Error unions on bridge functions: `(Error | Renderer)` pattern established

### Integration Points
- WindowHandle from tamga_sdl3 consumed by Renderer.create for Vulkan surface creation
- New tamga_vma module will be consumed by both tamga_vk3d and future tamga_vk2d
- Existing test_vulkan.orh provides the integration test pattern to extend

</code_context>

<specifics>
## Specific Ideas

- User asked for detailed pro/con analysis on VMA integration options -- performance and future feature impact are important decision factors
- User asked for detailed pro/con analysis on shader loading -- hot-reload and custom shader extensibility valued over zero-I/O simplicity
- Shared VMA module chosen specifically to avoid memory pool fragmentation when VK2D arrives in Phase 4
- Ring buffer staging chosen for zero-allocation-per-upload performance

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 02-vulkan-3d-renderer*
*Context gathered: 2026-03-26*
