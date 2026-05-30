# Disk Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local macOS disk cleanup tool that can run conservatively on a schedule and aggressively by explicit manual flag.

**Architecture:** Create a focused `tools/disk_cleanup` utility with a Python CLI, tests, runtime reports, and a `launchd` template. The CLI uses explicit whitelist rules, defaults to dry-run, requires `--apply` to delete, and requires `--include-assets` before deleting `BAResoucesSystem/course_assets` or `大资源平台/automation/release`.

**Tech Stack:** Python 3 standard library, `unittest`, macOS `launchd`, zsh wrapper scripts.

---

### Task 1: Tests for Cleanup Rules

**Files:**
- Create: `tools/disk_cleanup/tests/test_disk_cleanup.py`

- [ ] **Step 1: Write failing tests**

Create tests covering:
- `tmp_pack_*` under `Documents/work/.git/objects/pack` is detected.
- `DEV` dependency/cache directories are detected in conservative mode.
- `course_assets` and `automation/release` are ignored unless `include_assets=True`.
- build directories containing Git-tracked files are skipped.

- [ ] **Step 2: Run tests and confirm red**

Run: `python3 -m unittest discover -s /Users/idefeng/Documents/work/tools/disk_cleanup/tests -q`

Expected: import failure because `disk_cleanup.py` does not exist yet.

### Task 2: Cleanup CLI

**Files:**
- Create: `tools/disk_cleanup/scripts/disk_cleanup.py`

- [ ] **Step 1: Implement candidates and reports**

Build candidate discovery with:
- conservative Git garbage rule for `/Users/idefeng/Documents/work/.git/objects/pack/tmp_pack_*`
- conservative `~/DEV` generated directory rules for `node_modules`, `.venv`, `.next`, `.cache`, `.pytest_cache`, `__pycache__`, `.vite`, `.expo`, `test-results`, `dist`, and safe generated `build` directories
- explicit aggressive rules for `BAResoucesSystem/course_assets` and `大资源平台/automation/release`

- [ ] **Step 2: Implement guarded deletion**

Deletion requires `--apply`. Directories with Git-tracked files are skipped and reported instead of deleted.

- [ ] **Step 3: Run tests and confirm green**

Run: `python3 -m unittest discover -s /Users/idefeng/Documents/work/tools/disk_cleanup/tests -q`

Expected: all tests pass.

### Task 3: Scheduled Wrapper

**Files:**
- Create: `tools/disk_cleanup/scripts/run_disk_cleanup.sh`
- Create: `tools/disk_cleanup/scripts/install_launch_agent.sh`
- Create: `tools/disk_cleanup/launchd/com.idefeng.disk-cleanup.plist`

- [ ] **Step 1: Add conservative scheduled runner**

The scheduled runner calls `disk_cleanup.py --apply` without `--include-assets`.

- [ ] **Step 2: Add installer**

The installer copies the plist to `~/Library/LaunchAgents`, unloads any previous version, loads the new version, and prints launchctl state.

### Task 4: Documentation and Verification

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `task.md`

- [ ] **Step 1: Document usage**

Add manual dry-run, conservative apply, aggressive apply, report path, and launchd install commands.

- [ ] **Step 2: Verify**

Run:
- `python3 -m unittest discover -s /Users/idefeng/Documents/work/tools/disk_cleanup/tests -q`
- `python3 /Users/idefeng/Documents/work/tools/disk_cleanup/scripts/disk_cleanup.py --json`
- `/bin/zsh /Users/idefeng/Documents/work/tools/disk_cleanup/scripts/install_launch_agent.sh`

Expected: tests pass, dry-run report is generated, and launchd loads.
