#!/usr/bin/env python3
"""macOS 应用残留扫描工具。"""

from __future__ import annotations

import argparse
import json
import re
import shutil
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable


TOOL_ROOT = Path(__file__).resolve().parents[1]
RUNTIME_ROOT = TOOL_ROOT / "runtime"
REPORT_ROOT = RUNTIME_ROOT / "reports"
LOG_ROOT = RUNTIME_ROOT / "logs"
SAFE_DELETE_CATEGORIES = {
    "caches",
    "http_storages",
    "logs",
    "saved_application_state",
}
REPORT_ONLY_CATEGORIES = {
    "user_applications",
    "application_support",
    "app_support",
    "preferences",
    "launch_agents",
    "webkit",
    "containers",
    "group_containers",
}


@dataclass(frozen=True)
class ScanRoot:
    """定义单个扫描根目录。"""

    category: str
    path: Path


def build_default_scan_roots(home: Path) -> list[ScanRoot]:
    """返回默认的用户级扫描目录列表。"""
    library_root = home / "Library"
    return [
        ScanRoot(category="user_applications", path=home / "Applications"),
        ScanRoot(category="application_support", path=library_root / "Application Support"),
        ScanRoot(category="caches", path=library_root / "Caches"),
        ScanRoot(category="http_storages", path=library_root / "HTTPStorages"),
        ScanRoot(category="logs", path=library_root / "Logs"),
        ScanRoot(category="preferences", path=library_root / "Preferences"),
        ScanRoot(category="saved_application_state", path=library_root / "Saved Application State"),
        ScanRoot(category="launch_agents", path=library_root / "LaunchAgents"),
        ScanRoot(category="webkit", path=library_root / "WebKit"),
        ScanRoot(category="containers", path=library_root / "Containers"),
        ScanRoot(category="group_containers", path=library_root / "Group Containers"),
    ]


def normalize_name(name: str) -> str:
    """把应用名规范化为仅含小写字母数字的形式。"""
    return re.sub(r"[^a-z0-9]+", "", name.lower())


def iter_match_tokens(app_name: str) -> list[str]:
    """生成用于匹配路径名的基础 token。"""
    normalized = normalize_name(app_name)
    tokens = {normalized}
    lowered = app_name.lower().strip()
    if lowered:
        tokens.add(lowered)
    return [token for token in tokens if token]


def normalize_for_compare(value: str) -> str:
    """把路径名规范化后用于模糊比较。"""
    return re.sub(r"[^a-z0-9]+", "", value.lower())


def match_path(path: Path, app_name: str) -> tuple[bool, str | None]:
    """判断路径是否命中应用残留规则，并返回命中原因。"""
    path_name = path.name
    normalized_path = normalize_for_compare(path_name)
    normalized_app_name = normalize_name(app_name)

    if normalized_app_name and normalized_app_name in normalized_path:
        reason = "bundle_id_match" if ".plist" in path_name.lower() and "." in path_name else "name_match"
        return True, reason

    for token in iter_match_tokens(app_name):
        if token in path_name.lower():
            return True, "name_match"

    return False, None


def classify_path_type(path: Path) -> str:
    """返回命中项的路径类型，便于后续决定清理动作。"""
    return "directory" if path.is_dir() else "file"


def classify_cleanup_action(category: str) -> tuple[str, str]:
    """按目录风险返回计划动作与风险等级。"""
    if category in SAFE_DELETE_CATEGORIES:
        return "safe_delete", "low"
    if category in REPORT_ONLY_CATEGORIES:
        return "report_only", "high"
    return "skip", "unknown"


def find_matches_in_root(scan_root: ScanRoot, app_name: str) -> list[dict[str, str]]:
    """在单个根目录中扫描候选残留，并去重返回。"""
    if not scan_root.path.exists():
        return []

    matches: list[dict[str, str]] = []
    seen_paths: set[str] = set()

    for path in sorted(scan_root.path.rglob("*"), key=lambda item: str(item).lower()):
        matched, reason = match_path(path, app_name)
        if not matched:
            continue

        string_path = str(path)
        if string_path in seen_paths:
            continue

        seen_paths.add(string_path)
        planned_action, risk_level = classify_cleanup_action(scan_root.category)
        matches.append(
            {
                "path": string_path,
                "category": scan_root.category,
                "name": path.name,
                "match_reason": reason or "name_match",
                "path_type": classify_path_type(path),
                "risk_level": risk_level,
                "planned_action": planned_action,
                "action_status": "pending",
            }
        )

    return matches


def flatten_matches(match_groups: Iterable[list[dict[str, str]]]) -> list[dict[str, str]]:
    """把按目录分组的扫描结果拍平成单个列表。"""
    flattened: list[dict[str, str]] = []
    for group in match_groups:
        flattened.extend(group)
    return flattened


