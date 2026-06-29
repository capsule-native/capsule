# Milestone 9 Whole-Branch Review Fix Report

Applied: 2026-06-29  
Branch: worktree-agent-a5fc55111aa79e3b4 (fast-forwarded to milestone-9-machines, then patched)  
CI result: **632 tests, 6 skipped, 0 failures**

---

## C1 — machineActionsModel errors are never shown

**File:** `Sources/CapsuleUI/AppShellView.swift` (after line 150, after volumeActionsModel block)

Added a `LifecycleNoticeView` block bound to `machineActionsModel.notice`, mirroring the `networkActionsModel` pattern exactly. The notice is now shown in the health banner strip above the content column, and all three closures (onAction, onForceStop, onDismiss) clear it via `machineActionsModel.notice = nil`.

---

## I1 — stop doesn't reload

**File:** `Sources/CapsuleDomain/MachineActionsModel.swift` — `stop(_:)` method

Added `await reloadList()` immediately after the successful `backend.stopMachine` call, before updating `pendingRestart` and posting the activity message. Mirrors the `delete(_:)` and `apply(settings:to:)` pattern.

---

## I2 — restartNow ignores stop failure

**File:** `Sources/CapsuleDomain/MachineActionsModel.swift`

Changed `stop(_ name: String) async` to `@discardableResult stop(_ name: String) async -> Bool`. The success path returns `true`; the catch block returns `false` (already sets `notice` before returning). In `restartNow(_:)`, the call is guarded: `guard await stop(name) else { return }` — if stop failed the restart is aborted (notice is already visible from `stop`). Existing callers that discard the return value are unaffected by `@discardableResult`.

---

## I3 — machine logs leak --follow processes

**Two changes:**

1. **`Sources/CapsuleDomain/MachineActionsModel.swift`** — `makeLogsModels()`: set `boot.follow = false` and `session.follow = false` so opening the sheet takes a snapshot instead of streaming.

2. **`Sources/CapsuleUI/MachineLogsView.swift`** — added `.onDisappear { bootModel.stop(); sessionModel.stop() }` on the root `VStack` so any follow stream the user toggles on is torn down when the sheet dismisses.

---

## I4 — create blocks the wizard for the whole multi-minute boot

**File:** `Sources/CapsuleDomain/MachineActionsModel.swift` — `create(draft:)` method

Reworked the `taskCenter` path to call `taskCenter.runStreaming(...)` discardably (it is `@discardableResult`) and return `true` immediately after enqueueing — the sheet dismisses and the Activity pane shows progress. Moved `onActivity` and `banner` assignment into the `onSuccess` closure. The non-taskCenter fallback path is unchanged (inline async, reports errors via `notice`).

**New test:** `Tests/CapsuleUnitTests/MachineActionsModelCreateTests.swift` — `test_create_taskCenter_backgroundsAndSetsBannerOnSuccess`:  
- Wires a real `TaskCenter()`, calls `create(draft:)` and asserts it returns `true` immediately.  
- Awaits `taskCenter.tasks.last?.wait()` to let the background task finish.  
- Asserts `mock.lastCreatedMachine != nil` and `banner.kind == .created`.  
- PASSED.

---

## M1 — capability gate parity

**ContentColumnView.swift — done:** Added `.machines` to the `isGatedSurfaceUnavailable` switch case alongside `.volumes` and `.networks`. `SidebarSection.machines.isEnabled(features:)` gates the surface when the build doesn't report the machines feature.

**CapsuleCommands.swift — done:** Added `.disabled(!SidebarSection.machines.isEnabled(features: systemModel.health.availableFeatures))` to both "Create Machine…" and "Open Machine Shell" buttons in the Machine `CommandMenu`. `CapsuleApp` already imports `CapsuleUI` so `SidebarSection` is accessible. `systemModel.health.availableFeatures` is already observed in the commands body.

---

## M2 — dead confirmation property

**File:** `Sources/CapsuleDomain/MachineActionsModel.swift`

Removed `public var confirmation: ConfirmationRequest?`. No production code outside this file referenced it (verified with `grep`).

---

## M3 — remove superseded helper

**Files:**
- `Sources/CapsuleDomain/ContainerLifecycleModel.swift`: removed the entire `openMachineShell(name:)` method (lines 94–102 in the original). No production caller found.
- `Tests/CapsuleUnitTests/ContainerLifecycleModelTests.swift`: removed `testMachineShellBuildsArgv` (11 lines). The test was the only reference to the removed method.

---

## M4 — clear previousDefault after revert

**File:** `Sources/CapsuleDomain/MachineActionsModel.swift` — `revertDefault()` method

Added `previousDefault = nil` immediately after `backend.setDefaultMachine(id: prev)` succeeds and before `reloadList()`. A failed revert leaves `previousDefault` intact so the user can retry.

---

## make ci output summary

```
Build complete!
swift format lint — clean (no warnings)
check-architecture.sh — Architecture boundaries OK
check-headers.sh — License headers OK
swift test — 632 tests, 6 skipped, 0 failures
```
