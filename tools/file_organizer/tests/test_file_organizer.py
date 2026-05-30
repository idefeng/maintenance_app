import unittest
from pathlib import Path
import sys
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from file_organizer import (
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
    load_source_rules,
    pick_document_destination,
    process_source,
    resolve_collision,
    should_collect_pending_directory,
    write_pending_directories,
)


class FileOrganizerTests(unittest.TestCase):
    """文件整理规则测试。"""

    def test_destination_root_is_synology_drive_project_tree(self) -> None:
        """所有自动归档目标都应落在 Synology Drive 项目树下。"""
        self.assertEqual(
            PROJECT_ROOT,
            Path("/Users/idefeng/Library/CloudStorage/SynologyDrive-etlchina/A-项目管理"),
        )
        self.assertEqual(WORK_ROOT, PROJECT_ROOT)

    def test_source_rules_match_requested_roots_without_recursion(self) -> None:
        """来源目录应只包含三个固定路径，且全部只扫描第一层。"""
        self.assertEqual(
            [(rule.path, rule.recursive) for rule in SOURCE_RULES],
            [
                (Path("/Users/idefeng/Desktop"), False),
                (Path("/Users/idefeng/Downloads"), False),
                (Path("/Users/idefeng/Documents"), False),
            ],
        )

    def test_load_source_rules_adds_user_configured_roots_without_recursion(self) -> None:
        """用户在 App 中添加的来源目录应追加到整理来源，默认仍只扫描第一层。"""
        with TemporaryDirectory() as temp_dir:
            config_path = Path(temp_dir) / "source-rules.json"
            extra_path = Path(temp_dir) / "Inbox"
            config_path.write_text(
                '{"sources": [{"path": "' + str(extra_path) + '"}]}',
                encoding="utf-8",
            )

            source_rules = load_source_rules(config_path)

            self.assertIn((extra_path, False), [(rule.path, rule.recursive) for rule in source_rules])
            self.assertEqual(source_rules[: len(SOURCE_RULES)], SOURCE_RULES)

    def test_pick_document_destination_respects_rule_order(self) -> None:
        """包含多个关键词时，应优先命中更靠前的规则。"""
        destination = pick_document_destination("CME托育培训材料.pdf")
        self.assertEqual(
            destination,
            WORK_ROOT / "A-国家卫健委/1-能力建设和继续教育中心/1-资格认证处/托育项目",
        )

    def test_pick_document_destination_supports_case_insensitive_keyword(self) -> None:
        """英文关键词应支持大小写不敏感匹配。"""
        destination = pick_document_destination("cme-课程安排.docx")
        self.assertEqual(
            destination,
            WORK_ROOT / "A-国家卫健委/1-能力建设和继续教育中心/继续医学教育管理平台",
        )

    def test_pick_document_destination_falls_back_to_default(self) -> None:
        """未命中关键词时，应统一进入“其他信息”根目录。"""
        destination = pick_document_destination("普通资料.pdf")
        self.assertEqual(destination, DEFAULT_DOCUMENT_DESTINATION)

    def test_build_destination_for_application(self) -> None:
        """应用程序类文件应进入软件目录。"""
        category, destination = build_destination(Path("Installer.dmg"))
        self.assertEqual(category, "application")
        self.assertEqual(destination, APP_DESTINATION / "Installer.dmg")

    def test_build_destination_for_archive_application(self) -> None:
        """压缩包类文件也应按应用程序类文件归档。"""
        category, destination = build_destination(Path("托育素材包.zip"))
        self.assertEqual(category, "application")
        self.assertEqual(destination, APP_DESTINATION / "托育素材包.zip")

    def test_build_destination_for_synology_package(self) -> None:
        """Synology 安装包也应按应用程序类文件归档。"""
        category, destination = build_destination(Path("SynologyDrive.spk"))
        self.assertEqual(category, "application")
        self.assertEqual(destination, APP_DESTINATION / "SynologyDrive.spk")

    def test_build_destination_for_document(self) -> None:
        """文档类文件应按名称规则决定目录。"""
        category, destination = build_destination(Path("继续医学教育-课程安排.docx"))
        self.assertEqual(category, "named_document")
        self.assertEqual(
            destination,
            WORK_ROOT
            / "A-国家卫健委/1-能力建设和继续教育中心/继续医学教育管理平台/继续医学教育-课程安排.docx",
        )

    def test_build_destination_for_unmatched_document(self) -> None:
        """未命中关键词的文档类文件应进入“其他信息”根目录。"""
        category, destination = build_destination(Path("会议纪要.pdf"))
        self.assertEqual(category, "other_info_document")
        self.assertEqual(destination, DEFAULT_DOCUMENT_DESTINATION / "会议纪要.pdf")

    def test_build_destination_for_unmatched_non_document_file(self) -> None:
        """非文档普通文件应跳过，不参与自动整理。"""
        self.assertIsNone(build_destination(Path("旅行照片.jpg")))

    def test_build_destination_for_named_non_document_file(self) -> None:
        """命中关键词的非文档普通文件也应跳过。"""
        self.assertIsNone(build_destination(Path("托育现场照片.jpg")))

    def test_build_destination_skips_system_metadata_files(self) -> None:
        """系统元数据文件不应参与自动整理。"""
        self.assertIsNone(build_destination(Path(".DS_Store")))
        self.assertIsNone(build_destination(Path(".localized")))

    def test_build_destination_for_unmatched_audio_file(self) -> None:
        """音频文件当前不在自动整理范围内。"""
        self.assertIsNone(build_destination(Path("访谈录音.m4a")))

    def test_build_destination_for_unmatched_video_file(self) -> None:
        """视频文件当前不在自动整理范围内。"""
        self.assertIsNone(build_destination(Path("培训录像.mov")))

    def test_resolve_collision_keeps_original_when_target_is_free(self) -> None:
        """目标不存在时不应修改文件名。"""
        destination = resolve_collision(Path("/tmp/free-target.txt"))
        self.assertEqual(destination, Path("/tmp/free-target.txt"))

    def test_resolve_collision_adds_incremental_suffix(self) -> None:
        """目标已存在时，应追加递增后缀避免覆盖。"""
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            original = root / "资料.pdf"
            original.write_text("occupied", encoding="utf-8")

            resolved = resolve_collision(original)

            self.assertEqual(resolved, root / "资料_1.pdf")

    def test_collect_entries_for_non_recursive_source_only_returns_first_level(self) -> None:
        """非递归来源目录不应返回子目录中的嵌套文件。"""
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            nested_dir = root / "nested"
            nested_dir.mkdir()
            nested_file = nested_dir / "睡眠记录.pdf"
            nested_file.write_text("demo", encoding="utf-8")
            root_file = root / "继续医学教育-课程安排.docx"
            root_file.write_text("demo", encoding="utf-8")

            entries = collect_entries(root, recursive=False)

            self.assertEqual(entries, [nested_dir, root_file])

    def test_process_source_collects_pending_directories_for_non_recursive_source(self) -> None:
        """非递归来源目录应把普通子目录写入待处理列表。"""
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pending_dir = root / "folder"
            pending_dir.mkdir()
            (root / "普通资料.pdf").write_text("demo", encoding="utf-8")

            _, pending_directories, _ = process_source(root, dry_run=True, recursive=False)

            self.assertEqual(
                pending_directories,
                [{"source_root": str(root), "directory": str(pending_dir)}],
            )

    def test_should_collect_pending_directory_skips_recursive_source_paths(self) -> None:
        """来源根目录本身不应误判为待处理子目录。"""
        for source_rule in SOURCE_RULES:
            self.assertFalse(should_collect_pending_directory(source_rule.path))

    def test_should_collect_pending_directory_skips_managed_destination_paths(self) -> None:
        """工具自身的目标目录不应进入待处理列表。"""
        self.assertFalse(should_collect_pending_directory(APP_DESTINATION))
        self.assertFalse(should_collect_pending_directory(WORK_ROOT))

    def test_write_pending_directories_updates_stable_latest_file(self) -> None:
        """待处理列表应写入带元数据的固定文件。"""
        with TemporaryDirectory() as temp_dir:
            pending_path = Path(temp_dir) / "pending.json"
            payload = [{"source_root": "/tmp/source", "directory": "/tmp/source/folder"}]

            returned_path = write_pending_directories(payload, pending_path)

            self.assertTrue(pending_path.exists())
            self.assertEqual(returned_path, pending_path)
            self.assertNotEqual(PENDING_DIRECTORIES_PATH, pending_path)
            content = pending_path.read_text(encoding="utf-8")
            self.assertIn('"count": 1', content)
            self.assertIn('"directories"', content)

    def test_build_report_contains_summary_and_source_breakdown(self) -> None:
        """运行报告应包含汇总信息与来源维度统计。"""
        actions = [
            FileAction(
                source="/tmp/source/a.zip",
                destination="/tmp/destination/a.zip",
                category="document",
                status="dry-run",
                reason="matched_rule",
            )
        ]
        pending_directories = [{"source_root": "/tmp/source", "directory": "/tmp/source/folder"}]
        skipped_entries = [{"path": "/tmp/source/subdir", "reason": "unsupported_or_out_of_scope"}]

        report = build_report(
            dry_run=True,
            source_results=[
                {
                    "source": "/tmp/source",
                    "recursive": False,
                    "actions": actions,
                    "pending_directories": pending_directories,
                    "skipped_entries": skipped_entries,
                }
            ],
        )

        self.assertTrue(str(REPORT_ROOT / "latest.json").endswith("latest.json"))
        self.assertEqual(report["summary"]["action_count"], 1)
        self.assertEqual(report["summary"]["pending_directory_count"], 1)
        self.assertEqual(report["summary"]["skipped_count"], 1)
        self.assertEqual(report["sources"][0]["action_count"], 1)
        self.assertEqual(report["sources"][0]["pending_directory_count"], 1)
        self.assertEqual(report["sources"][0]["skipped_count"], 1)


if __name__ == "__main__":
    unittest.main()
