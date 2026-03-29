# Compiler Bugs

## Open

None — all known bugs are fixed.

## Fixed

### Cross-module `@cImport` type identity
**Fixed in:** v0.15 (`#cimport` unification)

The compiler generates a single shared `@cImport` wrapper module for all modules that declare the same `#cimport` name. Types are identical across modules.

### C/C++ source compilation in modules
**Fixed in:** v0.15 (`#cimport source:` field)

`#cimport = { name: "...", include: "...", source: "file.cpp" }` compiles the source file and links it into the module. `linkLibCpp()` is added automatically for C++ sources.

### System library linking
**Fixed in:** v0.8.1, replaced by `#cimport` in v0.15

Bridge modules use `#cimport = { name: "SDL3", include: "SDL3/SDL.h" }`. The compiler generates `linkSystemLibrary` + `linkLibC` in build.zig automatically.

### Error messages include source file name
**Fixed in:** v0.8.0

### `pub bridge func` inside bridge struct body
**Fixed**

### `elif` keyword
**Fixed in:** v0.8.0

### Duplicate imports in multi-file modules
**Fixed in:** v0.8.2

Codegen deduplicates imports across files in the same module.

### Enum variants with explicit integer values
**Fixed in:** v0.13

`A = 4` inside `pub enum(u32) Scancode { ... }` compiles correctly.

### `is` operator with module-qualified type names
**Fixed in:** v0.13

`if(ev is tamga_sdl3.QuitEvent)` works. Both parser and codegen handle dotted RHS.

### `void` in error union return position
**Fixed in:** v0.13

`pub bridge func initPlatform() (Error | void)` compiles correctly.

### Type alias syntax
**Fixed in:** v0.13

`pub const WindowHandle: type = Ptr(u8)` — uses `const` declaration, not `pub type`.

### `(null | A | B | C)` multi-type null union
**Fixed in:** v0.14

Generates `?union(enum) { ... }` for multi-type null unions.

### `cast(EnumType, int)` generates @enumFromInt
**Fixed in:** v0.14

### Empty struct construction `TypeName{}`
**Fixed in:** v0.14

### Multi-file module with Zig sidecar
**Fixed in:** v0.16

Sidecar pub-fixup loop fixed; deduplication prevents duplicate module registration.

### `size` keyword in bridge func parameters
**Fixed in:** v0.16

PEG grammar `param_name` rule allows builtin keywords in parameter position.

### `const &BridgeStruct` pointer pass
**Fixed in:** v0.16

`is_bridge` flag on FuncSig guards const auto-borrow.

### Sidecar `export fn` → `pub export fn`
**Fixed in:** v0.16

### Negative float literals in arguments
**Fixed in:** v0.16

Unary `-` added to PEG grammar.

### `#cimport` module-relative include paths
**Fixed in:** v0.16

### Cross-module `is` operator tagged union check
**Fixed in:** v0.16

Emits tagged union tag comparison for arbitrary unions.

### Cross-compilation garbled step name
**Fixed in:** v0.16

Use-after-free in `target_flag` allocation fixed.

### `-fast` cache leak into `bin/`
**Fixed in:** v0.16

Cache cleanup runs unconditionally.
