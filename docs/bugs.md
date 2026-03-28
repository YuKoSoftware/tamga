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

### `const &BridgeStruct` parameter codegen passes by value instead of by pointer

`bridge func draw(self: &Renderer, mesh: const &Mesh, ...)` — the `const &Mesh` parameter should pass a pointer to the argument, but the generated Zig emits a by-value pass. Zig expects `*const Mesh` but gets `Mesh`.

**Found in:** Phase 2 plan 02-03 (tamga_vk3d.orh draw/destroyMesh)

**Impact:** Cannot pass bridge struct values as `const &` to bridge functions. `self: &T` (mutable) works correctly as the receiver.

**Workaround:** Changed `const &Mesh` parameters to pass `Mesh` by value (small struct, acceptable API).

**Fix needed:** In codegen, when a bridge function parameter is `const &BridgeStruct`, emit `@ptrCast(&arg)` (take address) at the call site, not just `arg`.

### Bridge struct value param generates `*const` in error-union-returning functions

`bridge func createMaterial(self: &Renderer, ..., texture: Texture) (Error | Material)` — the `texture: Texture` (by value) parameter generates `texture: *const Texture` on the Zig side when the function returns an error union. The generated call site still passes by value, causing a type mismatch.

Non-error-union bridge functions correctly pass structs by value.

**Found in:** Phase 2 plan 02-04 (tamga_vk3d.orh createMaterial)

**Impact:** Bridge functions returning error unions silently convert struct value params to const pointer. The Zig sidecar must use `*const T` to match, and the bridge declaration must use `const &T`.

**Workaround:** Changed bridge declaration to `texture: const &Texture` and Zig sidecar to `texture: *const Texture` to match what the compiler generates.

**Fix needed:** In codegen for error-union-returning bridge functions, keep struct value parameters as values (consistent with non-error-union functions), or at minimum make the call site match the generated signature.

### `export fn` in sidecar .zig should be `pub export fn`

Bridge functions declared in `main.orh` as `bridge func foo()` generate `export fn foo()` in the sidecar copy. The generated `main.zig` does `@import("main_bridge").foo` which requires `pub` visibility.

**Found in:** Phase 2 plan 02-03 (main.zig bridge helper functions)

**Impact:** Bridge functions in the main module's sidecar are not accessible from the generated Orhon code.

**Workaround:** Manually add `pub` to all `export fn` declarations in `main.zig`.

**Fix needed:** When copying sidecar .zig files to bridge files, ensure all `export fn` declarations also have `pub` visibility, or the codegen should emit `pub export fn` for bridge function implementations.

### Negative float literals rejected as bridge call arguments

`ren.setDirLight(0, -0.5, -1.0, -0.3, ...)` fails with `unexpected '-'`. Negative numeric literals are not valid as direct arguments in bridge function calls.

**Found in:** Phase 2 plan 02-04 (test_vulkan.orh setDirLight)

**Impact:** Cannot pass negative float or integer literals directly as function arguments. Non-bridge calls may have the same limitation.

**Workaround:** Assign to a `const` variable first: `const x: f32 = 0.0 - 0.5`, then pass `x`.

**Fix needed:** Parser should allow unary negation expressions (`-0.5`) in argument position.

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

### Cross-module `is` operator generates `@TypeOf` comparison instead of tagged union check

`if(ev is tamga_sdl3.QuitEvent)` generates `if (@TypeOf(ev) == tamga_sdl3.QuitEvent)` in Zig. `@TypeOf` returns the compile-time type of the variable (always the union type), not the runtime active tag. The check is always false.

Intra-module `is` works correctly — `ev == ._QuitEvent` is generated.

**Found in:** Phase 2 plan 02-04 (test_vulkan.orh event handling)

**Impact:** Cannot use `is` to dispatch on union variants from another module. All cross-module `is` checks on tagged unions silently fail (always false).

**Workaround:** Added `pollEventTag()`/`getLastScancode()` bridge helpers in tamga_sdl3 that classify events internally (intra-module `is` works), returning integer tags to the caller.

**Fix needed:** In codegen for `is` with a cross-module type, emit tagged union comparison (`ev == ._TypeName`) instead of `@TypeOf(ev) == TypeName`.

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
