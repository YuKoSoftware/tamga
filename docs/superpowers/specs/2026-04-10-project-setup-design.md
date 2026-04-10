# Tamga Project Setup — Design Spec

## Goal

Set up the tamga project with proper guardrails, hooks, and documentation to ensure high-quality development. Based on the orhon_compiler project setup, tailored for tamga's specific needs as a multimedia/gaming framework library collection.

## What Gets Created

### 1. Git Repository

- `git init` in `/home/yunus/Projects/orhon/tamga`
- Remote: `git remote add origin https://github.com/YuKoSoftware/tamga.git`
- Initial commit with existing files + new configuration

### 2. CLAUDE.md

Project instructions file with the following sections:

**What This Project Is**
- Tamga is a multimedia/gaming framework library collection for the Orhon programming language
- Dual purpose: stress-test the Orhon compiler with real-world code, and build a high-quality modern framework
- Built with Orhon (`.orh`) and Zig bridge sidecars (`.zig`). Builds via `orhon build`

**Build & Test**
- `orhon build` — build the project
- `orhon run` — build and run
- Per-library test files in `src/test/test_*.orh` — run manually

**Design Philosophy**
- Modern Vulkan 1.3 only, 64-bit only
- High performance, clean architecture — no hacks, no workarounds
- Research and adopt better approaches rather than patching around limitations
- Every design choice must be justified
- Code must be clean, organized, and well-structured

**Anti-Hallucination Rules**
- Never guess Orhon syntax — check orhon_compiler's PEG grammar (`src/peg/orhon.peg`) and language spec docs (`docs/01-basics.md` through `docs/15-testing.md`)
- Never guess Zig APIs — use zig-mcp tools or WebFetch to verify
- Never guess Vulkan/SDL3 APIs — check official docs (Khronos registry, SDL wiki) or use context7
- Never assume orhon_compiler behavior — read its source when in doubt
- If unsure, look it up; don't extrapolate

**Mandatory Read-Before-Edit**
- Always read a file before modifying it
- Read orhon_compiler language spec docs before changing Orhon syntax usage
- Read `docs/tech-stack.md` before making technology choices
- Read the relevant module's existing code before adding to it

**Code Quality Rules**
- Keep changes minimal — don't refactor surrounding code unless asked
- Match existing patterns in the file being edited
- No hacks, no workarounds — if something can't be done cleanly, flag it and discuss
- Never add features or abstractions beyond what was requested
- Large files are a smell — flag when files grow beyond manageable size

**Workflow Rules**
- Documentation: each doc file has one purpose, no overlap
- Verification: run `orhon build` after meaningful changes, never claim "this should work" — verify it
- Research: before making architecture or API decisions, research current best practices

**Project Structure & Modules**
- Module listing (TamgaSDL3, TamgaVK, TamgaVK3D, etc.)
- Reference to `docs/tech-stack.md` for technology details
- Orhon compiler at `/home/yunus/Projects/orhon/orhon_compiler` is the authority on language behavior

### 3. `.claude/settings.local.json`

**Permissions (auto-allowed):**
- `orhon build`, `orhon run`, `orhon test`
- `git` commands
- `glslangValidator` (shader compilation)
- `ls`, `mkdir`, `bash`
- WebFetch: `ziglang.org`, `registry.khronos.org`, `wiki.libsdl.org`, `github.com`, `codeberg.org`, `devdocs.io`
- WebSearch
- zig-mcp tools (`search_std_lib`, `get_std_lib_item`)
- context7 tools

**Hooks:**

PostToolUse on Edit|Write:
- If edited file is `.zig` or `.orh`, run `orhon build` from tamga directory
- Tails last 20 lines of output
- Catches compilation errors immediately

PreToolUse on Bash (commit gate):
- Matches git commit commands
- Runs `orhon build` before allowing commit
- Denies commit if build fails

### 4. Memory

- User memory: building multimedia/gaming framework, high standards for code quality and modern architecture
- Project memory: Vulkan 1.3 only, 64-bit only, code needs updating against current compiler, remote at github.com/YuKoSoftware/tamga
- Reference memory: orhon_compiler source as authority for language syntax/semantics

### 5. `docs/todo.md` Update

Add note that full code and docs update is the first task after setup — code is outdated against current orhon_compiler.

## What Is NOT In Scope

- Updating tamga source code (separate follow-up task)
- Updating tamga docs content (separate follow-up task)
- Adding new features or modules
- Test automation (tests are visual/GPU-dependent, run manually)
