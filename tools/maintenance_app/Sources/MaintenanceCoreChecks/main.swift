import Foundation
import MaintenanceCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("CHECK FAILED: \(message)\n", stderr)
        exit(1)
    }
}

func checkPaths() {
    let paths = MaintenancePaths.default
    expect(paths.workspaceRoot.path == "/Users/idefeng/Documents/work", "默认工作目录错误")
    expect(
        paths.unifiedScript.path == "/Users/idefeng/Documents/work/tools/disk_cleanup/scripts/disk_cleanup.py",
        "统一维护脚本路径错误"
    )
    expect(
        paths.latestReport.path == "/Users/idefeng/Documents/work/tools/disk_cleanup/runtime/reports/latest.json",
        "最新报告路径错误"
    )

    let custom = MaintenancePaths(workspaceRoot: URL(fileURLWithPath: "/tmp/work"))
    expect(custom.unifiedScript.path == "/tmp/work/tools/disk_cleanup/scripts/disk_cleanup.py", "自定义脚本路径错误")
    expect(custom.latestReport.path == "/tmp/work/tools/disk_cleanup/runtime/reports/latest.json", "自定义报告路径错误")
    expect(
        custom.fileOrganizerSourceConfig.path == "/tmp/work/tools/file_organizer/runtime/config/source-rules.json",
        "文件整理额外来源配置路径错误"
    )
}

func checkDiskUsageSnapshot() {
    let snapshot = DiskUsageSnapshot(volumeName: "Macintosh HD", mountPath: "/", totalBytes: 100, availableBytes: 25)
    expect(snapshot.usedBytes == 75, "磁盘已用空间计算错误")
    expect(abs(snapshot.usedFraction - 0.75) < 0.0001, "磁盘使用比例计算错误")
}

func checkFileOrganizerSourceConfig() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("maintenance-source-config-\(UUID().uuidString)")
    let configURL = directory.appendingPathComponent("source-rules.json")
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    var config = FileOrganizerSourceConfig(sources: [])
    config.add(path: "/tmp/inbox")
    config.add(path: "/tmp/inbox")
    config.add(path: "/tmp/archive")
    try FileOrganizerSourceConfigStore.write(config, to: configURL)

    let reloaded = try FileOrganizerSourceConfigStore.read(from: configURL)

    expect(reloaded.sources.map(\.path) == ["/tmp/inbox", "/tmp/archive"], "文件整理来源配置去重或顺序错误")
    expect(reloaded.sources.allSatisfy { !$0.recursive }, "文件整理额外来源默认不应递归")
}