def build_action_summary(matches: list[dict[str, str]]) -> dict[str, int]:
    """汇总计划动作与实际执行结果，便于周报和定时任务排查。"""
    summary = {
        "safe_delete": 0,
        "report_only": 0,
        "skip": 0,
        "deleted": 0,
        "reported": 0,
        "failed": 0,
    }
    for match in matches:
        planned_action = match.get("planned_action", "skip")
        if planned_action in summary:
            summary[planned_action] += 1

        action_status = match.get("action_status")
        if action_status == "deleted":
            summary["deleted"] += 1
        elif action_status in {"reported", "skipped"}:
            summary["reported"] += 1
        elif action_status == "failed":
            summary["failed"] += 1
    return summary


def build_report(
    app_name: str,
    scan_roots: list[ScanRoot],
    match_groups: list[list[dict[str, str]]],
    cleanup_mode: str = "scan",
) -> dict:
    """构造统一的 JSON 扫描报告。"""
    matches = flatten_matches(match_groups)
    scan_root_states = []

    for scan_root in scan_roots:
        # 记录每个扫描目录的状态，便于解释为何某些目录没有结果。
        status = "scanned" if scan_root.path.exists() else "missing"
        scan_root_states.append(
            {
                "category": scan_root.category,
                "path": str(scan_root.path),
                "status": status,
            }
        )

    return {
        "app_name": app_name,
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "cleanup_mode": cleanup_mode,
        "scan_roots": scan_root_states,
        "matches": matches,
        "match_count": len(matches),
        "action_summary": build_action_summary(matches),
    }


def ensure_runtime_directories() -> None:
    """确保报告目录可写。"""
    REPORT_ROOT.mkdir(parents=True, exist_ok=True)
    LOG_ROOT.mkdir(parents=True, exist_ok=True)


def build_default_report_path(app_name: str) -> Path:
    """为当前应用生成默认报告文件名。"""
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    normalized = normalize_name(app_name) or "app"
    return REPORT_ROOT / f"{normalized}-cleanup-{timestamp}.json"


def write_report(report: dict, report_path: Path) -> Path:
    """把报告写入指定路径。"""
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return report_path


def delete_path(path: Path) -> None:
    """按路径类型删除目标。"""
    if path.is_dir():
        shutil.rmtree(path)
        return
    path.unlink()


def apply_cleanup_actions(matches: list[dict[str, str]]) -> dict[str, int]:
    """执行低风险删除动作，其余项目只保留在报告里。"""
    for match in matches:
        planned_action = match.get("planned_action", "skip")
        target_path = Path(match["path"])

        if planned_action == "safe_delete":
            if not target_path.exists():
                match["action_status"] = "skipped"
                continue

            try:
                # 只有已分类为低风险的命中项才允许进入删除分支。
                delete_path(target_path)
                match["action_status"] = "deleted"
            except OSError as error:
                match["action_status"] = "failed"
                match["action_error"] = str(error)
            continue

        if planned_action == "report_only":
            match["action_status"] = "reported"
        else:
            match["action_status"] = "skipped"

    return build_action_summary(matches)


def render_summary(report: dict, report_path: Path) -> str:
    """生成终端摘要输出。"""
    lines = [
        f"应用名: {report['app_name']}",
        f"清理模式: {report['cleanup_mode']}",
        f"扫描目录数: {len(report['scan_roots'])}",
        f"命中数量: {report['match_count']}",
    ]

    if report["matches"]:
        lines.append("候选残留:")
        for match in report["matches"]:
            lines.append(
                f"- [{match['category']}] {match['path']} "
                f"({match['match_reason']}, {match['planned_action']}, {match['action_status']})"
            )
    else:
        lines.append("未发现候选残留")

    action_summary = report["action_summary"]
    lines.append(
        "动作统计: "
        f"safe_delete={action_summary['safe_delete']}, "
        f"report_only={action_summary['report_only']}, "
        f"deleted={action_summary['deleted']}, "
        f"reported={action_summary['reported']}, "
        f"failed={action_summary['failed']}"
    )
    lines.append(f"报告文件: {report_path}")
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    """解析命令行参数。"""
    parser = argparse.ArgumentParser(description="扫描 macOS 已卸载应用的候选残留文件")
    parser.add_argument("app_name", help="要扫描的应用名，例如 LetsVPN")
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
        "--apply",
        action="store_true",
        help="执行低风险白名单清理动作，其他命中项仍只报告",
    )
    return parser.parse_args()


def main() -> int:
    """执行命令行扫描流程。"""
    args = parse_args()
    ensure_runtime_directories()

    scan_roots = build_default_scan_roots(Path.home())
    match_groups = [find_matches_in_root(scan_root, args.app_name) for scan_root in scan_roots]
    cleanup_mode = "apply" if args.apply else "scan"
    if args.apply:
        apply_cleanup_actions(flatten_matches(match_groups))
    report = build_report(args.app_name, scan_roots, match_groups, cleanup_mode=cleanup_mode)
    report_path = args.report_path or build_default_report_path(args.app_name)
    write_report(report, report_path)

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(render_summary(report, report_path))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
