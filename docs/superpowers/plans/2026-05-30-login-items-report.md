# Login Items Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the disk cleanup tool with a read-only macOS Login Items and Background Items report.

**Architecture:** Add parsing and classification helpers to `tools/disk_cleanup/scripts/disk_cleanup.py`. The CLI gains `--login-items`, which runs `sfltool dumpbtm`, scans LaunchAgents/LaunchDaemons metadata, and adds a `login_items` section to the JSON report; it never deletes login item files.

**Tech Stack:** Python 3 standard library, `unittest`, macOS `sfltool`, plist parsing.

---

### Task 1: Tests for Login Item Parsing and Classification

**Files:**
- Modify: `tools/disk_cleanup/tests/test_disk_cleanup.py`

- [ ] **Step 1: Add parser tests**

Add tests proving `parse_btm_dump()` extracts UID, name, type, disposition, identifier, URL, executable path, and parent identifier from `sfltool dumpbtm` text.

- [ ] **Step 2: Add classification tests**

Add tests proving `build_login_items_section()` marks own `com.idefeng.*` osascript entries as `own_automation`, marks uninstaller helper records as `manual_review`, and creates duplicate display-name groups.

- [ ] **Step 3: Run tests and confirm red**

Run `python3 -m unittest discover -s /Users/idefeng/Documents/work/tools/disk_cleanup/tests -q`.

Expected: import failure for new functions.

### Task 2: Implement Read-Only Report

**Files:**
- Modify: `tools/disk_cleanup/scripts/disk_cleanup.py`

- [ ] **Step 1: Add dataclass and parser helpers**

Implement `LoginItemRecord`, `parse_btm_dump()`, URL decoding, and LaunchAgent/LaunchDaemon plist scanning.

- [ ] **Step 2: Add classification**

Implement category and suggested-action rules without deleting anything.

- [ ] **Step 3: Add CLI flag**

Add `--login-items`; when present, include `login_items` in the normal report.

### Task 3: Documentation and Verification

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `task.md`

- [ ] **Step 1: Document the report mode**

Explain that login item cleanup is read-only, and root-level items require manual review.

- [ ] **Step 2: Verify**

Run:
- `python3 -m unittest discover -s /Users/idefeng/Documents/work/tools/disk_cleanup/tests -q`
- `python3 /Users/idefeng/Documents/work/tools/disk_cleanup/scripts/disk_cleanup.py --login-items --json`

Expected: tests pass and the report contains a `login_items` section.
