# macOS 原生维护工具设计建议

## 结论

可以做成 macOS 原生可视化工具，建议使用 SwiftUI 开发。第一版不要重写现有 Python 规则，而是把 SwiftUI App 作为原生外壳，调用统一入口 `tools/disk_cleanup/scripts/disk_cleanup.py`，读取 JSON 报告并展示结果。这样可以最快获得可视化体验，同时避免文件整理、磁盘清理、登录项识别规则出现两套实现。

## 推荐架构

- 原生界面：SwiftUI macOS App，使用侧边栏组织功能模块
- 执行层：Swift `Process` 调用现有 Python 脚本
- 数据层：解析 `tools/disk_cleanup/runtime/reports/latest.json` 与 `tools/file_organizer/runtime/reports/latest.json`
- 定时任务层：读取和管理 `~/Library/LaunchAgents/com.idefeng.*.plist`
- 权限策略：引导用户授权 Terminal 或 App 访问 `Desktop`、`Downloads`、`Documents`；系统级登录项只展示，不自动删除

## 功能模块

1. 总览
   - 显示最近一次运行时间、磁盘清理候选数量、文件整理动作数量、登录项人工复核数量
   - 提供“预览运行”和“执行保守维护”两个主按钮

2. 磁盘清理
   - 展示 `candidates` 列表、大小、风险等级和状态
   - 默认只允许执行保守清理
   - `course_assets` 和 `automation/release` 保持手动确认，不放进默认按钮

3. 文件整理
   - 展示每个来源目录的待移动文件、目标路径、待处理子目录和跳过条目
   - 支持 dry-run 预览，再执行移动

4. 登录项与后台活动
   - 展示重复显示名、来源 plist、可执行路径、分类和建议动作
   - 对 `own_automation` 标记为保留
   - 对 `possible_remnant` 标记为人工复核
   - 不在第一版提供自动删除系统级 LaunchAgent/Daemon

5. 定时任务
   - 显示 `com.idefeng.disk-cleanup`、`com.idefeng.file-organizer`、`com.idefeng.app-cleanup` 的加载状态和计划时间
   - 提供打开 plist、查看最近日志、重新安装 launchd 配置的入口

## 分阶段实现

第一阶段：SwiftUI 壳 + JSON 报告查看 + 手动运行按钮。

第二阶段：launchd 状态查看、日志查看、任务重装。

第三阶段：把部分稳定规则迁移到 Swift 层，但保留 Python 脚本作为兼容入口。

## 不建议第一版做的事

- 不建议直接删除登录项或系统级 plist
- 不建议用管理员权限自动执行清理
- 不建议马上重写全部 Python 逻辑
- 不建议把文件整理规则和清理规则拆成两套实现
