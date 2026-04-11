# Language Ideas

- minimum version Vulkan 1.2 justification: 
minimum Vulkan 1.2 is the lowest version that natively includes the core features required for a modern renderer without heavy reliance on extensions. It brings descriptor indexing (enabling bindless-style resource access), timeline semaphores for robust synchronization, and buffer device address for GPU-driven techniques. This makes it a practical baseline if you still care about broader hardware compatibility while avoiding outdated design patterns.

- minimum version Vulkan 1.3 — justification:
Vulkan 1.3 is justified as the default target because it significantly simplifies engine architecture while aligning with modern GPU workflows. Features like dynamic rendering remove render pass complexity, and synchronization2 provides a cleaner, less error-prone model for GPU sync. It reduces boilerplate, eliminates many legacy constraints, and allows you to design a renderer around current best practices rather than compatibility workarounds.

- Enforce same-folder rule for module files: require all `.orh` files declaring the same `module` to live in the same directory as the anchor file. Currently the compiler groups by declaration regardless of path, but every project follows same-folder convention anyway. Enforcing it improves discoverability (`ls` shows all module files), makes tooling trivial (infer module from path), and catches mistyped `module` declarations. The anchor file rule already ties modules to directories implicitly — this just closes the loop.

- Multi-file Zig sidecars: allow a module's sidecar `.zig` file to `@import` additional `.zig` files from the same source directory. Currently the compiler only copies the anchor-matching `.zig` file to the generated directory, and Zig blocks imports outside the module path. The compiler should either copy referenced `.zig` files alongside the sidecar or widen the Zig module path to include the source directory. Without this, large bridge implementations cannot be split into logical units. Discovered 2026-04-01.
  - **Resolved:** private `_`-prefixed Zig files (e.g., `_device.zig`, `_pipelines.zig`) are imported by the anchor module and not auto-mapped to Orhon. Used in tamga_vk3d split.

- `#assets` directive for copying runtime dependencies to build output: `#assets = "src/test/assets"` in the anchor file would copy the directory to `bin/assets/` on build. Code then uses exe-relative paths like `"assets/test_texture.png"`. Shaders and small data should still be embedded (compile-time, zero runtime deps), but textures, models, audio, and configs are too large and too frequently iterated on to embed — they need copy-to-build-site. This also enables hot-reloading later (edit asset, re-run without rebuild).
