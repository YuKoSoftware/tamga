# Compiler Bugs

All Phase 1 bugs (13 total) were fixed in Orhon compiler v0.14.2. See git history for details.

Phase 2 bugs (below) were also fixed but are now **obsolete** — they related to the old
`bridge`/`#cimport` system which no longer exists in the compiler. The new `.zon`-based
Zig module system replaced it entirely.

For current compiler shortcomings, see `docs/compiler-gaps.md`.

## Open

(none)

## Fixed (Phase 2, obsolete — old bridge/cimport system)

- **build-gen: unused bridge module for `use std::collections`** — Fixed in Orhon v0.14.2.
- **build-gen: `linkSystemLibrary` for `#cimport source:` libraries** — Fixed in Orhon v0.14.2.
