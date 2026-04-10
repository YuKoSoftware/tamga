# Tamga Project Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set up the tamga project with git, CLAUDE.md, hooks, permissions, and memory so that future development has proper guardrails against hallucination, low-quality code, and stale assumptions.

**Architecture:** Configuration-only changes — no source code modifications. Creates CLAUDE.md (project instructions), `.claude/settings.local.json` (permissions + hooks), memory files, and initializes git with remote.

**Tech Stack:** Git, Claude Code hooks system, Orhon compiler (on PATH)

---

### File Structure

- Create: `CLAUDE.md` — project instructions for Claude
- Create: `.claude/settings.local.json` — permissions and hooks
- Create: `~/.claude/projects/-home-yunus-Projects-orhon-tamga/memory/user_profile.md` — user memory
- Create: `~/.claude/projects/-home-yunus-Projects-orhon-tamga/memory/project_tamga.md` — project memory
- Create: `~/.claude/projects/-home-yunus-Projects-orhon-tamga/memory/reference_orhon_compiler.md` — reference memory
- Create: `~/.claude/projects/-home-yunus-Projects-orhon-tamga/memory/MEMORY.md` — memory index
- Modify: `docs/todo.md` — add update task

---

### Task 1: Initialize Git Repository

**Files:**
- Create: `.git/` (via `git init`)

- [ ] **Step 1: Initialize git**

```bash
cd /home/yunus/Projects/orhon/tamga && git init
```

- [ ] **Step 2: Add remote**

```bash
cd /home/yunus/Projects/orhon/tamga && git remote add origin https://github.com/YuKoSoftware/tamga.git
```

- [ ] **Step 3: Verify**

```bash
cd /home/yunus/Projects/orhon/tamga && git remote -v
```

Expected: `origin https://github.com/YuKoSoftware/tamga.git (fetch)` and `(push)`

---

### Task 2: Create CLAUDE.md

**Files:**
- Create: `CLAUDE.md`

- [ ] **Step 1: Write CLAUDE.md**

```markdown
# Tamga — Claude Project Instructions

## What This Project Is

Tamga is a multimedia/gaming framework library collection for the Orhon programming language.
Dual purpose: stress-test the Orhon compiler with real-world code, and build a high-quality
modern framework. Built with Orhon (`.orh`) and Zig bridge sidecars (`.zig`). Builds via
`orhon build`.

---

## Build & Test

```bash
orhon build              # build the project
orhon run                # build and run
```

Per-library test files live in `src/test/test_*.orh` — run manually as needed.
No automated test suite (tests are visual/GPU-dependent).

---

## Design Philosophy

- **Vulkan 1.3 only, 64-bit only** — no backwards compatibility with older Vulkan versions
- High performance, clean architecture — no hacks, no workarounds
- When better approaches exist, research and adopt them rather than patching around limitations
- Every design choice must be justified — if the current approach isn't the best, change it
- Code must be clean, organized, and well-structured

---

## Anti-Hallucination Rules

- Never guess Orhon syntax — check orhon_compiler's PEG grammar
  (`/home/yunus/Projects/orhon/orhon_compiler/src/peg/orhon.peg`) and language spec docs
  (`/home/yunus/Projects/orhon/orhon_compiler/docs/01-basics.md` through `docs/15-testing.md`)
- Never guess Zig APIs — use zig-mcp tools (`search_std_lib`, `get_std_lib_item`) or
  WebFetch to verify before using any std lib function not already present in this project
- Never guess Vulkan or SDL3 APIs — check official docs (Khronos Vulkan registry, SDL wiki)
  or use context7 before using any API not already in the codebase
- Never assume orhon_compiler behavior — read its source when in doubt
- If unsure about anything, look it up; don't extrapolate
- If a tool returns no result for an API, it doesn't exist — don't use it

---

## Mandatory Read-Before-Edit

- Always read a file before modifying it — the full relevant section, not just a few lines
- Read orhon_compiler language spec docs before changing Orhon syntax usage
- Read `docs/tech-stack.md` before making technology choices
- Read the relevant module's existing code before adding to it

---

## Code Quality Rules

- Keep changes minimal — don't refactor surrounding code unless asked
- Match existing patterns in the file being edited (naming, error handling style, structure)
- No hacks, no workarounds — if something can't be done cleanly, flag it and discuss
- Never add features, abstractions, or "improvements" beyond what was requested
- Large files are a smell — flag when files grow beyond manageable size

---

## Workflow Rules

### Documentation rule
Each doc file has one specific purpose — no overlap. Before creating a new doc,
check that no existing file covers the topic. README is introduction only.

### Verification discipline
- After meaningful changes: run `orhon build` to check compilation
- Never claim "this should work" — verify it
- After completing any change touching 3+ files or adding a new feature, run a
  code review via `superpowers:requesting-code-review` before claiming done

### Research rule
Before making architecture or API decisions, research current best practices.
Don't default to whatever's already there if it's outdated. Use WebSearch,
context7, or official documentation to verify that a chosen approach is still
the recommended one.

---

## Project Structure

```
src/
  tamga.orh                  — framework anchor (module tamga_framework)
  tamga_helper.zig           — main helper sidecar
  TamgaSDL3/                 — SDL3 window, input, event dispatch, game loop
  TamgaVK/                   — VMA allocator, render graph, Vulkan core
    TamgaVK3D/               — 3D renderer (textures, materials, lighting)
    TamgaVK2D/               — 2D renderer (planned)
    TamgaVKCompute/          — Compute utilities (planned)
    libs/                    — Vulkan headers, VMA
    shaders3D/               — GLSL shader sources
  TamgaCore/                 — Math, BVH, Pathfinding (planned)
  TamgaAI/                   — GOAP, Utility AI (planned)
  TamgaAudio/                — Audio (planned)
  TamgaECS/                  — Entity Component System (planned)
  TamgaGUI/                  — GUI (planned)
  TamgaNET/                  — Networking (planned)
  TamgaPhysics/              — Physics (planned)
  test/                      — Per-library test files
