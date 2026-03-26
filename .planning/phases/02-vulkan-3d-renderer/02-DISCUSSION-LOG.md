# Phase 2: Vulkan 3D Renderer - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-03-26
**Phase:** 02-vulkan-3d-renderer
**Areas discussed:** Render graph design, Geometry submission API, VMA integration strategy, Shader & pipeline management

---

## Render Graph Design

### Pass declaration model

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit pass objects | Named GraphicsPass/ComputePass objects, declare read/write attachments, graph sorts and inserts barriers | Y |
| Builder pattern | Fluent API: graph.addPass().writes().reads().build() | |
| Callback registration | Register render callbacks with resource declarations | |

**User's choice:** Explicit pass objects
**Notes:** None

### Attachment ownership

| Option | Description | Selected |
|--------|-------------|----------|
| Graph owns attachments | Declare by name + format + size policy. Graph allocates via VMA, handles resize | Y |
| User manages, graph references | User creates attachments manually, passes handles | |
| Hybrid | Graph owns transient, user owns persistent | |

**User's choice:** Graph owns attachments
**Notes:** None

### Pass types in scope

| Option | Description | Selected |
|--------|-------------|----------|
| Graphics + Compute | Full graphics and compute passes. Matches VK3-12/VK3-15 | Y |
| Graphics only, compute stub | Graphics full, compute definition only | |
| Graphics + Compute + Transfer | Also explicit transfer passes | |

**User's choice:** Graphics + Compute
**Notes:** None

---

## Geometry Submission API

### Submission model

| Option | Description | Selected |
|--------|-------------|----------|
| Mesh object model | Create Mesh from vertex/index data, bind Material, submit draw(mesh, material, transform) | Y |
| Immediate draw calls | Push vertex data per frame, no caching | |
| Command buffer recording | User records draw commands into list | |

**User's choice:** Mesh object model
**Notes:** None

### Vertex format

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed standard format | position(vec3), normal(vec3), UV(vec2), color(vec4) | Y |
| Configurable vertex attributes | User declares layout via descriptors | |
| Multiple preset formats | 2-3 presets (PosOnly, PosNormUV, etc.) | |

**User's choice:** Fixed standard format
**Notes:** None

### Material model

| Option | Description | Selected |
|--------|-------------|----------|
| Simple material struct | Texture ref + Phong properties. One pipeline per material type | Y |
| Material + shader pair | Material binds to specific shader program | |
| Descriptor-set based | Materials map to Vulkan descriptor sets | |

**User's choice:** Simple material struct
**Notes:** None

---

## VMA Integration Strategy

### Bridge architecture

| Option | Description | Selected |
|--------|-------------|----------|
| Shared tamga_vma module | Single allocator shared by VK3D and VK2D. One memory pool, unified staging | Y |
| Single VMA sidecar in VK3D | Simplest now, but double pools when VK2D arrives | |
| VMA in platform layer | Centralized but breaks platform/renderer separation | |

**User's choice:** Shared tamga_vma module
**Notes:** User requested detailed pro/con analysis with performance and future feature considerations before deciding. Key factor: avoiding fragmented memory pools when VK2D arrives.

### Staging strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Ring buffer staging | Single large persistent staging buffer (8-16MB), ring allocation | Y |
| Per-upload staging | Temporary buffer per upload, VMA pooling | |
| You decide | Claude's discretion | |

**User's choice:** Ring buffer staging
**Notes:** None

---

## Shader & Pipeline Management

### Shader loading

| Option | Description | Selected |
|--------|-------------|----------|
| Runtime .spv loading | Load SPIR-V files at init. Hot-reload, custom shader ready | Y |
| Embedded SPIR-V blobs | @embedFile, zero I/O, single binary | |
| Both with compile-time switch | Debug=load, Release=embed | |

**User's choice:** Runtime .spv loading
**Notes:** User requested detailed pro/con analysis with performance, future upgrades and features in mind. Key factors: hot-reload dev experience, custom shader extensibility at engine layer.

### Uniform data strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Push constants + UBO split | Push constants for per-draw transforms, UBO for scene (camera, lights) | Y |
| All UBOs | Everything in uniform buffers | |
| Push constants only | Everything via push constants (128-256B limit) | |

**User's choice:** Push constants + UBO split
**Notes:** None

### Pipeline cache persistence

| Option | Description | Selected |
|--------|-------------|----------|
| File-backed cache | Serialize to disk on shutdown, load on startup | Y |
| Memory-only cache | Rebuilt each run | |
| You decide | Claude's discretion | |

**User's choice:** File-backed cache
**Notes:** None

---

## Claude's Discretion

- Descriptor set layout design
- Debug geometry rendering approach
- Depth prepass integration
- MSAA resolve management
- Swapchain recreation flow
- .spv file location convention
- Ring buffer sizing and overflow

## Deferred Ideas

None
