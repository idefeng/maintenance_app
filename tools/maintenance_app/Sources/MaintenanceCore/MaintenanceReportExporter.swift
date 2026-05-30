import Foundation

public enum MaintenanceReportExporter {
    public static func markdownSummary(for report: MaintenanceReport) -> String {
        var lines: [String] = [
            "# 本机维护报告摘要",
            "",
            "- 生成时间：\(report.generatedAt)",
            "- 模式：\(report.apply ? "执行清理" : "预览")",
            "- 磁盘清理：计划 \(report.summary.planned)，已删除 \(report.summary.deleted)，跳过 \(report.summary.skipped)，失败 \(report.summary.failed)",
            "- 预计释放：\(byteString(report.summary.bytesPlanned))；实际释放：\(byteString(report.summary.bytesDeleted))"
        ]

        if let organizer = report.fileOrganizer {
            lines.append("- 文件整理：动作 \(organizer.summary.actionCount)，待处理目录 \(organizer.summary.pendingDirectoryCount)，跳过 \(organizer.summary.skippedCount)")
        }

        if let loginItems = report.loginItems {
            lines.append("- 登录项：总数 \(loginItems.summary.itemCount)，人工复核 \(loginItems.summary.manualReviewCount)，疑似残留 \(loginItems.summary.possibleRemnantCount)，自有自动化 \(loginItems.summary.ownAutomationCount)")
        }

        if !report.candidates.isEmpty {
            lines.append("")
            lines.append("## 磁盘清理候选")
            for candidate in report.candidates.prefix(20) {
                lines.append("- \(candidate.status)：\(candidate.path)（\(byteString(candidate.sizeBytes))，\(candidate.category)，\(candidate.reason)）")
            }
            appendOmittedCount(report.candidates.count, limit: 20, to: &lines)
        }

        if let duplicates = report.loginItems?.duplicateDisplayNames, !duplicates.isEmpty {
            lines.append("")
            lines.append("## 重复登录项显示名")
            for duplicate in duplicates.prefix(20) {
                lines.append("- \(duplicate.displayName)：\(duplicate.count) 项")
            }
            appendOmittedCount(duplicates.count, limit: 20, to: &lines)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    public static func fileName(for report: MaintenanceReport) -> String {
        let safeTimestamp = report.generatedAt
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return "maintenance-summary-\(safeTimestamp).md"
    }

    private static func appendOmittedCount(_ count: Int, limit: Int, to lines: inout [String]) {
        if count > limit {
            lines.append("- 其余 \(count - limit) 项已省略，请查看完整 JSON 报告。")
        }
    }

    private static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
