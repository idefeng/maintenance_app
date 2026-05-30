# App Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 macOS 应用残留工具扩展为“规则分级清理”模式，默认只扫描，`--apply` 时仅清理低风险残留，并补充每周五自动执行配置。

**Architecture:** 在 `tools/app_cleanup` 下扩展独立 Python 脚本，核心逻辑拆分为“名称规范化 / 规则匹配 / 风险分级 / 目录扫描 / 清理执行 / 报告写入”几个纯函数，便于使用临时目录做测试。CLI 负责参数解析、调度扫描与可选清理、格式化输出。

**Tech Stack:** Python 3、`argparse`、`json`、`pathlib`、`unittest`

---

### Task 1: 建立测试骨架并锁定匹配行为

**Files:**
- Create: `tools/app_cleanup/tests/test_app_cleanup.py`
- Test: `tools/app_cleanup/tests/test_app_cleanup.py`

- [x] **Step 1: 写失败测试，覆盖名称规范化与路径匹配**
- [x] **Step 2: 运行单测并确认因模块缺失而失败**
- [x] **Step 3: 实现最小脚本骨架与纯函数**
- [x] **Step 4: 运行单测并确认通过**

### Task 2: 完成目录扫描、风险分级与报告输出

**Files:**
- Create: `tools/app_cleanup/scripts/app_cleanup.py`
- Modify: `tools/app_cleanup/tests/test_app_cleanup.py`
- Test: `tools/app_cleanup/tests/test_app_cleanup.py`

- [x] **Step 1: 写失败测试，覆盖扫描、去重、JSON 报告结构**
- [x] **Step 2: 运行对应单测并确认失败**
- [x] **Step 3: 实现扫描器、风险分级、报告生成与文件输出**
- [x] **Step 4: 运行单测并确认通过**

### Task 3: 完成 CLI、定时配置与文档

**Files:**
- Modify: `tools/app_cleanup/scripts/app_cleanup.py`
- Create: `tools/app_cleanup/launchd/com.idefeng.app-cleanup.plist`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `task.md`

- [x] **Step 1: 完成 `--apply` 参数与终端输出**
- [x] **Step 2: 新增每周五定时运行的 `launchd` 模板**
- [x] **Step 3: 更新仓库说明和变更记录**
- [x] **Step 4: 运行完整测试验证**
