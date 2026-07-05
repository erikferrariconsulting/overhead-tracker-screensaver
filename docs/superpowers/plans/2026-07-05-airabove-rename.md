# AirAbove Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the entire codebase and shipped identity to `AirAbove` with no remaining use of the old project name in app-facing identifiers, bundle IDs, product names, schemes, runtime strings, docs, or local installer paths.

**Architecture:** This is a clean brand cutover. Because the app has not shipped yet, we do not preserve compatibility with old bundle IDs or product names. The work should proceed in a strict sequence: define the new naming map, rename Xcode targets and schemes, update Swift module imports and type names, remove old runtime strings and cache namespaces, then sweep docs, tests, and tooling before a final repo-wide verification.

**Tech Stack:** Xcode project file, Swift source, macOS bundle metadata, shell-based verification with `rg` and `xcodebuild`.

---

### Task 1: Define the canonical AirAbove naming map

**Files:**
- Modify: `OverheadTrackerScreensaver.xcodeproj/project.pbxproj`
- Modify: `App/OverheadTrackerApp.swift`
- Modify: `Screensaver/OverheadTrackerScreensaverView.swift`
- Modify: `Screensaver/FlightFeedClient.swift`
- Modify: `App/ScreensaverInstaller.swift`
- Modify: `README.md`

- [ ] **Step 1: Establish the final names**

Use these names consistently everywhere:
- App product name: `AirAbove`
- Screensaver bundle name: `AirAbove.saver`
- Core framework name: `AirAboveCore`
- Core test bundle name: `AirAboveCoreTests`
- App bundle ID: `com.airabove.app`
- Screensaver bundle ID: `com.airabove.screensaver`
- Cache namespace: `com.airabove.screensaver`
- User agent string: `AirAbove/1.0 (+https://airabove.com)`

- [ ] **Step 2: Verify current old-name footprint**

Run:
```bash
rg -n "OverheadTracker|overheadtracker|overhead-tracker|com\\.overheadradar|com\\.overheadtracker" .
```

- [ ] **Step 3: Update the naming map in project metadata**

Replace old product, target, and bundle identifiers with the AirAbove equivalents in the Xcode project file and any app-facing strings in the app entry points.

- [ ] **Step 4: Verify the old identity is gone from first-party code**

Run:
```bash
rg -n "OverheadTracker|overheadtracker|overhead-tracker|com\\.overheadradar|com\\.overheadtracker" App Screensaver Tests README.md
```

- [ ] **Step 5: Commit**

```bash
git add OverheadTrackerScreensaver.xcodeproj/project.pbxproj App/OverheadTrackerApp.swift Screensaver/OverheadTrackerScreensaverView.swift Screensaver/FlightFeedClient.swift App/ScreensaverInstaller.swift README.md
git commit -m "rename project identity to AirAbove"
```

### Task 2: Rename Xcode targets, products, and shared schemes

**Files:**
- Modify: `OverheadTrackerScreensaver.xcodeproj/project.pbxproj`
- Modify: `OverheadTrackerScreensaver.xcodeproj/xcshareddata/xcschemes/OverheadTrackerScreensaver.xcscheme`
- Modify: `OverheadTrackerScreensaver.xcodeproj/xcshareddata/xcschemes/OverheadTrackerScreensaverCore.xcscheme`
- Modify: any other shared scheme in `OverheadTrackerScreensaver.xcodeproj/xcshareddata/xcschemes`

- [ ] **Step 1: Rename targets and products**

Update the display names and product references so the project exposes:
- `AirAbove`
- `AirAboveCore`
- `AirAboveCoreTests`

- [ ] **Step 2: Rename shared schemes**

Update the scheme XML so buildable names and blueprint names reference the new product and target names, including:
- `AirAbove.saver`
- `AirAboveCore.framework`
- `AirAboveCoreTests.xctest`

- [ ] **Step 3: Verify scheme discovery**

Run:
```bash
xcodebuild -list -project OverheadTrackerScreensaver.xcodeproj
```

Expected:
- schemes and targets use AirAbove names only

- [ ] **Step 4: Commit**

```bash
git add OverheadTrackerScreensaver.xcodeproj/project.pbxproj OverheadTrackerScreensaver.xcodeproj/xcshareddata/xcschemes/*
git commit -m "rename xcode targets and schemes"
```

### Task 3: Rename Swift modules, type names, and imports

**Files:**
- Modify: `App/OverheadTrackerApp.swift`
- Modify: `App/MainView.swift`
- Modify: `App/SettingsView.swift`
- Modify: `App/ScreensaverInstaller.swift`
- Modify: `Screensaver/OverheadTrackerScreensaverView.swift`
- Modify: `Screensaver/FlightCardView.swift`
- Modify: `Screensaver/FlightFeedClient.swift`
- Modify: `Tests/Core/*.swift`

- [ ] **Step 1: Update module imports**

Replace:
- `import OverheadTrackerScreensaverCore` -> `import AirAboveCore`

- [ ] **Step 2: Rename public app entry types**

Rename old brand-bearing types to AirAbove names, including:
- `OverheadTrackerApp` -> `AirAboveApp`
- `OverheadTrackerScreensaverView` -> `AirAboveScreensaverView`
- `OverheadTrackerScreensaverRootView` -> `AirAboveRootView`

