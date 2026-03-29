# Tamga

A multimedia framework written in [Orhon](https://github.com/YuKoSoftware/orhon), currently serving as a testbed for the Orhon compiler. Not usable as a framework yet.

## Status

Early development. The primary purpose right now is to stress-test the Orhon compiler with real-world code and surface bugs.

What exists so far:
- **TamgaSDL3** — SDL3 window, input, typed event dispatch, game loop
- **TamgaVK3D** — Vulkan 3D renderer with textures, materials, and Phong lighting
- **TamgaVulkan** — VMA-backed GPU memory allocator

What's planned but not started:
- TamgaVK2D, TamgaAudio, TamgaGUI

## Building

Requires the Orhon compiler, SDL3, and Vulkan SDK headers installed.

```bash
orhon build
orhon run
```

## License

TBD
