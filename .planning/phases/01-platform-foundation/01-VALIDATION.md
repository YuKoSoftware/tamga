---
phase: 1
slug: platform-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
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
| 01-01-01 | 01 | 1 | WIN-01 | integration | `orhon test` | ❌ W0 | ⬜ pending |
| 01-01-02 | 01 | 1 | WIN-10 | integration | `orhon test` | ❌ W0 | ⬜ pending |
| 01-02-01 | 02 | 1 | WIN-04 | integration | `orhon test` | ❌ W0 | ⬜ pending |
| 01-02-02 | 02 | 1 | WIN-05 | integration | `orhon test` | ❌ W0 | ⬜ pending |
| 01-02-03 | 02 | 1 | WIN-06 | integration | `orhon test` | ❌ W0 | ⬜ pending |
| 01-02-04 | 02 | 1 | WIN-11 | integration | `orhon test` | ❌ W0 | ⬜ pending |
| 01-03-01 | 03 | 2 | WIN-02, WIN-09 | manual | visual verify | n/a | ⬜ pending |
| 01-03-02 | 03 | 2 | WIN-08 | manual | visual verify | n/a | ⬜ pending |
| 01-03-03 | 03 | 2 | WIN-14 | integration | `orhon test` | ❌ W0 | ⬜ pending |
| 01-04-01 | 04 | 2 | LOOP-01, LOOP-02 | integration | `orhon test` | ❌ W0 | ⬜ pending |
| 01-04-02 | 04 | 2 | LOOP-03 | integration | `orhon test` | ❌ W0 | ⬜ pending |
| 01-05-01 | 05 | 3 | WIN-12, WIN-13 | integration | `orhon test` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `src/test/test_platform.orh` — integration tests for window creation, events, frame loop
- [ ] Update existing `src/test/test_sdl3.orh` to use new Tamga-native API (not raw SDL3 constants)

*Note: Orhon test runner is built-in, no framework installation needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Window resize delivers correct HiDPI pixel dimensions | WIN-02, WIN-09 | Requires visual display + actual resize interaction | Open window, resize, verify pixel dimensions in callback match actual display pixels |
| Cursor hide/show/lock in 3D viewport | WIN-08 | Requires mouse interaction verification | Open window, enable relative mouse mode, verify cursor hidden and delta values correct |
| Gamepad input response | WIN-06 | Requires physical gamepad connected | Connect gamepad, verify axis/button events fire with correct values |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
