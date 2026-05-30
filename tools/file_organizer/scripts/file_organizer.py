#!/usr/bin/env python3
"""本地文件整理工具命令行入口。"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from file_organizer_core import (
    APP_DESTINATION,
    DEFAULT_DOCUMENT_DESTINATION,
    PENDING_DIRECTORIES_PATH,
    PROJECT_ROOT,
    REPORT_ROOT,
    SOURCE_RULES,
    WORK_ROOT,
    FileAction,
    build_destination,
    build_report,
    collect_entries,
    ensure_directories,
    load_source_rules,
    pick_document_destination,
    process_source,
    render_summary,
    resolve_collision,
    should_collect_pending_directory,
    write_pending_directories,
    write_report,
)


def parse_args() -> argparse.Namespace:
    """解析命令行参数。"""
    parser = argparse.ArgumentParser(description="按预设规则整理本地文件")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="只生成报告，不实际移动文件",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="把完整 JSON 报告输出到标准输出",
    )
    parser.add_argument(
        "--report-path",
        type=Path,
        help="指定 JSON 报告写入路径",
    )
    parser.add_argument(
        "--pending-path",
        type=Path,
        help="指定待处理子目录清单写入路径",
    )
    return parser.parse_args()


def main() -> int:
    """执行整理流程。"""
    args = parse_args()
    ensure_directories()

    source_results = []
    all_pending_directories = []

    for source_rule in load_source_rules():
        actions, pending_directories, skipped_entries = process_source(
            source_rule.path,
            dry_run=args.dry_run,
            recursive=source_rule.recursive,
        )
        source_results.append(
            {
                "source": str(source_rule.path),
                "recursive": source_rule.recursive,
                "actions": actions,
                "pending_directories": pending_directories,
                "skipped_entries": skipped_entries,
            }
        )
        all_pending_directories.extend(pending_directories)

    pending_path = write_pending_directories(
        all_pending_directories,
        args.pending_path or PENDING_DIRECTORIES_PATH,
    )
    report = build_report(dry_run=args.dry_run, source_results=source_results)
    report["pending_directories_path"] = str(pending_path)
    report_path = write_report(report, args.report_path)

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(render_summary(report, report_path, pending_path))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