func checkReportDecoding() throws {
    let payload = """
    {
      "generated_at": "2026-05-31T09:30:00",
      "apply": false,
      "include_assets": false,
      "include_login_items": true,
      "include_file_organizer": true,
      "skip_disk_cleanup": false,
      "summary": {
        "planned": 2,
        "deleted": 0,
        "skipped": 1,
        "missing": 0,
        "failed": 0,
        "bytes_planned": 4096,
        "bytes_deleted": 0
      },
      "candidates": [
        {
          "path": "/Users/idefeng/DEV/demo/node_modules",
          "category": "rebuildable_cache",
          "reason": "matched_node_modules",
          "risk_level": "low",
          "size_bytes": 4096,
          "status": "planned",
          "error": null
        }
      ],
      "login_items": {
        "mode": "read_only",
        "sfltool_error": null,
        "summary": {
          "item_count": 79,
          "launch_plist_count": 33,
          "own_automation_count": 3,
          "possible_remnant_count": 7,
          "manual_review_count": 54
        },
        "duplicate_display_names": [
          {
            "display_name": "Docker",
            "count": 4,
            "identifiers": ["Docker", "2.com.docker.docker"]
          }
        ],
        "items": [],
        "launch_plists": []
      },
      "file_organizer": {
        "tool": "file-organizer",
        "run_at": "2026-05-31T09:30:00",
        "dry_run": true,
        "summary": {
          "source_count": 3,
          "action_count": 1,
          "pending_directory_count": 9,
          "skipped_count": 5
        },
        "sources": [
          {
            "source": "/Users/idefeng/Downloads",
            "recursive": false,
            "action_count": 1,
            "pending_directory_count": 0,
            "skipped_count": 0,
            "actions": [
              {
                "source": "/Users/idefeng/Downloads/demo.pdf",
                "destination": "/Users/idefeng/Library/CloudStorage/SynologyDrive-etlchina/A-项目管理/其他信息/demo.pdf",
                "category": "other_info_document",
                "status": "dry-run",
                "reason": "matched_rule"
              }
            ],
            "pending_directories": [],
            "skipped_entries": []
          }
        ],
        "pending_directories_path": "/tmp/pending.json",
        "report_path": "/tmp/report.json"
      }
    }
    """.data(using: .utf8)!

    let report = try MaintenanceReport.decode(from: payload)
    expect(report.generatedAt == "2026-05-31T09:30:00", "报告时间解析错误")
    expect(report.summary.planned == 2, "磁盘清理 planned 汇总解析错误")
    expect(report.candidates.first?.riskLevel == "low", "候选项风险等级解析错误")
    expect(report.loginItems?.summary.manualReviewCount == 54, "登录项人工复核数量解析错误")
    expect(report.loginItems?.duplicateDisplayNames.first?.displayName == "Docker", "重复登录项显示名解析错误")
    expect(report.fileOrganizer?.summary.pendingDirectoryCount == 9, "文件整理待处理目录数量解析错误")
    expect(report.fileOrganizer?.sources.first?.actions.first?.status == "dry-run", "文件整理动作状态解析错误")
}

