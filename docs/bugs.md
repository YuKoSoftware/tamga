# Compiler Bugs

## Fixed

### Cross-module `@cImport` type identity
**Fixed in:** `#cimport` unification

The compiler now generates a single shared `@cImport` wrapper module (e.g., `_vulkan_c.zig`) for all modules that declare the same `#cimport` name. Types are identical across modules — no more `@ptrCast` at module boundaries.

### No mechanism to compile C/C++ source files in module
**Fixed in:** `#cimport source:` field

`#cimport = { name: "...", include: "...", source: "file.cpp" }` compiles the source file and links it into the module. `linkLibCpp()` is added automatically for C++ sources.

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

None — all known bugs are fixed.

## Fixed (v0.16)

### `(null | A | B | C)` union with null
**Fixed in:** v0.14 Phase 20 — generates `?union(enum) { ... }` for multi-type null unions.

### `cast(EnumType, int)` generates @enumFromInt
**Fixed in:** v0.14 Phase 20

### Empty struct construction `TypeName{}`
**Fixed in:** v0.14 Phase 20

### Multi-file module with Zig sidecar
**Fixed in:** v0.16 Phase 27 — sidecar pub-fixup loop fixed; deduplication prevents duplicate module registration.

### `size` keyword in bridge func parameters
**Fixed in:** PEG grammar — `param_name` rule allows builtin keywords in parameter position.

### `const &BridgeStruct` pointer pass
**Fixed in:** v0.16 Phase 25 — `is_bridge` flag on FuncSig guards const auto-borrow.

### Bridge struct value param `*const` in error-union functions
**Fixed in:** v0.16 Phase 25 — `is_bridge` guard covers all bridge calls. Tamga workaround obsolete.

### Sidecar `export fn` → `pub export fn`
**Fixed in:** v0.16 Phase 25 — read-modify-write prepends `pub` to all `export fn`.

### Negative float literals in arguments
**Fixed in:** v0.16 Phase 26 — unary `-` added to PEG grammar.

### `#cimport` module-relative include paths
**Fixed in:** v0.16 Phase 27 — `addIncludePath` for source module directory.

### `#cimport source:` linkSystemLibrary
**Fixed in:** v0.16 Phase 27 — unconditional for all `#cimport` names.

### Cross-module `is` operator tagged union check
**Fixed in:** v0.16 Phase 26 — emits `val == ._TypeName` for arbitrary unions.

### Cross-compilation garbled step name
**Fixed in:** v0.16 Phase 28 — use-after-free in `target_flag` allocation fixed.

### `-fast` cache leak into `bin/`
**Fixed in:** v0.16 Phase 28 — cache cleanup runs unconditionally.
