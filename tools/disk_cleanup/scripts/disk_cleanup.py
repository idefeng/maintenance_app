#!/usr/bin/env python3
"""本机磁盘空间清理工具。"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import plistlib
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from types import ModuleType
from typing import Any, Iterable
from urllib.parse import unquote, urlparse


TOOL_ROOT = Path(__file__).resolve().parents[1]
TOOLS_ROOT = TOOL_ROOT.parent
RUNTIME_ROOT = TOOL_ROOT / "runtime"
REPORT_ROOT = RUNTIME_ROOT / "reports"
LOG_ROOT = RUNTIME_ROOT / "logs"
FILE_ORGANIZER_CORE_PATH = TOOLS_ROOT / "file_organizer" / "scripts" / "file_organizer_core.py"
DEFAULT_DOCUMENTS_WORK_ROOT = Path("/Users/idefeng/Documents/work")
DEFAULT_DEV_ROOT = Path("/Users/idefeng/DEV")
DEFAULT_LAUNCH_ROOTS = (
    Path.home() / "Library" / "LaunchAgents",
    Path("/Library/LaunchAgents"),
    Path("/Library/LaunchDaemons"),
)

REBUILDABLE_DIR_NAMES = {
    "__pycache__",
    ".cache",
    ".expo",
    ".next",
    ".pytest_cache",
    ".venv",
    ".vite",
    "node_modules",
    "test-results",
}
GENERATED_DIR_NAMES = {"build", "dist"}
EXACT_CONSERVATIVE_PATHS = (
    Path("ETLChina/大资源平台/automation/build/ms-playwright"),
)
EXACT_AGGRESSIVE_PATHS = (
    Path("ETLChina/BAResoucesSystem/course_assets"),
    Path("ETLChina/大资源平台/automation/release"),
)
FILE_ORGANIZER_CORE_MODULE: ModuleType | None = None


@dataclass
class CleanupCandidate:
    """单个待清理候选项。"""

    path: Path
    category: str
    reason: str
    risk_level: str
    size_bytes: int
    status: str = "planned"
    error: str | None = None

    def to_dict(self) -> dict[str, object]:
        """转换为可写入 JSON 报告的结构。"""
        return {
            "path": str(self.path),
            "category": self.category,
            "reason": self.reason,
            "risk_level": self.risk_level,
            "size_bytes": self.size_bytes,
            "status": self.status,
            "error": self.error,
        }


@dataclass
class LoginItemRecord:
    """macOS 登录项与后台活动记录。"""

    uid: str
    uuid: str | None
    name: str | None
    developer_name: str | None
    item_type: str | None
    disposition: str | None
    identifier: str | None
    url: str | None
    url_path: Path | None
    executable_path: Path | None
    parent_identifier: str | None
    bundle_identifier: str | None

    @property
    def display_name(self) -> str:
        """返回用于聚合重复显示名的名称。"""
        return self.name or self.developer_name or self.identifier or "(unknown)"


def ensure_runtime_directories() -> None:
    """确保报告和日志目录存在。"""
    REPORT_ROOT.mkdir(parents=True, exist_ok=True)
    LOG_ROOT.mkdir(parents=True, exist_ok=True)


def path_size(path: Path) -> int:
    """计算路径大小；权限异常时按 0 处理并继续生成报告。"""
    try:
        if path.is_symlink() or path.is_file():
            return path.lstat().st_size
        total = 0
        for root, dirnames, filenames in os.walk(path, topdown=True, followlinks=False):
            for dirname in dirnames:
                try:
                    total += (Path(root) / dirname).lstat().st_size
                except OSError:
                    continue
            for filename in filenames:
                try:
                    total += (Path(root) / filename).lstat().st_size
                except OSError:
                    continue
        return total
    except OSError:
        return 0


def find_git_root(path: Path) -> Path | None:
    """向上查找 Git 仓库根目录。"""
    current = path if path.is_dir() else path.parent
    for candidate in (current, *current.parents):
        if (candidate / ".git").exists():
            return candidate
    return None


def has_tracked_files(path: Path) -> bool:
    """判断路径下是否包含 Git 已跟踪文件，防止误删源码资产。"""
    git_root = find_git_root(path)
    if git_root is None:
        return False

    try:
        relative_path = path.resolve().relative_to(git_root.resolve())
    except ValueError:
        return False

    result = subprocess.run(
        ["git", "-C", str(git_root), "ls-files", "--", str(relative_path)],
        text=True,
        capture_output=True,
        check=False,
    )
    return bool(result.stdout.strip())


def iter_named_directories(root: Path, names: set[str]) -> Iterable[Path]:
    """遍历指定名称的目录，并跳过 Git 内部目录与已命中目录的子树。"""
    if not root.exists():
        return

    for current_root, dirnames, _ in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_root)
        dirnames[:] = [dirname for dirname in dirnames if dirname != ".git"]
        if current.name in names:
            yield current
            dirnames[:] = []


def build_candidate(path: Path, category: str, reason: str, risk_level: str) -> CleanupCandidate:
    """构造候选项并记录当前大小。"""
    return CleanupCandidate(
        path=path,
        category=category,
        reason=reason,
        risk_level=risk_level,
        size_bytes=path_size(path),
    )


def build_skipped_candidate(path: Path, category: str, reason: str) -> CleanupCandidate:
    """构造跳过项，用于解释为何没有删除某些构建目录。"""
    candidate = build_candidate(path, category, reason, "medium")
    candidate.status = "skipped"
    return candidate


def append_unique(candidates: list[CleanupCandidate], candidate: CleanupCandidate) -> None:
    """按路径去重追加候选项。"""
    if any(existing.path == candidate.path for existing in candidates):
        return
    candidates.append(candidate)


def has_rebuildable_parent(path: Path, stop_root: Path) -> bool:
    """判断路径是否位于已整体清理的可重建父目录内。"""
    for parent in path.parents:
        if parent == stop_root:
            return False
        if parent.name in REBUILDABLE_DIR_NAMES:
            return True
    return False


def discover_git_garbage(documents_work_root: Path) -> list[CleanupCandidate]:
    """发现 Documents/work 根仓库中遗留的 Git 临时 pack 文件。"""
    pack_root = documents_work_root / ".git" / "objects" / "pack"
    if not pack_root.exists():
        return []

    return [
        build_candidate(path, "git_tmp_pack", "git_garbage_tmp_pack", "low")
        for path in sorted(pack_root.glob("tmp_pack_*"))
        if path.is_file()
    ]


def discover_dev_candidates(dev_root: Path, include_assets: bool) -> list[CleanupCandidate]:
    """发现 DEV 目录下的可重建依赖、缓存、构建产物和可选业务资产。"""
    candidates: list[CleanupCandidate] = []
    if not dev_root.exists():
        return candidates

    for path in iter_named_directories(dev_root, REBUILDABLE_DIR_NAMES):
        if has_tracked_files(path):
            append_unique(candidates, build_skipped_candidate(path, "rebuildable_cache", "contains_git_tracked_files"))
            continue
        append_unique(candidates, build_candidate(path, "rebuildable_cache", f"matched_{path.name}", "low"))

    for path in iter_named_directories(dev_root, GENERATED_DIR_NAMES):
        if has_rebuildable_parent(path, dev_root):
            continue
        if has_tracked_files(path):
            append_unique(candidates, build_skipped_candidate(path, "generated_output", "contains_git_tracked_files"))
            continue
        append_unique(candidates, build_candidate(path, "generated_output", f"matched_{path.name}", "low"))

    for relative_path in EXACT_CONSERVATIVE_PATHS:
        path = dev_root / relative_path
        if path.exists():
            append_unique(candidates, build_candidate(path, "generated_output", "known_rebuildable_path", "low"))

    if include_assets:
        for relative_path in EXACT_AGGRESSIVE_PATHS:
            path = dev_root / relative_path
            if path.exists():
                append_unique(candidates, build_candidate(path, "aggressive_asset", "include_assets_enabled", "medium"))

    return sorted(candidates, key=lambda item: str(item.path))


def discover_candidates(
    documents_work_root: Path,
    dev_root: Path,
    include_assets: bool,
) -> list[CleanupCandidate]:
    """汇总所有清理候选项。"""
    candidates = discover_git_garbage(documents_work_root)
    for candidate in discover_dev_candidates(dev_root, include_assets):
        append_unique(candidates, candidate)
    return sorted(candidates, key=lambda item: str(item.path))


def delete_path(path: Path) -> None:
    """删除文件、符号链接或目录。"""
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
        return
    path.unlink()


def apply_cleanup(candidates: list[CleanupCandidate]) -> None:
    """执行删除动作，只处理 planned 状态的候选项。"""
    for candidate in candidates:
        if candidate.status != "planned":
            continue
        if not candidate.path.exists():
            candidate.status = "missing"
            continue
        try:
            delete_path(candidate.path)
            candidate.status = "deleted"
        except OSError as error:
            candidate.status = "failed"
            candidate.error = str(error)


def summarize_candidates(candidates: list[CleanupCandidate]) -> dict[str, int]:
    """汇总候选项执行状态。"""
    summary = {
        "planned": 0,
        "deleted": 0,
        "skipped": 0,
        "missing": 0,
        "failed": 0,
        "bytes_planned": 0,
        "bytes_deleted": 0,
    }
    for candidate in candidates:
        if candidate.status in summary:
            summary[candidate.status] += 1
        if candidate.status == "planned":
            summary["bytes_planned"] += candidate.size_bytes
        elif candidate.status == "deleted":
            summary["bytes_deleted"] += candidate.size_bytes
    return summary


def load_file_organizer_core() -> ModuleType:
    """加载文件整理核心模块，复用既有规则而不是复制一份。"""
    global FILE_ORGANIZER_CORE_MODULE
    if FILE_ORGANIZER_CORE_MODULE is not None:
        return FILE_ORGANIZER_CORE_MODULE
    if not FILE_ORGANIZER_CORE_PATH.exists():
        raise RuntimeError(f"file_organizer_core not found: {FILE_ORGANIZER_CORE_PATH}")

    module_name = "_idefeng_file_organizer_core"
    spec = importlib.util.spec_from_file_location(module_name, FILE_ORGANIZER_CORE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load file_organizer_core: {FILE_ORGANIZER_CORE_PATH}")

    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    FILE_ORGANIZER_CORE_MODULE = module
    return module


def build_file_organizer_section(
    dry_run: bool,
    source_rules: Iterable[Any] | None = None,
    pending_path: Path | None = None,
    report_path: Path | None = None,
    write_standalone_report: bool = True,
    ensure_destinations: bool = True,
) -> dict[str, object]:
    """执行或演练文件整理，并返回可并入主报告的结果。"""
    organizer = load_file_organizer_core()
    if ensure_destinations:
        organizer.ensure_directories()

    selected_source_rules = list(source_rules if source_rules is not None else organizer.load_source_rules())
    source_results = []
    all_pending_directories = []

    for source_rule in selected_source_rules:
        actions, pending_directories, skipped_entries = organizer.process_source(
            source_rule.path,
            dry_run=dry_run,
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

    pending_target = organizer.write_pending_directories(
        all_pending_directories,
        pending_path or organizer.PENDING_DIRECTORIES_PATH,
    )
    report = organizer.build_report(dry_run=dry_run, source_results=source_results)
    report["pending_directories_path"] = str(pending_target)
    if write_standalone_report:
        report["report_path"] = str(organizer.write_report(report, report_path))
    elif report_path is not None:
        report["report_path"] = str(report_path)
    else:
        report["report_path"] = None
    return report


def normalize_btm_value(value: str) -> str | None:
    """规范化 sfltool 字段值。"""
    stripped = value.strip()
    if stripped == "(null)" or not stripped:
        return None
    return stripped


def strip_hex_suffix(value: str | None) -> str | None:
    """移除 `legacy agent (0x10008)` 这类类型字段里的十六进制后缀。"""
    if value is None:
        return None
    return value.split(" (0x", 1)[0].strip()


def file_url_to_path(value: str | None) -> Path | None:
    """把 file URL 转换成本地路径。"""
    if value is None:
        return None
    parsed = urlparse(value)
    if parsed.scheme != "file":
        return None
    return Path(unquote(parsed.path))


def optional_path(value: str | None) -> Path | None:
    """把普通路径字段转换为 Path。"""
    if value is None or not value.startswith("/"):
        return None
    return Path(value)


def build_login_item_record(uid: str, fields: dict[str, str | None]) -> LoginItemRecord:
    """从 sfltool 字段构造登录项记录。"""
    url = fields.get("URL")
    executable_path = fields.get("Executable Path")
    return LoginItemRecord(
        uid=uid,
        uuid=fields.get("UUID"),
        name=fields.get("Name"),
        developer_name=fields.get("Developer Name"),
        item_type=strip_hex_suffix(fields.get("Type")),
        disposition=fields.get("Disposition"),
        identifier=fields.get("Identifier"),
        url=url,
        url_path=file_url_to_path(url),
        executable_path=optional_path(executable_path),
        parent_identifier=fields.get("Parent Identifier"),
        bundle_identifier=fields.get("Bundle Identifier"),
    )


def parse_btm_dump(output: str) -> list[LoginItemRecord]:
    """解析 `sfltool dumpbtm` 输出。"""
    records: list[LoginItemRecord] = []
    current_uid: str | None = None
    current_fields: dict[str, str | None] | None = None

    def flush_record() -> None:
        if current_uid is None or current_fields is None:
            return
        records.append(build_login_item_record(current_uid, current_fields))

    for raw_line in output.splitlines():
        line = raw_line.strip()
        if line.startswith("Records for UID"):
            flush_record()
            current_fields = None
            current_uid = line.split("Records for UID", 1)[1].split(":", 1)[0].strip()
            continue

        if line.startswith("#") and line.endswith(":"):
            flush_record()
            current_fields = {}
            continue

        if current_fields is None or ":" not in line:
            continue

        key, value = line.split(":", 1)
        current_fields[key.strip()] = normalize_btm_value(value)

    flush_record()
    return records


def login_record_haystack(record: LoginItemRecord) -> str:
    """把记录中的主要字段合并成小写匹配文本。"""
    values = [
        record.name,
        record.developer_name,
        record.identifier,
        record.url,
        str(record.executable_path) if record.executable_path else None,
        record.parent_identifier,
        record.bundle_identifier,
    ]
    return " ".join(value for value in values if value).lower()


def classify_login_item(record: LoginItemRecord) -> tuple[str, str, str, str]:
    """返回登录项分类、建议动作、风险等级和原因。"""
    haystack = login_record_haystack(record)

    if "com.idefeng." in haystack:
        return "own_automation", "keep", "low", "local_automation"

    if "uninstaller" in haystack or "letsgo" in haystack:
        return "possible_remnant", "manual_review", "medium", "uninstaller_or_removed_app_marker"

    if record.url_path and str(record.url_path).startswith("/Library/Launch"):
        return "system_background_item", "manual_review_admin", "medium", "root_level_launchd_item"

    if record.url_path and str(record.url_path).startswith(str(Path.home() / "Library" / "LaunchAgents")):
        return "user_launch_agent", "manual_review", "low", "user_launch_agent"

    if record.item_type in {"app", "login item", "dock tile", "quicklook", "spotlight", "background app refresh"}:
        return "app_managed_component", "keep", "low", "app_registered_component"

    return "background_item", "manual_review", "medium", "unclassified_background_item"


def record_to_report_item(record: LoginItemRecord) -> dict[str, object]:
    """把登录项记录转换为报告项。"""
    category, suggested_action, risk_level, reason = classify_login_item(record)
    return {
        "uid": record.uid,
        "uuid": record.uuid,
        "display_name": record.display_name,
        "name": record.name,
        "developer_name": record.developer_name,
        "item_type": record.item_type,
        "disposition": record.disposition,
        "identifier": record.identifier,
        "url": record.url,
        "url_path": str(record.url_path) if record.url_path else None,
        "executable_path": str(record.executable_path) if record.executable_path else None,
        "parent_identifier": record.parent_identifier,
        "bundle_identifier": record.bundle_identifier,
        "category": category,
        "suggested_action": suggested_action,
        "risk_level": risk_level,
        "classification_reason": reason,
    }


def build_duplicate_display_names(records: list[LoginItemRecord]) -> list[dict[str, object]]:
    """按显示名汇总重复项。"""
    grouped: dict[str, list[LoginItemRecord]] = {}
    for record in records:
        grouped.setdefault(record.display_name, []).append(record)

    duplicates = []
    for display_name, items in grouped.items():
        if display_name == "(unknown)" or len(items) < 2:
            continue
        duplicates.append(
            {
                "display_name": display_name,
                "count": len(items),
                "identifiers": [item.identifier for item in items],
            }
        )
    return sorted(duplicates, key=lambda item: (-int(item["count"]), str(item["display_name"]).lower()))


def read_launch_plist(path: Path) -> dict[str, object] | None:
    """读取单个 LaunchAgent/Daemon plist 的核心信息。"""
    try:
        with path.open("rb") as handle:
            payload = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException):
        return None

    program_arguments = payload.get("ProgramArguments")
    program = payload.get("Program")
    executable = program
    if executable is None and isinstance(program_arguments, list) and program_arguments:
        executable = program_arguments[0]

    return {
        "path": str(path),
        "label": payload.get("Label"),
        "program": program,
        "program_arguments": program_arguments,
        "executable": executable,
        "root_level": str(path).startswith("/Library/"),
    }


def scan_launch_plists(launch_roots: Iterable[Path]) -> list[dict[str, object]]:
    """扫描 LaunchAgents 与 LaunchDaemons plist 元数据。"""
    plists: list[dict[str, object]] = []
    for root in launch_roots:
        if not root.exists():
            continue
        for path in sorted(root.glob("*.plist")):
            plist_record = read_launch_plist(path)
            if plist_record is not None:
                plists.append(plist_record)
    return plists


def run_sfltool_dumpbtm() -> tuple[str, str | None]:
    """执行 sfltool dumpbtm 并返回输出和错误信息。"""
    result = subprocess.run(["sfltool", "dumpbtm"], text=True, capture_output=True, check=False)
    error = result.stderr.strip() or None
    return result.stdout, error


def build_login_items_summary(items: list[dict[str, object]], launch_plists: list[dict[str, object]]) -> dict[str, int]:
    """汇总登录项报告。"""
    return {
        "item_count": len(items),
        "launch_plist_count": len(launch_plists),
        "own_automation_count": sum(1 for item in items if item["category"] == "own_automation"),
        "possible_remnant_count": sum(1 for item in items if item["category"] == "possible_remnant"),
        "manual_review_count": sum(
            1
            for item in items
            if item["suggested_action"] in {"manual_review", "manual_review_admin"}
        ),
    }


def build_login_items_section(
    btm_output: str | None = None,
    launch_roots: Iterable[Path] | None = None,
) -> dict[str, object]:
    """构建登录项与后台活动只读报告。"""
    sfltool_error = None
    if btm_output is None:
        btm_output, sfltool_error = run_sfltool_dumpbtm()

    records = parse_btm_dump(btm_output)
    items = [record_to_report_item(record) for record in records]
    launch_plists = scan_launch_plists(launch_roots if launch_roots is not None else DEFAULT_LAUNCH_ROOTS)

    return {
        "mode": "read_only",
        "sfltool_error": sfltool_error,
        "summary": build_login_items_summary(items, launch_plists),
        "duplicate_display_names": build_duplicate_display_names(records),
        "items": items,
        "launch_plists": launch_plists,
    }


def build_cleanup_report(
    documents_work_root: Path = DEFAULT_DOCUMENTS_WORK_ROOT,
    dev_root: Path = DEFAULT_DEV_ROOT,
    apply: bool = False,
    include_assets: bool = False,
    include_login_items: bool = False,
    include_file_organizer: bool = False,
    skip_disk_cleanup: bool = False,
    file_organizer_source_rules: Iterable[Any] | None = None,
    file_organizer_write_standalone_report: bool = True,
    file_organizer_ensure_destinations: bool = True,
) -> dict[str, object]:
    """构建清理报告，并在 apply=True 时执行删除。"""
    candidates = [] if skip_disk_cleanup else discover_candidates(documents_work_root, dev_root, include_assets)
    if apply:
        apply_cleanup(candidates)

    report: dict[str, object] = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "apply": apply,
        "include_assets": include_assets,
        "include_login_items": include_login_items,
        "include_file_organizer": include_file_organizer,
        "skip_disk_cleanup": skip_disk_cleanup,
        "documents_work_root": str(documents_work_root),
        "dev_root": str(dev_root),
        "summary": summarize_candidates(candidates),
        "candidates": [candidate.to_dict() for candidate in candidates],
    }
    if include_login_items:
        report["login_items"] = build_login_items_section()
    if include_file_organizer:
        report["file_organizer"] = build_file_organizer_section(
            dry_run=not apply,
            source_rules=file_organizer_source_rules,
            write_standalone_report=file_organizer_write_standalone_report,
            ensure_destinations=file_organizer_ensure_destinations,
        )
    return report


def build_default_report_path() -> Path:
    """生成默认报告路径。"""
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    return REPORT_ROOT / f"disk-cleanup-{timestamp}.json"


def write_report(report: dict[str, object], report_path: Path) -> Path:
    """写入 JSON 报告并刷新 latest.json。"""
    report_path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(report, ensure_ascii=False, indent=2)
    report_path.write_text(payload, encoding="utf-8")
    (REPORT_ROOT / "latest.json").write_text(payload, encoding="utf-8")
    return report_path


def parse_args() -> argparse.Namespace:
    """解析命令行参数。"""
    parser = argparse.ArgumentParser(description="清理 Documents/work 与 DEV 下的可重建磁盘占用")
    parser.add_argument("--apply", action="store_true", help="真正执行删除；默认只生成预览报告")
    parser.add_argument("--include-assets", action="store_true", help="同时清理 course_assets 和 release 交付包")
    parser.add_argument("--login-items", action="store_true", help="额外生成登录项与后台活动只读报告")
    parser.add_argument("--organize-files", action="store_true", help="同时执行或演练文件整理")
    parser.add_argument("--skip-disk-cleanup", action="store_true", help="只运行附加功能，不扫描或清理磁盘缓存候选项")
    parser.add_argument("--json", action="store_true", help="输出完整 JSON 报告")
    parser.add_argument("--documents-work-root", type=Path, default=DEFAULT_DOCUMENTS_WORK_ROOT)
    parser.add_argument("--dev-root", type=Path, default=DEFAULT_DEV_ROOT)
    parser.add_argument("--report-path", type=Path, default=None)
    return parser.parse_args()


def main() -> int:
    """CLI 入口。"""
    args = parse_args()
    ensure_runtime_directories()

    report = build_cleanup_report(
        documents_work_root=args.documents_work_root,
        dev_root=args.dev_root,
        apply=args.apply,
        include_assets=args.include_assets,
        include_login_items=args.login_items,
        include_file_organizer=args.organize_files,
        skip_disk_cleanup=args.skip_disk_cleanup,
    )
    report_path = write_report(report, args.report_path or build_default_report_path())

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        summary = report["summary"]
        print(f"report_path={report_path}")
        print(f"apply={report['apply']}")
        print(f"include_assets={report['include_assets']}")
        print(f"include_login_items={report['include_login_items']}")
        print(f"include_file_organizer={report['include_file_organizer']}")
        print(f"skip_disk_cleanup={report['skip_disk_cleanup']}")
        print(
            "summary="
            f"planned:{summary['planned']} "
            f"deleted:{summary['deleted']} "
            f"skipped:{summary['skipped']} "
            f"failed:{summary['failed']}"
        )
        if args.login_items:
            login_summary = report["login_items"]["summary"]  # type: ignore[index]
            print(
                "login_items="
                f"items:{login_summary['item_count']} "
                f"possible_remnants:{login_summary['possible_remnant_count']} "
                f"manual_review:{login_summary['manual_review_count']}"
            )
        if args.organize_files:
            organizer_summary = report["file_organizer"]["summary"]  # type: ignore[index]
            print(
                "file_organizer="
                f"actions:{organizer_summary['action_count']} "
                f"pending_directories:{organizer_summary['pending_directory_count']} "
                f"skipped:{organizer_summary['skipped_count']}"
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