func checkRunnerCommands() {
    let paths = MaintenancePaths(workspaceRoot: URL(fileURLWithPath: "/tmp/work"))
    let runner = MaintenanceRunner(paths: paths, pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"))

    let preview = runner.command(for: .preview)
    expect(preview.executable.path == "/usr/bin/python3", "预览命令的 Python 路径错误")
    expect(preview.arguments == [
        "/tmp/work/tools/disk_cleanup/scripts/disk_cleanup.py",
        "--login-items",
        "--organize-files",
        "--json"
    ], "预览命令参数错误")

    let maintenance = runner.command(for: .conservativeMaintenance)
    expect(maintenance.arguments == [
        "/tmp/work/tools/disk_cleanup/scripts/disk_cleanup.py",
        "--apply",
        "--login-items",
        "--organize-files",
        "--json"
    ], "保守维护命令参数错误")
}

func checkShellCommandDetails() throws {
    let details = try ShellCommandRunner.run(
        ShellCommand(
            title: "详情检查",
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-c", "printf stdout-demo; printf stderr-demo >&2"]
        )
    )

    expect(details.title == "详情检查", "命令详情标题错误")
    expect(details.commandLine.contains("/bin/zsh"), "命令详情缺少可执行路径")
    expect(details.exitStatus == 0, "命令详情退出码错误")
    expect(details.stdout == "stdout-demo", "命令详情 stdout 记录错误")
    expect(details.stderr == "stderr-demo", "命令详情 stderr 记录错误")
    expect(details.succeeded, "命令详情成功状态错误")
}

func checkLaunchAgentStatusParsing() {
    let definition = MaintenanceTaskDefinition(
        label: "com.idefeng.disk-cleanup",
        installedPlistURL: URL(fileURLWithPath: "/Users/idefeng/Library/LaunchAgents/com.idefeng.disk-cleanup.plist"),
        templatePlistURL: URL(fileURLWithPath: "/Users/idefeng/Documents/work/tools/disk_cleanup/launchd/com.idefeng.disk-cleanup.plist"),
        logDirectoryURL: URL(fileURLWithPath: "/Users/idefeng/Documents/work/tools/disk_cleanup/runtime/logs"),
        installerURL: URL(fileURLWithPath: "/Users/idefeng/Documents/work/tools/disk_cleanup/scripts/install_launch_agent.sh"),
        reportURLs: [
            URL(fileURLWithPath: "/Users/idefeng/Documents/work/tools/disk_cleanup/runtime/reports/latest.json")
        ]
    )
    let state = LaunchAgentState(
        definition: definition,
        payload: [
            "ProgramArguments": ["/usr/bin/osascript", "-e", "tell application \"Terminal\""],
            "StartCalendarInterval": [
                "Weekday": 6,
                "Hour": 10,
                "Minute": 30
            ]
        ],
        installed: true
    )

    expect(state.label == "com.idefeng.disk-cleanup", "LaunchAgent label 解析错误")
    expect(state.installed, "LaunchAgent 安装状态解析错误")
    expect(state.scheduleDescription == "周六 10:30", "LaunchAgent 周计划解析错误")
    expect(state.commandDescription.contains("osascript"), "LaunchAgent 命令摘要解析错误")
    expect(state.logDirectoryPath == "/Users/idefeng/Documents/work/tools/disk_cleanup/runtime/logs", "LaunchAgent 日志目录解析错误")
    expect(state.installerPath == "/Users/idefeng/Documents/work/tools/disk_cleanup/scripts/install_launch_agent.sh", "LaunchAgent 安装脚本路径解析错误")
    expect(state.reportPaths.first == "/Users/idefeng/Documents/work/tools/disk_cleanup/runtime/reports/latest.json", "LaunchAgent 报告路径解析错误")

    let daily = LaunchAgentState(
        label: "com.idefeng.file-organizer",
        plistURL: definition.installedPlistURL,
        payload: [
            "StartCalendarInterval": [
                "Hour": 13,
                "Minute": 0
            ]
        ],
        installed: true
    )
    expect(daily.scheduleDescription == "每天 13:00", "LaunchAgent 日计划解析错误")

    let definitions = LaunchAgentState.knownDefinitions(paths: .default)
    expect(definitions.count == 3, "已知 LaunchAgent 数量错误")
    expect(
        definitions.first(where: { $0.label == "com.idefeng.app-cleanup" })?.installerURL.path ==
        "/Users/idefeng/Documents/work/tools/app_cleanup/scripts/install_launch_agent.sh",
        "app-cleanup 安装脚本路径错误"
    )
}

func checkMaintenanceFilters() throws {
    let payload = """
    {
      "generated_at": "2026-05-31T09:30:00",
      "apply": false,
      "include_assets": false,
      "include_login_items": true,
      "include_file_organizer": false,
      "skip_disk_cleanup": false,
      "summary": {
        "planned": 1,
        "deleted": 0,
        "skipped": 1,
        "missing": 0,
        "failed": 0,
        "bytes_planned": 4096,
        "bytes_deleted": 0
      },
      "candidates": [
        {
          "path": "/Users/idefeng/DEV/demo/node_modules",
          "category": "rebuildable_cache",
          "reason": "matched_node_modules",
          "risk_level": "low",
          "size_bytes": 4096,
          "status": "planned",
          "error": null
        },
        {
          "path": "/Users/idefeng/DEV/demo/.next",
          "category": "build_cache",
          "reason": "matched_next",
          "risk_level": "low",
          "size_bytes": 1024,
          "status": "skipped",
          "error": "contains tracked files"
        }
      ],
      "login_items": {
        "mode": "read_only",
        "sfltool_error": null,
        "summary": {
          "item_count": 4,
          "launch_plist_count": 1,
          "own_automation_count": 1,
          "possible_remnant_count": 1,
          "manual_review_count": 2
        },
        "duplicate_display_names": [
          {
            "display_name": "Docker",
            "count": 2,
            "identifiers": ["com.docker.docker", "2.com.docker.docker"]
          }
        ],
        "items": [
          {
            "uid": "1",
            "uuid": "docker-a",
            "display_name": "Docker",
            "name": "Docker",
            "developer_name": "Docker Inc",
            "item_type": "app",
            "disposition": "enabled",
            "identifier": "com.docker.docker",
            "url_path": "/Applications/Docker.app",
            "executable_path": null,
            "category": "manual_review",
            "suggested_action": "review",
            "risk_level": "medium",
            "classification_reason": "duplicate display name"
          },
          {
            "uid": "2",
            "uuid": "docker-b",
            "display_name": "Docker",
            "name": "Docker Helper",
            "developer_name": "Docker Inc",
            "item_type": "app",
            "disposition": "disabled",
            "identifier": "2.com.docker.docker",
            "url_path": "/Applications/Docker.app",
            "executable_path": null,
            "category": "manual_review",
            "suggested_action": "review",
            "risk_level": "medium",
            "classification_reason": "duplicate display name"
          },
          {
            "uid": "3",
            "uuid": "leftover",
            "display_name": "LetsGo Network Incorporated",
            "name": "LetsGo",
            "developer_name": null,
            "item_type": "daemon",
            "disposition": "enabled",
            "identifier": "com.letsgo.helper",
            "url_path": null,
            "executable_path": "/Library/LaunchDaemons/com.letsgo.helper",
            "category": "possible_remnant",
            "suggested_action": "manual_review",
            "risk_level": "medium",
            "classification_reason": "uninstalled app remnant"
          },
          {
            "uid": "4",
            "uuid": "automation",
            "display_name": "com.idefeng.disk-cleanup",
            "name": "disk cleanup",
            "developer_name": null,
            "item_type": "launch_agent",
            "disposition": "enabled",
            "identifier": "com.idefeng.disk-cleanup",
            "url_path": null,
            "executable_path": "/Users/idefeng/Documents/work/tools/disk_cleanup/scripts/run_disk_cleanup.sh",
            "category": "own_automation",
            "suggested_action": "keep",
            "risk_level": "low",
            "classification_reason": "owned automation"
          }
        ],
        "launch_plists": []
      },
      "file_organizer": null
    }
    """.data(using: .utf8)!

    let report = try MaintenanceReport.decode(from: payload)
    let diskFilter = CleanupCandidateFilter(searchText: "node", status: "planned", category: "rebuildable_cache")
    let diskMatches = diskFilter.apply(to: report.candidates)
    expect(diskMatches.map(\.path) == ["/Users/idefeng/DEV/demo/node_modules"], "磁盘候选项过滤错误")

    let loginItems = report.loginItems!
    let remnantFilter = LoginItemFilter(searchText: "letsgo", category: "possible_remnant", duplicateOnly: false)
    expect(remnantFilter.apply(to: loginItems).map(\.uuid) == ["leftover"], "登录项疑似残留过滤错误")

    let duplicateFilter = LoginItemFilter(searchText: "", category: nil, duplicateOnly: true)
    expect(duplicateFilter.apply(to: loginItems).map(\.uuid) == ["docker-a", "docker-b"], "登录项重复显示名过滤错误")
}

func checkMaintenanceLogReader() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("maintenance-log-reader-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let oldLog = directory.appendingPathComponent("old.log")
    let newLog = directory.appendingPathComponent("new.log")
    let hiddenFile = directory.appendingPathComponent(".gitkeep")
    try "old-content".write(to: oldLog, atomically: true, encoding: .utf8)
    try "prefix-abcdefghijklmnopqrstuvwxyz-tail".write(to: newLog, atomically: true, encoding: .utf8)
    try "".write(to: hiddenFile, atomically: true, encoding: .utf8)

    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: oldLog.path)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: newLog.path)

    let preview = try MaintenanceLogReader.recentLogs(in: directory, limit: 1, maxBytes: 9)
    expect(preview.count == 1, "日志预览数量错误")
    expect(preview.first?.fileName == "new.log", "日志预览排序错误")
    expect(preview.first?.content == "wxyz-tail", "日志预览尾部读取错误")
    expect(preview.first?.isTruncated == true, "日志预览截断标记错误")
}

