# Compiler Gaps

Shortcomings discovered during tamga development that need to be addressed in orhon_compiler.
No workarounds or hacks — these block clean implementation until fixed.

---

## Resolved

### GAP-001: Cross-module type mapping for sibling Zig modules

**Discovered:** 2026-04-10
**Resolved:** 2026-04-11 — Fixed in orhon_compiler. `mapTypeEx` now resolves `field_access`
nodes for sibling Zig modules, mapping them to `module_name.TypeName` in generated Orhon
interfaces. Both alias patterns (`const sdl = @import(...)`) and inline import patterns are
supported.

---

## Open

No open gaps.
