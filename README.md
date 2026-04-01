# Tamga

A multimedia framework written in [Orhon](https://github.com/YuKoSoftware/orhon), currently serving as a testbed for the Orhon compiler. Not usable as a framework yet.

## Status

Early development. The primary purpose right now is to stress-test the Orhon compiler with real-world code and surface bugs.

What exists so far:
- **TamgaSDL3** — SDL3 window, input, typed event dispatch, game loop
- **TamgaVK3D** — Vulkan 3D renderer with textures, materials, and Phong lighting
- **TamgaVK** — VMA-backed GPU memory allocator

What's planned but not started:
- TamgaVK2D, TamgaAudio, TamgaGUI

## Building

Requires the Orhon compiler (v0.14.2+), Zig 0.15.2+, SDL3, and Vulkan SDK.

```bash
orhon build
orhon run
```

