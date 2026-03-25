---
phase: 1
slug: platform-foundation
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-25
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Orhon `test {}` blocks (built-in test runner) |
| **Config file** | none — test files in `src/test/` |
| **Quick run command** | `orhon test` |
| **Full suite command** | `orhon test` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `orhon test`
- **After every plan wave:** Run `orhon test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | WIN-01, WIN-10 | integration | `orhon test` | src/test/test_sdl3.orh | pending |
| 01-02-01 | 02 | 2 | WIN-04, WIN-05, WIN-06, WIN-10, WIN-11 | integration | `orhon build` | src/TamgaSDL3/tamga_sdl3.orh | pending |
| 01-03-01 | 03 | 3 | LOOP-01, LOOP-02, LOOP-03 | integration | `orhon build` | src/TamgaSDL3/tamga_loop.orh | pending |
| 01-03-02 | 03 | 3 | WIN-02, WIN-09, WIN-13 | manual + build | `orhon build` | src/test/test_sdl3.orh | pending |
| 01-03-03 | 03 | 3 | WIN-08, WIN-14 | manual | visual verify | n/a | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [x] `src/test/test_sdl3.orh` — exists in codebase, rewritten in Plan 03 Task 2 to use new Tamga-native API with error union init
- [x] `src/test/test_vulkan.orh` — exists in codebase, rewritten in Plan 03 Task 2 to use new WindowHandle + error union init

*Note: Orhon test runner is built-in, no framework installation needed. The existing test files are rewritten as part of Plan 03 rather than requiring a separate test scaffold — they already exist and serve as the integration test bed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Window resize delivers correct HiDPI pixel dimensions | WIN-02, WIN-09 | Requires visual display + actual resize interaction | Open window, resize, verify pixel dimensions in callback match actual display pixels |
| Cursor hide/show/lock in 3D viewport | WIN-08 | Requires mouse interaction verification | Open window, enable relative mouse mode, verify cursor hidden and delta values correct |
| Gamepad input response | WIN-06 | Requires physical gamepad connected | Connect gamepad, verify axis/button events fire with correct values |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 10s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** ready
