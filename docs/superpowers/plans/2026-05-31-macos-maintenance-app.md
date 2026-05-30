# macOS Maintenance App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a first-version native macOS SwiftUI maintenance app that runs the existing unified Python maintenance script and displays the resulting JSON report.

**Architecture:** Create a Swift Package under `/Users/idefeng/Documents/work/tools/maintenance_app`. Put script paths, command construction, report decoding, and launchd status reading in a testable `MaintenanceCore` library. Put the SwiftUI shell in a `MaintenanceApp` executable target that calls `MaintenanceCore` and never rewrites the Python cleanup rules.

**Tech Stack:** Swift 6.3, Swift Package Manager, SwiftUI, Foundation `Process`, XCTest.

---

### Task 1: Swift Package Skeleton

**Files:**
- Create: `/Users/idefeng/Documents/work/tools/maintenance_app/Package.swift`
- Create: `/Users/idefeng/Documents/work/tools/maintenance_app/Sources/MaintenanceCore/MaintenancePaths.swift`
- Create: `/Users/idefeng/Documents/work/tools/maintenance_app/Sources/MaintenanceCoreChecks/main.swift`

- [x] Create a SwiftPM package with a `MaintenanceCore` library, `MaintenanceApp` executable, and `MaintenanceCoreChecks` executable.
- [x] Add a check proving default paths resolve to `/Users/idefeng/Documents/work` and the unified Python script.
- [x] Run `swift run MaintenanceCoreChecks` and confirm the new path check passes.

### Task 2: Report Decoding

**Files:**
- Create: `/Users/idefeng/Documents/work/tools/maintenance_app/Sources/MaintenanceCore/MaintenanceReport.swift`
- Modify: `/Users/idefeng/Documents/work/tools/maintenance_app/Sources/MaintenanceCoreChecks/main.swift`

- [x] Add failing checks for decoding `summary`, `file_organizer.summary`, `login_items.summary`, candidates, duplicate login names, and launch plist records from representative JSON.
- [x] Implement `Codable` models with optional nested sections, preserving unknown fields by ignoring them.
- [x] Run `swift run MaintenanceCoreChecks` and confirm decoding checks pass.

### Task 3: Script Runner

**Files:**
- Create: `/Users/idefeng/Documents/work/tools/maintenance_app/Sources/MaintenanceCore/MaintenanceRunner.swift`
- Modify: `/Users/idefeng/Documents/work/tools/maintenance_app/Sources/MaintenanceCoreChecks/main.swift`

- [x] Add checks proving preview commands use `--login-items --organize-files --json` without `--apply`.
- [x] Add checks proving conservative maintenance commands use `--apply --login-items --organize-files --json`.
- [x] Implement command construction and a `Process` runner that captures stdout/stderr and decodes JSON output.
- [x] Run `swift run MaintenanceCoreChecks` and confirm runner checks pass.

### Task 4: LaunchAgent Status

**Files:**
- Create: `/Users/idefeng/Documents/work/tools/maintenance_app/Sources/MaintenanceCore/LaunchAgentStatus.swift`
- Modify: `/Users/idefeng/Documents/work/tools/maintenance_app/Sources/MaintenanceCoreChecks/main.swift`

- [x] Add checks reading sample plist dictionaries and converting them into label, schedule, plist path, and installed/missing status.
- [x] Implement status loading for the three known labels: `com.idefeng.disk-cleanup`, `com.idefeng.file-organizer`, and `com.idefeng.app-cleanup`.
- [x] Run `swift run MaintenanceCoreChecks` and confirm launchd status checks pass.

### Task 5: SwiftUI Shell

**Files:**
- Create: `/Users/idefeng/Documents/work/tools/maintenance_app/Sources/MaintenanceApp/MaintenanceApp.swift`
- Create: `/Users/idefeng/Documents/work/tools/maintenance_app/Sources/MaintenanceApp/AppViewModel.swift`
- Create: `/Users/idefeng/Documents/work/tools/maintenance_app/Sources/MaintenanceApp/ContentView.swift`

- [x] Build a SwiftUI app with a sidebar: Overview, Disk Cleanup, File Organizer, Login Items, Scheduled Tasks.
- [x] Add toolbar buttons for preview and conservative maintenance.
- [x] Display report sections from `MaintenanceReport` and launchd status from `LaunchAgentStatus`.
- [x] Keep destructive actions limited to existing conservative script behavior; no login item deletion UI.
- [x] Run `swift build` and confirm the app compiles.

### Task 6: Documentation and Verification

**Files:**
- Modify: `/Users/idefeng/Documents/work/README.md`
- Modify: `/Users/idefeng/Documents/work/CHANGELOG.md`
- Modify: `/Users/idefeng/Documents/work/task.md`

- [x] Document how to run `swift run MaintenanceApp` from `tools/maintenance_app`.
- [x] Document that Xcode is not required for this first SwiftPM version, but a future `.xcodeproj` can be added.
- [x] Run existing Python tests plus Swift checks and build.
- [x] Run a dry preview command through the Python script and verify JSON report still includes disk, file organizer, and login sections.
