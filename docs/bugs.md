# Compiler Bugs

## Fixed

### Error messages now include source file name
**Fixed in:** v0.8.0

Errors now show file and line: `src/orhonsdl3/orhonsdl3.orh:24`.

### #linkC directive for system library dependencies
**Fixed in:** v0.8.1

Bridge modules now use `#linkC "SDL3"` in the anchor file. The compiler generates `linkSystemLibrary` + `linkLibC` in build.zig automatically. Workaround removed from orhonsdl3.zig — now uses `@cInclude("SDL3/SDL.h")`.

### `pub bridge func` inside bridge struct body
**Fixed**

Parser already handles `pub` before `bridge` inside struct bodies. Tested and confirmed working — `pub bridge func` compiles correctly.

### `elif` keyword now supported
**Fixed in:** v0.8.0

`} elif(condition) {` is now valid syntax. `else if` remains unsupported by design — use `elif` for multi-way branches.

### Duplicate imports when multiple files in same module import same dependency
**Fixed in:** v0.8.2

When two .orh files in the same module both `import orhonsdl3`, the codegen emits `const orhonsdl3 = @import(...)` twice in the generated .zig file. Zig rejects this as "duplicate struct member name".

Fix: codegen deduplicates imports across files in the same module.

### Enum variants with explicit integer values
**Fixed in:** v0.10.x

Compiler now supports `A = 4` inside `pub enum(u32) Scancode { ... }`. Explicit per-variant integer assignments compile and generate correctly.

Workaround removed in Phase 1 cleanup (260326-h4x) — tamga_sdl3.orh Scancode and MouseButton enums now use their real SDL3 integer values directly. The scancode translation table in tamga_sdl3.zig has been removed.

### `is` operator rejects module-qualified type names
**Fixed in:** v0.10.x

`if(ev is tamga_sdl3.QuitEvent)` and `if(ev is not tamga_sdl3.NoEvent)` now compile correctly. Both the parser (dotted RHS) and codegen (qualified type path in generated Zig) are fixed.

Workaround removed in Phase 1 cleanup (260326-h4x) — test_sdl3.orh and test_vulkan.orh now use `is` dispatch on cross-module union types directly. EventKind enum and Event flat struct removed from tamga_sdl3.orh.

### `Unit` type not recognized in bridge return position
**Fixed in:** v0.10.x

The fix uses `void` (not `Unit`) as the non-error member: `(Error | void)`. `pub bridge func initPlatform() (Error | void)` compiles correctly. Zig sidecar returns `void` (no return value).

Workaround removed in Phase 1 cleanup (260326-h4x) — initPlatform no longer returns bool.

### `pub type Alias = T` type alias syntax
**Fixed in:** v0.10.x

The fix uses `pub const Alias: type = T` syntax (not `pub type Alias = T`). `pub const WindowHandle: type = Ptr(u8)` compiles correctly. Zig sidecar uses `pub const WindowHandle = *anyopaque`.

Workaround removed in Phase 1 cleanup (260326-h4x) — WindowHandle wrapper struct replaced by type alias in tamga_sdl3.orh and tamga_sdl3.zig.

## Open

### `(null | A | B | C)` union with null collapses to `?A`

`typeToZig` for `(null | A | B | C)` returns `?A` — only the first non-null type survives. The codegen emits `?A` as the function return type and generates `return .{ ._null = null }` which fails Zig compilation.

**Found in:** Phase 1 cleanup 260326-h4x, tamga_sdl3.orh pollEvent()

**Impact:** Cannot use null in a union with 3+ types. `(null | A)` (two members) works fine, but adding more types causes codegen to drop all but the first.

**Workaround:** Added `NoEvent` struct as a sentinel first union member. pollEvent returns `(NoEvent | QuitEvent | KeyDownEvent | ...)` — a union without null. Callers use `if(ev is not tamga_sdl3.NoEvent)` instead of null check.

**Fix needed:** When a union contains `null` AND more than one non-null type, codegen should generate `?(union(enum) { ... })` rather than `?FirstType`.

### `cast(EnumType, int)` generates @intCast instead of @enumFromInt

`cast(Scancode, raw.getKeyScancode())` generates `@as(Scancode, @intCast(raw.getKeyScancode()))` in Zig. Zig rejects this: `@intCast` cannot convert integers to enum types; `@enumFromInt` must be used instead.

**Found in:** Phase 1 cleanup 260326-h4x, tamga_sdl3.orh pollEvent()

**Impact:** Cannot cast raw integer values to typed enum fields in event structs.

**Workaround:** KeyDownEvent.scancode and MouseButtonEvent.button fields remain `u32`/`u8` (raw integer types). Callers compare against raw integer literals.

**Fix needed:** In codegen `cast(T, x)`, detect when T is an enum type and emit `@as(T, @enumFromInt(x))` instead of `@as(T, @intCast(x))`.

### Empty struct construction `TypeName()` generates invalid Zig `TypeName()`

`return NoEvent()` (a struct with no fields) generates `NoEvent()` in Zig. Zig rejects this: `NoEvent` is a type, not a function. Empty struct literals in Zig are `NoEvent{}`, not `NoEvent()`.

**Found in:** Phase 1 cleanup 260326-h4x, tamga_sdl3.orh pollEvent()

**Impact:** Cannot construct zero-field struct values in arbitrary union return.

**Workaround:** Added a dummy `pub empty: bool` field to NoEvent so construction uses named args: `NoEvent(empty: false)` → Zig: `NoEvent{ .empty = false }`.

**Fix needed:** In codegen, when a call_expr with no args targets a struct type (no bitfield, no function), emit `TypeName{}` (struct initialization) instead of `TypeName()` (function call).

### Multi-file module with Zig sidecar: "file exists in modules 'root' and 'tamga_sdl3'"

`orhon build` fails with `internal codegen error: tamga_sdl3.zig:1:1: error: file exists in modules 'root' and 'tamga_sdl3'` when a module has multiple .orh files and a Zig sidecar.

**Found in:** Phase 2 plan 02-01 (TamgaVMA creation triggered rebuild that exposed this)

**Impact:** `orhon build` fails for the main executable when tamga_sdl3 module is present. This was pre-existing before TamgaVMA — confirmed by reverting TamgaVMA changes and reproducing the error.

**Root cause:** The Zig sidecar file (`tamga_sdl3.zig`) is being added to the build graph as both a module root file AND as a file within the `tamga_sdl3` module. Likely the codegen iterates all .zig files in a module directory and picks them up twice — once as a sidecar and once as a free-standing Zig file.

**Fix needed:** In the build system codegen, when a module has a sidecar .zig file (same name as the anchor .orh file), only add it as the module's bridge file — do NOT add it to the root build graph as a standalone file.

### `size` is a reserved keyword / parse error in bridge func parameters

`bridge func createBuffer(self: &Allocator, size: u64, ...)` fails with `unexpected 'size'`. The word `size` cannot be used as a parameter name in bridge functions.

**Found in:** Phase 2 plan 02-01 (TamgaVMA tamga_vma.orh)

**Impact:** Cannot use `size` as a parameter name in bridge function signatures.

**Workaround:** Renamed parameter to `byte_size` / `byte_count`.

**Fix needed:** Determine if `size` is an intentional reserved keyword or an unintended parse conflict; if unintentional, allow it as an identifier in parameter position.