assets/
  shaders/                   — Compiled .spv files (runtime)
  textures/                  — Texture files
docs/
  tech-stack.md              — Technology choices and rationale
  todo.md                    — Current work and tasks
  ideas.md                   — Language and framework ideas
  bugs.md                    — Compiler bugs found via tamga
```

---

## References

- Orhon compiler source: `/home/yunus/Projects/orhon/orhon_compiler` — the authority on
  language syntax, semantics, and behavior
- Orhon language spec: `/home/yunus/Projects/orhon/orhon_compiler/docs/01-basics.md`
  through `docs/15-testing.md`
- PEG grammar: `/home/yunus/Projects/orhon/orhon_compiler/src/peg/orhon.peg`
- Zig docs: https://ziglang.org/documentation/master/
- Vulkan spec: https://registry.khronos.org/vulkan/
- SDL3 docs: https://wiki.libsdl.org/SDL3/
```

- [ ] **Step 2: Verify the file reads correctly**

Read the file back and confirm no formatting issues.

---

### Task 3: Create `.claude/settings.local.json`

**Files:**
- Create: `.claude/settings.local.json`

- [ ] **Step 1: Create .claude directory**

```bash
mkdir -p /home/yunus/Projects/orhon/tamga/.claude
```

- [ ] **Step 2: Write settings.local.json**

```json
{
  "permissions": {
    "allow": [
      "Bash(orhon build:*)",
      "Bash(orhon run:*)",
      "Bash(orhon test:*)",
      "Bash(git:*)",
      "Bash(glslangValidator:*)",
      "Bash(ls:*)",
      "Bash(mkdir:*)",
      "Bash(bash:*)",
      "WebFetch(domain:ziglang.org)",
      "WebFetch(domain:registry.khronos.org)",
      "WebFetch(domain:wiki.libsdl.org)",
      "WebFetch(domain:github.com)",
      "WebFetch(domain:codeberg.org)",
      "WebFetch(domain:devdocs.io)",
      "WebSearch",
      "mcp__zig-docs__search_std_lib",
      "mcp__zig-docs__get_std_lib_item",
      "mcp__context7__resolve-library-id",
      "mcp__context7__query-docs"
    ]
  },
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "input=$(cat); f=$(echo \"$input\" | python3 -c \"import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path','') or d.get('tool_response',{}).get('filePath',''))\"); case \"$f\" in *.zig|*.orh) cd /home/yunus/Projects/orhon/tamga && orhon build 2>&1 | tail -20 ;; esac",
            "timeout": 60,
            "statusMessage": "Running orhon build..."
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "input=$(cat); cmd=$(echo \"$input\" | python3 -c \"import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))\"); case \"$cmd\" in *'git commit'*) cd /home/yunus/Projects/orhon/tamga && orhon build 2>&1 | tail -20; EXIT=$?; if [ $EXIT -ne 0 ]; then echo '{\"hookSpecificOutput\":{\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"orhon build failed — fix before committing\"}}'; fi ;; esac",
            "timeout": 60,
            "statusMessage": "Running orhon build before commit..."
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: Verify the JSON is valid**

```bash
cd /home/yunus/Projects/orhon/tamga && python3 -c "import json; json.load(open('.claude/settings.local.json')); print('Valid JSON')"
```

Expected: `Valid JSON`

---

### Task 4: Update `docs/todo.md`

**Files:**
- Modify: `docs/todo.md`

- [ ] **Step 1: Add update task at the top of the file**

Add a new section at the top of `docs/todo.md`, before existing content:

```markdown
## Project Update (Post-Setup)

