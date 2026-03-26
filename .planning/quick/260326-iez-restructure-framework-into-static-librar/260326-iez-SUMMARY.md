# Quick Task 260326-iez Summary

**One-liner:** Restructured tamga_sdl3 and tamga_vk3d as #build = static libraries with v0.1.0 versioning; main.orh is test harness only

**Date:** 2026-03-26
**Commit:** 32b7d2b

## Changes

| File | Change |
|------|--------|
| `src/TamgaSDL3/tamga_sdl3.orh` | Added `#name`, `#version = Version(0, 1, 0)`, `#build = static` |
| `src/TamgaVK3D/tamga_vk3d.orh` | Added `#name`, `#version = Version(0, 1, 0)`, `#build = static` |
| `src/main.orh` | Changed name to `tamga_test`, version to `0.1.0` — test harness only |
| `.planning/STATE.md` | Milestone version `v1.0` -> `v0.1` |
