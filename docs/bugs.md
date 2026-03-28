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

### ~~`(null | A | B | C)` union with null collapses to `?A`~~ FIXED

~~`typeToZig` for `(null | A | B | C)` returns `?A` — only the first non-null type survives.~~

**Status:** FIXED — confirmed in Phase 2 plan 02-04. The compiler now correctly generates `?union(enum) { _QuitEvent: QuitEvent, _KeyDownEvent: KeyDownEvent, ... }` for `(null | QuitEvent | KeyDownEvent | ...)`. The `NoEvent` workaround has been removed; `pollEvent()` uses `null` directly.

### ~~`cast(EnumType, int)` generates @intCast instead of @enumFromInt~~ FIXED
**Fixed in:** v0.14 Phase 20 — codegen now emits `@enumFromInt` for enum casts.

### ~~Empty struct construction `TypeName()` generates invalid Zig~~ FIXED
**Fixed in:** v0.14 Phase 20 — codegen now emits `TypeName{}` for zero-field structs.

### ~~Multi-file module with Zig sidecar: "file exists in two modules"~~ FIXED
**Fixed in:** v0.16 Phase 27 — infinite loop in sidecar pub-fixup fixed; sidecar deduplication prevents duplicate module registration.

### ~~`size` is a reserved keyword in bridge func parameters~~ FIXED
**Fixed in:** PEG grammar — `param_name` rule allows `size` and other builtin keywords in parameter position.

### ~~`const &BridgeStruct` parameter codegen passes by value instead of by pointer~~ FIXED
**Fixed in:** v0.16 Phase 25 — `is_bridge` flag on FuncSig guards const auto-borrow. `const &` bridge params now correctly emit `&arg` at call site.

### ~~Bridge struct value param generates `*const` in error-union-returning functions~~ FIXED
**Fixed in:** v0.16 Phase 25 — `is_bridge` guard on FuncSig prevents const auto-borrow for all bridge calls including error-union-returning functions. The workaround (`const &Texture` + `*const Texture`) is now obsolete — by-value params work correctly. Regression tests added to mir.zig.

### ~~`export fn` in sidecar .zig should be `pub export fn`~~ FIXED
**Fixed in:** v0.16 Phase 25 — sidecar copy now does read-modify-write to prepend `pub` to all `export fn` declarations.

### ~~Negative float literals rejected as bridge call arguments~~ FIXED
**Fixed in:** v0.16 Phase 26 — unary `-` added to PEG grammar's `unary_expr` rule. Negative literals now valid as function arguments.

### ~~`#cimport` bridge file cannot resolve module-relative include paths~~ FIXED
**Fixed in:** v0.16 Phase 27 — `addIncludePath` emitted for source module directory so sidecar `@cInclude` resolves module-relative headers.

### ~~`#cimport source:` does not generate `linkSystemLibrary` for owning module~~ FIXED
**Fixed in:** v0.16 Phase 27 — `linkSystemLibrary` now emitted unconditionally for all `#cimport` names regardless of `source:` field.

### ~~Cross-module `is` operator generates `@TypeOf` comparison instead of tagged union check~~ FIXED
**Fixed in:** v0.16 Phase 26 — both AST and MIR codegen paths now check `arbitrary_union` type class and emit `val == ._TypeName` for cross-module tagged union checks. Workaround bridge helpers (pollEventTag, getLastScancode) are now obsolete.

### ~~Cross-compilation `-win_x64` passes garbled step name~~ FIXED
**Fixed in:** v0.16 Phase 28 — use-after-free in `target_flag` allocation fixed; `defer` moved outside `if` block so string lives until `runZigIn` reads it.

### ~~`orhon build -fast` leaks cache directory into `bin/`~~ FIXED
**Fixed in:** v0.16 Phase 28 — cache cleanup now removes `zig-out`, `.zig-cache`, and `zig-cache` from both generated and project root directories.
