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

### GAP-002: Auto-mapper does not extract struct fields

**Discovered:** 2026-04-11
**Status:** Open

**What we tried to do:** Access pub fields of a Zig struct from Orhon code. For example,
`RawEvent` has `pub tag: u8` — we wanted `raw.tag` to work from Orhon.

**What blocked it:** `extractStruct` in `zig_module.zig` only iterates `fn_decl`/`fn_proto`
members of Zig struct containers. It skips `container_field` nodes entirely. The generated
Orhon struct has methods but no fields.

**The clean solution:** Add a pass in `extractStruct` that iterates container members,
identifies `container_field` nodes with `pub` visibility, maps their types via `mapTypeEx`,
and emits `pub fieldName: MappedType` lines in the generated Orhon struct.

**Current workaround:** Getter methods on the Zig struct (`pub fn getTag(self: *const RawEvent) u8`).
These auto-map as methods. Works but adds boilerplate.

**Impact on tamga:** Any Zig struct whose fields should be readable from Orhon requires
getter methods. Affects RawEvent, DisplayInfo, and any future data structs.

**Severity:** Medium. Getter methods work but are verbose. Does not block tamga migration.
