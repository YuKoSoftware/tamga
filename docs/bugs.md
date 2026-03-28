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

### Multi-file module with Zig sidecar: "file exists in modules 'root' and 'tamga_sdl3'"

`orhon build` fails with `internal codegen error: tamga_sdl3.zig:1:1: error: file exists in modules 'root' and 'tamga_sdl3'` when a module has multiple .orh files and a Zig sidecar.

**Found in:** Phase 2 plan 02-01 (TamgaVMA creation triggered rebuild that exposed this)

**Impact:** `orhon build` fails for the main executable when tamga_sdl3 module is present. This was pre-existing before TamgaVMA — confirmed by reverting TamgaVMA changes and reproducing the error.

**Root cause:** The Zig sidecar file (`tamga_sdl3.zig`) is being added to the build graph as both a module root file AND as a file within the `tamga_sdl3` module. Likely the codegen iterates all .zig files in a module directory and picks them up twice — once as a sidecar and once as a free-standing Zig file.

**Fix needed:** In the build system codegen, when a module has a sidecar .zig file (same name as the anchor .orh file), only add it as the module's bridge file — do NOT add it to the root build graph as a standalone file.

### ~~`size` is a reserved keyword in bridge func parameters~~ FIXED
**Fixed in:** PEG grammar — `param_name` rule allows `size` and other builtin keywords in parameter position.

### ~~`const &BridgeStruct` parameter codegen passes by value instead of by pointer~~ FIXED
**Fixed in:** v0.16 Phase 25 — `is_bridge` flag on FuncSig guards const auto-borrow. `const &` bridge params now correctly emit `&arg` at call site.

### Bridge struct value param generates `*const` in error-union-returning functions

`bridge func createMaterial(self: &Renderer, ..., texture: Texture) (Error | Material)` — the `texture: Texture` (by value) parameter generates `texture: *const Texture` on the Zig side when the function returns an error union. The generated call site still passes by value, causing a type mismatch.

Non-error-union bridge functions correctly pass structs by value.

**Found in:** Phase 2 plan 02-04 (tamga_vk3d.orh createMaterial)

**Impact:** Bridge functions returning error unions silently convert struct value params to const pointer. The Zig sidecar must use `*const T` to match, and the bridge declaration must use `const &T`.

**Workaround:** Changed bridge declaration to `texture: const &Texture` and Zig sidecar to `texture: *const Texture` to match what the compiler generates.

**Fix needed:** In codegen for error-union-returning bridge functions, keep struct value parameters as values (consistent with non-error-union functions), or at minimum make the call site match the generated signature.

### ~~`export fn` in sidecar .zig should be `pub export fn`~~ FIXED
**Fixed in:** v0.16 Phase 25 — sidecar copy now does read-modify-write to prepend `pub` to all `export fn` declarations.

### ~~Negative float literals rejected as bridge call arguments~~ FIXED
**Fixed in:** v0.16 Phase 26 — unary `-` added to PEG grammar's `unary_expr` rule. Negative literals now valid as function arguments.

### `#cimport` bridge file cannot resolve module-relative include paths

When a sidecar `.zig` file uses `@cInclude("libs/some_header.h")` (a path relative to the source module directory), the generated bridge file at `.orh-cache/generated/` cannot find the header. The Orhon compiler copies the sidecar verbatim without adding a corresponding `addIncludePath` for the source module's directory.

**Found in:** Phase 2 plan 02-04 (tamga_vk3d.zig stb_image include)

**Impact:** Any single-header C library stored alongside the Orhon module (not on the system include path) cannot be used via `@cImport` in a sidecar `.zig` file. Headers must either be on the system path or accessed via `extern fn` declarations.

**Workaround:** Use `extern fn` declarations instead of `@cImport` for the header's types/functions. Provide the C implementation via `#cimport source:` which compiles from the source module directory (where relative paths resolve correctly).

**Fix needed:** When the Orhon compiler copies a sidecar `.zig` to the generated directory, it should also add `addIncludePath(b.path("../../src/ModuleName"))` (or equivalent) so that `@cImport` can find headers relative to the source module.

### `#cimport source:` does not generate `linkSystemLibrary` for owning module

When a module declares `#cimport = { name: "vulkan", include: "vulkan/vulkan.h", source: "vma_impl.cpp" }`, the generated `build.zig` compiles the C++ source and calls `linkLibCpp()`, but does NOT add `linkSystemLibrary("vulkan")` or `linkLibC()` for that module. Another module with the same `#cimport` name (without `source:`) does get `linkSystemLibrary`.

**Found in:** tamga_vulkan module (owns Vulkan cimport + VMA C++ source)

**Impact:** The C++ source may fail to find system headers (e.g., `vulkan/vulkan.h`) on systems where `linkLibCpp()` alone doesn't provide the include path. Currently works on Solus because C++ includes transitively expose Vulkan headers.

**Fix needed:** When `#cimport` has a `source:` field, the generated `build.zig` should also add `linkSystemLibrary(name)` and `linkLibC()` for that module — same as it does for modules that declare `#cimport` without `source:`.

### ~~Cross-module `is` operator generates `@TypeOf` comparison instead of tagged union check~~ FIXED
**Fixed in:** v0.16 Phase 26 — both AST and MIR codegen paths now check `arbitrary_union` type class and emit `val == ._TypeName` for cross-module tagged union checks. Workaround bridge helpers (pollEventTag, getLastScancode) are now obsolete.

### Cross-compilation `-win_x64` passes garbled step name to Zig build

`orhon build -win_x64` fails with `no step named '�����������������������'`. The compiler passes a corrupted/uninitialized string as the Zig build step name for the Windows x64 target.

**Found in:** Phase 2 (tamga_framework cross-compile attempt)

**Impact:** Cannot cross-compile for Windows. Likely affects all cross-compile targets (`-linux_x64` from non-Linux may also be broken).

**Workaround:** None — build natively on Windows, or fix the compiler.

**Fix needed:** In the build.zig codegen for cross-compilation targets, the step name string is uninitialized or points to freed memory. Initialize it properly before passing to `b.step()`.

### `orhon build -fast` leaks cache directory into `bin/`

`orhon build -fast` creates a cache folder inside `bin/` alongside the output binary. Regular `orhon build` correctly puts all cache in `.orh-cache/` and `zig-cache/`.

**Found in:** Phase 2 (tamga_framework optimized build)

**Impact:** `bin/` gets polluted with cache artifacts. Minor but messy — `bin/` should only contain build outputs.

**Workaround:** Manually delete the cache folder from `bin/` after building.

**Fix needed:** The `-fast` code path uses a different output/cache directory configuration than the regular build. Align it to use the same `.orh-cache/` and `zig-cache/` paths.
