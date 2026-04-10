# Compiler Gaps

Shortcomings discovered during tamga development that need to be addressed in orhon_compiler.
No workarounds or hacks — these block clean implementation until fixed.

---

## GAP-001: Cross-module type mapping for sibling Zig modules

**Discovered:** 2026-04-10

**What we tried to do:** Have `tamga_vk3d.zig` accept a `tamga_sdl3.Window` parameter in its
public `create()` function, so Orhon code can pass a Window from the SDL3 module to the
renderer module.

**What blocked it:** The Zig module auto-mapper (`zig_module.zig`, `mapTypeEx`) treats all
qualified type names (like `sdl.Window` from `@import("tamga_sdl3.zig")`) as `field_access`
nodes and returns `false` — marking them unmappable. Any function with an unmappable parameter
is silently skipped from the generated Orhon module.

The compiler already auto-detects sibling imports (`scanZigImports()`) and injects
`import tamga_sdl3` into the generated `.orh` file. So Orhon code CAN reference
`tamga_sdl3.Window` as a type. But the function that ACCEPTS it never shows up because
the mapper doesn't connect sibling module types to their Orhon equivalents.

**The clean solution:** When `mapTypeEx` encounters a `field_access` node (qualified type),
check if the qualifier matches a known sibling Zig module. If so, resolve the type to
`sibling_module_name.TypeName` in the generated Orhon interface instead of returning false.
The import injection already exists — the type mapping just needs to use it.

**Impact on tamga:** Blocks any cross-library type passing. Renderer creation needs Window,
GUI needs Window, audio may need Window. Any library-to-library interaction that passes
user-facing types is affected. This is fundamental for a framework where modules compose.

**Severity:** Blocker for tamga's complete update. Must be fixed in orhon_compiler before
tamga can fully migrate to the new Zig module system.
