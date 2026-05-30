"""本地文件整理工具核心逻辑。"""

from __future__ import annotations

import json
import shutil
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable


TOOL_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = Path("/Users/idefeng/Library/CloudStorage/SynologyDrive-etlchina/A-项目管理")
APP_DESTINATION = PROJECT_ROOT / "其他信息" / "软件安装包"
WORK_ROOT = PROJECT_ROOT
RUNTIME_ROOT = TOOL_ROOT / "runtime"
REPORT_ROOT = RUNTIME_ROOT / "reports"
LOG_ROOT = RUNTIME_ROOT / "logs"
CONFIG_ROOT = RUNTIME_ROOT / "config"
SOURCE_RULES_CONFIG_PATH = CONFIG_ROOT / "source-rules.json"
PENDING_DIRECTORIES_PATH = REPORT_ROOT / "pending-directories-latest.json"
OTHER_INFO_ROOT = WORK_ROOT / "其他信息"

APP_EXTENSIONS = {
    ".app",
    ".dmg",
    ".pkg",
    ".mpkg",
    ".spk",
    ".iso",
    ".zip",
    ".rar",
    ".7z",
    ".tar",
    ".gz",
    ".bz2",
    ".xz",
}
DOCUMENT_EXTENSIONS = {
    ".pdf",
    ".doc",
    ".docx",
    ".xls",
    ".xlsx",
    ".ppt",
    ".pptx",
    ".txt",
    ".md",
    ".rtf",
    ".csv",
    ".tsv",
    ".pages",
    ".numbers",
    ".key",
}
IGNORED_FILE_NAMES = {".ds_store", ".localized"}


@dataclass(frozen=True)
class DocumentRule:
    """定义单条文档归档规则。"""

    keywords: tuple[str, ...]
    destination: Path


DOCUMENT_RULES = [
    DocumentRule(
        ("托育",),
        WORK_ROOT / "A-国家卫健委/1-能力建设和继续教育中心/1-资格认证处/托育项目",
    ),
    DocumentRule(
        ("睡眠",),
        WORK_ROOT / "A-国家卫健委/1-能力建设和继续教育中心/睡眠医学人才",
    ),
    DocumentRule(
        ("继续医学教育", "cme"),
        WORK_ROOT / "A-国家卫健委/1-能力建设和继续教育中心/继续医学教育管理平台",
    ),
    DocumentRule(
        ("培训统筹",),
        WORK_ROOT / "A-国家卫健委/1-能力建设和继续教育中心/培训统筹办公室",
    ),
    DocumentRule(
        ("可验证",),
        WORK_ROOT / "A-国家卫健委/1-能力建设和继续教育中心/可验证自学",
    ),
    DocumentRule(
        ("中医药",),
        WORK_ROOT / "A-国家卫健委/2-中医药管理局",
    ),
    DocumentRule(("工业互联网",), WORK_ROOT / "G-工业互联网研究院"),
    DocumentRule(("博奥教育",), OTHER_INFO_ROOT / "公司信息"),
]
DEFAULT_DOCUMENT_DESTINATION = OTHER_INFO_ROOT


@dataclass(frozen=True)
class SourceRule:
    """定义来源目录及遍历方式。"""

    path: Path
    recursive: bool


SOURCE_RULES = [
    SourceRule(Path("/Users/idefeng/Desktop"), recursive=False),
    SourceRule(Path("/Users/idefeng/Downloads"), recursive=False),
    SourceRule(Path("/Users/idefeng/Documents"), recursive=False),
]

SOURCE_PATHS = {rule.path for rule in SOURCE_RULES}
RECURSIVE_SOURCE_PATHS = {rule.path for rule in SOURCE_RULES if rule.recursive}
MANAGED_DIRECTORIES = {
    APP_DESTINATION,
    WORK_ROOT,
    Path("/Users/idefeng/Documents/work"),
    Path("/Users/idefeng/Downloads/software"),
}


def load_additional_source_rules(config_path: Path = SOURCE_RULES_CONFIG_PATH) -> list[SourceRule]:
    """读取 App 追加的整理来源；默认只整理第一层，避免误扫整棵目录。"""
    if not config_path.exists():
        return []

    payload = json.loads(config_path.read_text(encoding="utf-8"))
    source_payloads = payload.get("sources", [])
    source_rules: list[SourceRule] = []

    for item in source_payloads:
        raw_path = item.get("path") if isinstance(item, dict) else None
        if not raw_path:
            continue
        path = Path(str(raw_path)).expanduser()
        source_rules.append(SourceRule(path, recursive=bool(item.get("recursive", False))))

    return source_rules