- [ ] **Step 3: Update test imports**

Replace:
- `@testable import OverheadTrackerScreensaverCore` -> `@testable import AirAboveCore`

- [ ] **Step 4: Build the renamed app and tests**

Run:
```bash
xcodebuild -scheme AirAbove -project OverheadTrackerScreensaver.xcodeproj -configuration Debug -destination 'platform=macOS' build
xcodebuild test -scheme AirAboveCore -project OverheadTrackerScreensaver.xcodeproj -destination 'platform=macOS'
```

- [ ] **Step 5: Commit**

```bash
git add App/*.swift Screensaver/*.swift Tests/Core/*.swift
git commit -m "rename swift modules and entrypoints"
```

### Task 4: Remove old runtime strings and persistent namespaces

**Files:**
- Modify: `Screensaver/FlightCardView.swift`
- Modify: `Screensaver/OverheadTrackerScreensaverView.swift`
- Modify: `Screensaver/FlightFeedClient.swift`
- Modify: `App/ScreensaverInstaller.swift`

- [ ] **Step 1: Rename cache directories and cache keys**

Replace any cache namespace or persistent folder name:
- `com.overheadtracker.screensaver` -> `com.airabove.screensaver`

- [ ] **Step 2: Rename user agent strings**

Replace:
- `OverheadTrackerScreensaver/1.0 (+https://overheadtracker.com)` -> `AirAbove/1.0 (+https://airabove.com)`

- [ ] **Step 3: Rename installer paths**

Replace:
- `OverheadTrackerScreensaver.saver` -> `AirAbove.saver`

- [ ] **Step 4: Verify runtime strings**

Run:
```bash
rg -n "OverheadTrackerScreensaver|overheadtracker|com\\.overheadtracker|OverheadTracker" App Screensaver Tests
```

Expected:
- no remaining first-party hits

- [ ] **Step 5: Commit**

```bash
git add Screensaver/FlightCardView.swift Screensaver/OverheadTrackerScreensaverView.swift Screensaver/FlightFeedClient.swift App/ScreensaverInstaller.swift
git commit -m "remove old runtime naming"
```

### Task 5: Rename docs, README, and install instructions

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-07-03-flight-api-v1-design.md`
- Modify: any other docs under `docs/` that mention the old brand
- Modify: `App/MainView.swift`

- [ ] **Step 1: Update README build and install instructions**

Replace all old project names, scheme names, bundle names, and install-path examples with AirAbove equivalents.

- [ ] **Step 2: Update docs/spec references**

Replace old brand references in specs and internal docs so the repository has one name only.

- [ ] **Step 3: Update user-facing install text**

Ensure the UI tells the user to install `AirAbove.saver`, not the old saver name.

- [ ] **Step 4: Verify documentation sweep**

Run:
```bash
rg -n "OverheadTracker|overheadtracker|overhead-tracker|Overhead Radar" README.md docs App
```

Expected:
- no first-party documentation still references the old project name

- [ ] **Step 5: Commit**

```bash
git add README.md docs/superpowers/specs/2026-07-03-flight-api-v1-design.md App/MainView.swift
git commit -m "rename docs and install text"
```

### Task 6: Rename test fixtures, debug helpers, and generated outputs

**Files:**
- Modify: `Tests/Core/*.swift`
- Modify: `debug_runner.swift`
- Modify: any scripts or fixtures that reference the old bundle or framework names

- [ ] **Step 1: Rename test expectations**

Update any hardcoded bundle identifiers, product names, or file names in tests.

- [ ] **Step 2: Rename debug helpers**

Update the local runner and any developer scripts so they reference AirAbove names only.

- [ ] **Step 3: Verify helper files**

Run:
```bash
rg -n "OverheadTracker|overheadtracker|OverheadTrackerScreensaver" Tests debug_runner.swift .
```

Expected:
- no first-party hits outside git history or unrelated third-party package names

- [ ] **Step 4: Commit**

```bash
git add Tests/Core/*.swift debug_runner.swift
git commit -m "rename tests and debug helpers"
```

### Task 7: Final repo-wide verification and cleanup

**Files:**
- None unless verification finds missed references

- [ ] **Step 1: Run a full repository sweep**

Run:
```bash
rg -n "OverheadTracker|overheadtracker|overhead-tracker|com\\.overheadradar|com\\.overheadtracker" .
```

Expected:
- no first-party references remain

- [ ] **Step 2: Verify project and test builds**

Run:
```bash
xcodebuild -list -project OverheadTrackerScreensaver.xcodeproj
xcodebuild -scheme AirAbove -project OverheadTrackerScreensaver.xcodeproj -configuration Debug -destination 'platform=macOS' build
xcodebuild test -scheme AirAboveCore -project OverheadTrackerScreensaver.xcodeproj -destination 'platform=macOS'
```

- [ ] **Step 3: Verify installer output**

Confirm the built saver is named `AirAbove.saver` and the installer copies that exact bundle name into Downloads and opens it in System Settings.

- [ ] **Step 4: Commit final cleanup only if needed**

```bash
git add .
git commit -m "finalize AirAbove rename"
```
