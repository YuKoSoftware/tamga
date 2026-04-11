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

### GAP-003: Cannot call Zig compt functions that take tuple/struct literal arguments

**Discovered:** 2026-04-11
**Status:** Open

**What we tried to do:** Call `std::bitfield`'s `Bitfield(u64, ("Resizable", "Fullscreen", ...))`
from Orhon code to define a window flags bitfield.

**What blocked it:** The Zig `Bitfield` function takes `comptime flags: anytype` which expects
a Zig struct/tuple literal (`.{ "Read", "Write" }`). Orhon has no syntax to produce this kind
of argument — Orhon tuples `("a", "b")` are named tuples, not Zig-style anonymous struct
literals.

**The clean solution:** Either add Orhon syntax that maps to Zig anonymous struct literals,
or add a dedicated `bitfield` keyword/syntax to Orhon (which the old compiler had via
`bitfield(u64) Name { ... }`).

**Current workaround:** Plain `pub const` integer constants for each flag value.

**Impact on tamga:** WindowFlags uses plain constants instead of a type-safe bitfield.
Functional but loses the named-flag ergonomics.

**Severity:** Low. Plain constants work. A dedicated bitfield syntax would be better.

### GAP-004: Auto-mapper generates invalid `anyopaque` type references

**Discovered:** 2026-04-11
**Status:** Open

**What we tried to do:** Have Zig functions accept/return `*anyopaque` or `*const anyopaque`
and have them auto-map to Orhon handle types.

**What blocked it:** The auto-mapper maps `*anyopaque` → `mut& anyopaque` and
`*const anyopaque` → `const& anyopaque`. But `anyopaque` is not in the
`PASSTHROUGH_PRIMITIVES` list and is not a valid Orhon type. The generated `.orh` fails
to compile.

**The clean solution:** Either:
1. Add `anyopaque` to primitives and map `*anyopaque` → handle type (matching `.orh` handle declarations)
2. Treat `*anyopaque` and `*const anyopaque` as unmappable (return false from mapTypeEx)
3. Special-case: when a `*anyopaque` param/return is seen, check if the companion `.orh` declares a handle type and map to it

**Current workaround:** Use `usize` to pass pointers as integers. The Zig side casts
`usize` → pointer internally. Works but loses type safety.

**Impact on tamga:** All raw data pointer parameters (vertex data, matrices, camera positions)
use `usize` instead of typed pointers. The handle types in `.orh` are only useful for
cross-module opaque resources (WindowHandle, VkBufferHandle), not for raw data passing.

**Severity:** Medium. `usize` works but is less safe than typed pointers.

### GAP-005: Union return type coercion does not work

**Discovered:** 2026-04-11
**Status:** Open

**What we tried to do:** Return a union member type from a function whose return type is
a union type alias:

```
pub const Event: type = (null | QuitEvent | KeyDownEvent | ...)
pub func pollEvent() Event {
    return QuitEvent{timestamp: ts}  // ERROR: expected 'Event', got 'QuitEvent'
}
```

**What blocked it:** The resolver's `typesCompatible` check in return statements does not
recognize that `QuitEvent` is a member of the `Event` union. It does a strict type equality
check, not a union membership check.

**The clean solution:** In the return type mismatch check (`resolver.zig:364`), when
`expected` is a union type and `val_type` is one of its members, the types should be
considered compatible. This is the same coercion that works for `var x: MyUnion = 100`.

**Current workaround:** Inline the full union type as the function return type instead
of using the alias. This compiles but is verbose and defeats the purpose of the alias.

**Impact on tamga:** `pollEvent()` has a 200-character return type signature instead of
`Event`. Any function returning a union type alias is affected.

**Severity:** High. Union type aliases are unusable as return types, which makes large
union-based APIs (like event systems) awkward.

### GAP-006: Codegen fails on large inline union types

**Discovered:** 2026-04-11
**Status:** Open

**What we tried to do:** Compile `tamga_sdl3.orh` which defines a function returning an
inline union of 14 types:
`(null | QuitEvent | KeyDownEvent | ... | WindowCloseEvent)`

**What blocked it:** The generated `_unions.zig` file references `GamepadAxisEvent` as an
undeclared identifier. The codegen does not properly resolve all union member type names
when generating the Zig union type definition.

**The clean solution:** The codegen pass that generates `_unions.zig` needs to import or
qualify all union member types with their module path. If `GamepadAxisEvent` is defined in
module `tamga_sdl3`, the generated Zig should reference it as `tamga_sdl3.GamepadAxisEvent`
or import it.

**Current workaround:** None. This is a blocking codegen bug.

**Impact on tamga:** `pollEvent()` and any function using large union types cannot compile.
This blocks the SDL3 event system.

**Severity:** Blocker. No workaround — the function cannot compile.

### GAP-007: Codegen generates self-referencing module imports

**Discovered:** 2026-04-11
**Status:** Open

**What we tried to do:** Compile the tamga_sdl3 module which has both a `.orh` file and a
`.zig` file.

**What blocked it:** The generated `tamga_sdl3.zig` output references `tamga_sdl3` as an
identifier within itself — a Zig file cannot import itself. The codegen emits
`tamga_sdl3.SomeType` in contexts where it should use a local reference.

**The clean solution:** When the codegen emits references to types defined in the current
module, it should use the local name (no module prefix) rather than the fully-qualified
module path.

**Current workaround:** None. This is a blocking codegen bug.

**Impact on tamga:** Any module with both `.orh` and `.zig` components hits this.

**Severity:** Blocker. No workaround.