def load_source_rules(config_path: Path = SOURCE_RULES_CONFIG_PATH) -> list[SourceRule]:
    """合并默认来源和用户追加来源，并按路径去重。"""
    merged_rules = list(SOURCE_RULES)
    seen_paths = {rule.path for rule in merged_rules}

    for rule in load_additional_source_rules(config_path):
        if rule.path in seen_paths:
            continue
        merged_rules.append(rule)
        seen_paths.add(rule.path)

    return merged_rules


@dataclass
class FileAction:
    """记录单个文件处理动作。"""

    source: str
    destination: str
    category: str
    status: str
    reason: str


def ensure_directories() -> None:
    """确保运行过程所需目录存在。"""
    required_paths = {
        APP_DESTINATION,
        REPORT_ROOT,
        LOG_ROOT,
        DEFAULT_DOCUMENT_DESTINATION,
        *(rule.destination for rule in DOCUMENT_RULES),
    }
    for path in required_paths:
        path.mkdir(parents=True, exist_ok=True)


def iter_top_level_entries(source: Path) -> Iterable[Path]:
    """只遍历指定目录的第一层内容。"""
    if not source.exists():
        return []
    return sorted(source.iterdir(), key=lambda item: item.name.lower())


def collect_entries(source: Path, recursive: bool) -> list[Path]:
    """按来源规则收集需要处理的文件或应用目录。"""
    if not source.exists():
        return []

    if not recursive:
        return list(iter_top_level_entries(source))

    entries: list[Path] = []
    directories_to_visit = [source]

    while directories_to_visit:
        current = directories_to_visit.pop()
        for entry in sorted(current.iterdir(), key=lambda item: item.name.lower(), reverse=True):
            # 普通目录继续向下遍历，应用目录本身视为待处理对象。
            if entry.is_dir() and not entry.name.lower().endswith(".app"):
                directories_to_visit.append(entry)
                continue
            entries.append(entry)

    return sorted(entries, key=lambda item: str(item).lower())


def is_application(entry: Path) -> bool:
    """判断是否属于应用程序类文件。"""
    return entry.suffix.lower() in APP_EXTENSIONS or (
        entry.is_dir() and entry.name.lower().endswith(".app")
    )


def is_document(entry: Path) -> bool:
    """判断是否属于文档类文件。"""
    return not entry.is_dir() and entry.suffix.lower() in DOCUMENT_EXTENSIONS


def is_ignored_entry(entry: Path) -> bool:
    """过滤 Finder 生成的系统元数据文件，避免把噪声一起归档。"""
    return not entry.is_dir() and entry.name.lower() in IGNORED_FILE_NAMES


def pick_rule_destination(file_name: str) -> Path | None:
    """按规则顺序匹配文件名关键词，返回命中的目标目录。"""
    lowered_name = file_name.lower()
    for rule in DOCUMENT_RULES:
        if any(keyword in lowered_name for keyword in rule.keywords):
            return rule.destination
    return None


def pick_document_destination(file_name: str) -> Path:
    """按规则顺序决定文档文件去向。"""
    matched_destination = pick_rule_destination(file_name)
    if matched_destination is not None:
        return matched_destination
    # 未命中文件名关键词的文档统一进入“其他信息”根目录，保持规则简单稳定。
    return DEFAULT_DOCUMENT_DESTINATION


def build_destination(entry: Path) -> tuple[str, Path] | None:
    """返回文件分类及目标路径。"""
    if is_ignored_entry(entry):
        return None
    if is_application(entry):
        return "application", APP_DESTINATION / entry.name
    if entry.is_dir():
        return None
    if is_document(entry):
        matched_destination = pick_rule_destination(entry.name)
        if matched_destination is not None:
            # 文档类文件命中关键词时，优先进入对应项目目录。
            return "named_document", matched_destination / entry.name
        return "other_info_document", pick_document_destination(entry.name) / entry.name
    # 当前合同只要求自动整理应用程序类和文档类文件，其他文件保留原位并记入跳过清单。
    return None


def resolve_collision(destination: Path) -> Path:
    """目标重名时自动追加递增后缀，避免覆盖已有文件。"""
    if not destination.exists():
        return destination

    counter = 1
    while True:
        candidate = destination.with_name(f"{destination.stem}_{counter}{destination.suffix}")
        if not candidate.exists():
            return candidate
        counter += 1


def move_entry(source: Path, destination: Path, dry_run: bool) -> str:
    """移动文件；如果是演练模式则只返回模拟结果。"""
    if dry_run:
        return "dry-run"
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source), str(destination))
    return "moved"


