# Tamga

A multimedia framework written in [Orhon](https://github.com/YourRepo/orhon), currently serving as a testbed for the Orhon compiler. Not usable as a framework yet.

## Status

Early development. Most modules are empty scaffolding. The primary purpose right now is to stress-test the Orhon compiler with real-world code and surface bugs.

What exists so far:
- **TamgaSDL3** — SDL3 window, input, and event handling
- **TamgaVK3D** — Vulkan 3D renderer (barebones clear-screen)

What's planned but not started:
- TamgaVK2D, TamgaAudio, TamgaECS, TamgaPhysics, TamgaGUI, TamgaGOAP, TamgaPack

## Building

Requires the Orhon compiler, SDL3, and Vulkan SDK headers installed.

```bash
orhon build
orhon run
```

## License

TBD