func checkMaintenanceReportExporter() throws {
    let payload = """
    {
      "generated_at": "2026-05-31T10:00:00",
      "apply": true,
      "include_assets": false,
      "include_login_items": true,
      "include_file_organizer": true,
      "skip_disk_cleanup": false,
      "summary": {
        "planned": 2,
        "deleted": 1,
        "skipped": 1,
        "missing": 0,
        "failed": 0,
        "bytes_planned": 4096,
        "bytes_deleted": 2048
      },
      "candidates": [
        {
          "path": "/Users/idefeng/DEV/demo/node_modules",
          "category": "rebuildable_cache",
          "reason": "matched_node_modules",
          "risk_level": "low",
          "size_bytes": 4096,
          "status": "deleted",
          "error": null
        }
      ],
      "login_items": {
        "mode": "read_only",
        "sfltool_error": null,
        "summary": {
          "item_count": 79,
          "launch_plist_count": 33,
          "own_automation_count": 3,
          "possible_remnant_count": 7,
          "manual_review_count": 54
        },
        "duplicate_display_names": [
          {
            "display_name": "Docker",
            "count": 4,
            "identifiers": ["Docker", "2.com.docker.docker"]
          }
        ],
        "items": [],
        "launch_plists": []
      },
      "file_organizer": {
        "tool": "file-organizer",
        "run_at": "2026-05-31T10:00:00",
        "dry_run": false,
        "summary": {
          "source_count": 3,
          "action_count": 2,
          "pending_directory_count": 9,
          "skipped_count": 5
        },
        "sources": [],
        "pending_directories_path": "/tmp/pending.json",
        "report_path": "/tmp/report.json"
      }
    }
    """.data(using: .utf8)!

    let report = try MaintenanceReport.decode(from: payload)
    let markdown = MaintenanceReportExporter.markdownSummary(for: report)
    expect(markdown.contains("# 本机维护报告摘要"), "维护报告摘要标题错误")
    expect(markdown.contains("- 模式：执行清理"), "维护报告摘要模式错误")
    expect(markdown.contains("- 磁盘清理：计划 2，已删除 1，跳过 1，失败 0"), "维护报告磁盘摘要错误")
    expect(markdown.contains("- 文件整理：动作 2，待处理目录 9，跳过 5"), "维护报告文件整理摘要错误")
    expect(markdown.contains("- 登录项：总数 79，人工复核 54，疑似残留 7，自有自动化 3"), "维护报告登录项摘要错误")
    expect(MaintenanceReportExporter.fileName(for: report) == "maintenance-summary-2026-05-31T10-00-00.md", "维护报告导出文件名错误")
}

func checkAppBundleTemplate() throws {
    let templateURL = URL(fileURLWithPath: "/Users/idefeng/Documents/work/tools/maintenance_app/Resources/AppBundle/Info.plist")
    let data = try Data(contentsOf: templateURL)
    guard let payload = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
        expect(false, "App Bundle Info.plist 格式错误")
        return
    }

    expect(payload["CFBundleExecutable"] as? String == "MaintenanceApp", "App Bundle 可执行文件名错误")
    expect(payload["CFBundleIdentifier"] as? String == "com.idefeng.maintenanceapp", "App Bundle identifier 错误")
    expect(payload["CFBundleIconFile"] as? String == "MaintenanceApp", "App Bundle 图标文件名错误")
    expect(payload["CFBundlePackageType"] as? String == "APPL", "App Bundle 类型错误")
}

checkPaths()
checkDiskUsageSnapshot()
try checkFileOrganizerSourceConfig()
try checkReportDecoding()
checkRunnerCommands()
try checkShellCommandDetails()
checkLaunchAgentStatusParsing()
try checkMaintenanceFilters()
try checkMaintenanceLogReader()
try checkMaintenanceReportExporter()
try checkAppBundleTemplate()
print("MaintenanceCoreChecks passed")