def should_collect_pending_directory(entry: Path) -> bool:
    """判断子目录是否应进入待处理列表。"""
    if not entry.is_dir() or entry.name.lower().endswith(".app"):
        return False
    if entry in SOURCE_PATHS:
        return False
    return entry not in RECURSIVE_SOURCE_PATHS and entry not in MANAGED_DIRECTORIES


def collect_pending_directories(source: Path, pending_directories: list[dict[str, str]]) -> None:
    """记录未递归处理的普通子目录。"""
    for entry in iter_top_level_entries(source):
        if should_collect_pending_directory(entry):
            pending_directories.append(
                {
                    "source_root": str(source),
                    "directory": str(entry),
                }
            )


def process_source(
    source: Path,
    dry_run: bool,
    recursive: bool,
) -> tuple[list[FileAction], list[dict[str, str]], list[dict[str, str]]]:
    """处理单个来源目录。"""
    actions: list[FileAction] = []
    pending_directories: list[dict[str, str]] = []
    skipped_entries: list[dict[str, str]] = []

    if not source.exists():
        skipped_entries.append({"path": str(source), "reason": "source_missing"})
        return actions, pending_directories, skipped_entries

    if not recursive:
        collect_pending_directories(source, pending_directories)

    for entry in collect_entries(source, recursive=recursive):
        target = build_destination(entry)
        if target is None:
            if entry.is_dir() and not entry.name.lower().endswith(".app"):
                continue
            skipped_entries.append({"path": str(entry), "reason": "unsupported_or_out_of_scope"})
            continue

        category, destination = target
        final_destination = resolve_collision(destination)
        status = move_entry(entry, final_destination, dry_run)
        actions.append(
            FileAction(
                source=str(entry),
                destination=str(final_destination),
                category=category,
                status=status,
                reason="matched_rule",
            )
        )

    return actions, pending_directories, skipped_entries


def build_report(dry_run: bool, source_results: list[dict]) -> dict:
    """构造统一的 JSON 运行报告。"""
    source_reports = []
    action_count = 0
    pending_directory_count = 0
    skipped_count = 0

    for source_result in source_results:
        actions = source_result["actions"]
        pending_directories = source_result["pending_directories"]
        skipped_entries = source_result["skipped_entries"]

        action_count += len(actions)
        pending_directory_count += len(pending_directories)
        skipped_count += len(skipped_entries)
        source_reports.append(
            {
                "source": source_result["source"],
                "recursive": source_result["recursive"],
                "action_count": len(actions),
                "pending_directory_count": len(pending_directories),
                "skipped_count": len(skipped_entries),
                "actions": [asdict(action) for action in actions],
                "pending_directories": pending_directories,
                "skipped_entries": skipped_entries,
            }
        )

    return {
        "tool": "file-organizer",
        "run_at": datetime.now().isoformat(timespec="seconds"),
        "dry_run": dry_run,
        "summary": {
            "source_count": len(source_reports),
            "action_count": action_count,
            "pending_directory_count": pending_directory_count,
            "skipped_count": skipped_count,
        },
        "sources": source_reports,
    }


def write_pending_directories(
    pending_directories: list[dict[str, str]],
    output_path: Path = PENDING_DIRECTORIES_PATH,
) -> Path:
    """把待处理子目录清单写入固定路径，便于人工后续处理。"""
    payload = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "count": len(pending_directories),
        "directories": pending_directories,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return output_path


def write_report(report: dict, report_path: Path | None = None) -> Path:
    """把整理结果写入 JSON 报告。"""
    timestamp = datetime.now().strftime("%Y%m%dT%H%M%S")
    target_path = report_path or REPORT_ROOT / f"file-organizer-{timestamp}.json"
    latest_path = REPORT_ROOT / "latest.json"
    target_path.parent.mkdir(parents=True, exist_ok=True)
    target_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    latest_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return target_path


def render_summary(report: dict, report_path: Path, pending_path: Path) -> str:
    """生成终端摘要输出。"""
    summary = report["summary"]
    lines = [
        f"执行时间: {report['run_at']}",
        f"演练模式: {'是' if report['dry_run'] else '否'}",
        f"来源目录数: {summary['source_count']}",
        f"处理文件数: {summary['action_count']}",
        f"待处理子目录数: {summary['pending_directory_count']}",
        f"跳过条目数: {summary['skipped_count']}",
        f"报告文件: {report_path}",
        f"待处理目录清单: {pending_path}",
    ]
    return "\n".join(lines)