Code and docs are outdated against the current Orhon compiler. Full update needed:
- Audit all `.orh` files against current compiler syntax and semantics
- Audit all `.zig` sidecar files against current compiler bridge conventions
- Update `docs/tech-stack.md` to reflect Vulkan 1.3 only (remove 1.2 references)
- Update `docs/ideas.md` — remove items that have been implemented or are no longer relevant
- Update `docs/bugs.md` — verify against current compiler version
- Verify `orhon build` succeeds with current compiler
- Run each test file manually and fix breakage
```

- [ ] **Step 2: Verify the edit**

Read `docs/todo.md` back and confirm the new section is at the top.

---

### Task 5: Create Memory Files

**Files:**
- Create: `~/.claude/projects/-home-yunus-Projects-orhon-tamga/memory/user_profile.md`
- Create: `~/.claude/projects/-home-yunus-Projects-orhon-tamga/memory/project_tamga.md`
- Create: `~/.claude/projects/-home-yunus-Projects-orhon-tamga/memory/reference_orhon_compiler.md`
- Create: `~/.claude/projects/-home-yunus-Projects-orhon-tamga/memory/MEMORY.md`

- [ ] **Step 1: Write user memory**

File: `~/.claude/projects/-home-yunus-Projects-orhon-tamga/memory/user_profile.md`

```markdown
---
name: User profile
description: Yunus builds the Orhon language and its ecosystem — demands high-quality, modern, no-compromise code
type: user
---

Yunus is the creator of the Orhon programming language and its ecosystem (compiler, framework libraries).
Has high standards for code quality: clean, organized, no hacks, no workarounds. Prefers modern approaches
(Vulkan 1.3, 64-bit only) over backwards-compatible compromises. Wants Claude to research best practices
before making design decisions rather than defaulting to what already exists. Values proper project setup
with guardrails, hooks, and anti-hallucination rules.
```

- [ ] **Step 2: Write project memory**

File: `~/.claude/projects/-home-yunus-Projects-orhon-tamga/memory/project_tamga.md`

```markdown
---
name: Tamga project status
description: Tamga framework current state — Vulkan 1.3 only, 64-bit, code outdated against current compiler
type: project
---

Tamga is a multimedia/gaming framework library collection for Orhon. Vulkan 1.3 only, 64-bit only.
Remote: github.com/YuKoSoftware/tamga.

As of 2026-04-10, all tamga code and docs are outdated against the current orhon_compiler. A full
audit and update is the first task after project setup. Do not trust tamga's existing code as
reflecting current compiler capabilities or syntax.

**Why:** The Orhon compiler evolved significantly since tamga was last worked on. Syntax, semantics,
and build conventions may have changed.

**How to apply:** Always verify Orhon syntax against orhon_compiler source before writing or
modifying `.orh` files in tamga. Don't copy patterns from existing tamga code without checking
they're still valid.
```

- [ ] **Step 3: Write reference memory**

File: `~/.claude/projects/-home-yunus-Projects-orhon-tamga/memory/reference_orhon_compiler.md`

```markdown
---
name: Orhon compiler as authority
description: orhon_compiler project is the source of truth for Orhon language syntax, semantics, and build conventions
type: reference
---

The Orhon compiler source at `/home/yunus/Projects/orhon/orhon_compiler` is the authority for:
- Language syntax: `src/peg/orhon.peg` (PEG grammar)
- Language semantics: `docs/01-basics.md` through `docs/15-testing.md`
- Compiler architecture: `docs/COMPILER.md`
- Zig gotchas and patterns: `CLAUDE.md` (Key Zig Gotchas section)
- Build conventions: how `orhon build` works, sidecar file handling, module structure

Always consult these before writing Orhon code in tamga. The compiler's CLAUDE.md also
documents critical Zig patterns (recursive functions need `anyerror!`, union tag comparison,
reporter string ownership, `@embedFile` usage, template substitution via split-write).
```

- [ ] **Step 4: Write MEMORY.md index**

File: `~/.claude/projects/-home-yunus-Projects-orhon-tamga/memory/MEMORY.md`

```markdown
- [User profile](user_profile.md) — Orhon creator, demands high-quality modern code, no compromises
- [Tamga project status](project_tamga.md) — Vulkan 1.3/64-bit, code outdated, needs full update
- [Orhon compiler reference](reference_orhon_compiler.md) — compiler source is authority for syntax/semantics
```

---

### Task 6: Initial Commit

**Files:**
- All new and modified files

- [ ] **Step 1: Stage files**

```bash
cd /home/yunus/Projects/orhon/tamga && git add CLAUDE.md .claude/settings.local.json docs/todo.md docs/superpowers/specs/2026-04-10-project-setup-design.md docs/superpowers/plans/2026-04-10-project-setup.md
```

Note: Do NOT stage memory files — they live outside the repo in `~/.claude/`.

- [ ] **Step 2: Commit**

```bash
cd /home/yunus/Projects/orhon/tamga && git commit -m "chore: set up project with CLAUDE.md, hooks, and guardrails

Add project instructions, anti-hallucination rules, compilation hooks,
and permission configuration for Claude Code development workflow."
```

- [ ] **Step 3: Stage and commit existing project files**

```bash
cd /home/yunus/Projects/orhon/tamga && git add .gitignore LICENSE README.md assets/ docs/ src/
cd /home/yunus/Projects/orhon/tamga && git commit -m "chore: add existing tamga source and assets"
```

- [ ] **Step 4: Verify**

```bash
cd /home/yunus/Projects/orhon/tamga && git log --oneline
```

Expected: Two commits visible.
