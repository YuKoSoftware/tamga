# Compiler Bugs

All Phase 1 bugs (13 total) were fixed in Orhon compiler v0.14.2. See git history for details.

## Open

(none)

## Fixed (Phase 2)

- **build-gen: unused bridge module for `use std::collections`** — when a module uses `use std::collections`, the generated build.zig creates a `bridge_collections` module variable but never adds it as an import, causing Zig "unused local constant" error. Discovered 2026-04-01. Fixed in Orhon v0.14.2 — bridge module is now properly imported.

- **build-gen: `linkSystemLibrary` for `#cimport source:` libraries** — when a `#cimport` has a `source:` field (compiled from source), the generated build.zig still emits `linkSystemLibrary("name")` which fails because it's not a system library. Affects stb_image in tamga_vk3d. Discovered 2026-04-01. Fixed in Orhon v0.14.2 — no spurious `linkSystemLibrary` emitted for source-compiled cimports.
