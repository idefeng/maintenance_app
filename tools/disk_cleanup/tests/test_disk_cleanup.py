import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from disk_cleanup import (  # type: ignore
    build_cleanup_report,
    build_file_organizer_section,
    build_login_items_section,
    discover_candidates,
    has_tracked_files,
    parse_btm_dump,
    summarize_candidates,
)


class DiskCleanupTests(unittest.TestCase):
    """磁盘清理规则测试。"""

    def test_discovers_git_tmp_pack_garbage(self) -> None:
        """Documents/work 下的 Git 临时 pack 垃圾应被识别。"""
        with TemporaryDirectory() as temp_dir:
            work_root = Path(temp_dir) / "work"
            pack_root = work_root / ".git" / "objects" / "pack"
            pack_root.mkdir(parents=True)
            garbage = pack_root / "tmp_pack_demo"
            garbage.write_bytes(b"x" * 128)

            candidates = discover_candidates(work_root, Path(temp_dir) / "DEV", include_assets=False)

            self.assertEqual(len(candidates), 1)
            self.assertEqual(candidates[0].path, garbage)
            self.assertEqual(candidates[0].category, "git_tmp_pack")

    def test_conservative_mode_discovers_rebuildable_dev_directories(self) -> None:
        """保守模式应识别可重建的开发依赖与缓存目录。"""
        with TemporaryDirectory() as temp_dir:
            dev_root = Path(temp_dir) / "DEV"
            node_modules = dev_root / "demo" / "node_modules"
            next_cache = dev_root / "web" / ".next"
            node_modules.mkdir(parents=True)
            next_cache.mkdir(parents=True)

            candidates = discover_candidates(Path(temp_dir) / "work", dev_root, include_assets=False)
            paths = {candidate.path for candidate in candidates}

            self.assertIn(node_modules, paths)
            self.assertIn(next_cache, paths)

    def test_assets_and_release_require_include_assets(self) -> None:
        """业务资产和交付包只应在激进模式中纳入清理。"""
        with TemporaryDirectory() as temp_dir:
            dev_root = Path(temp_dir) / "DEV"
            course_assets = dev_root / "ETLChina" / "BAResoucesSystem" / "course_assets"
            release = dev_root / "ETLChina" / "大资源平台" / "automation" / "release"
            course_assets.mkdir(parents=True)
            release.mkdir(parents=True)

            conservative = discover_candidates(Path(temp_dir) / "work", dev_root, include_assets=False)
            aggressive = discover_candidates(Path(temp_dir) / "work", dev_root, include_assets=True)

            self.assertNotIn(course_assets, {candidate.path for candidate in conservative})
            self.assertNotIn(release, {candidate.path for candidate in conservative})
            self.assertIn(course_assets, {candidate.path for candidate in aggressive})
            self.assertIn(release, {candidate.path for candidate in aggressive})

    def test_generated_directories_inside_rebuildable_parents_are_not_duplicated(self) -> None:
        """node_modules 已命中时，其内部 dist/build 不应重复进入候选清单。"""
        with TemporaryDirectory() as temp_dir:
            dev_root = Path(temp_dir) / "DEV"
            nested_dist = dev_root / "demo" / "node_modules" / "pkg" / "dist"
            nested_dist.mkdir(parents=True)

            candidates = discover_candidates(Path(temp_dir) / "work", dev_root, include_assets=False)
            paths = {candidate.path for candidate in candidates}

            self.assertIn(dev_root / "demo" / "node_modules", paths)
            self.assertNotIn(nested_dist, paths)

    def test_git_tracked_directories_are_reported_but_not_counted_as_deletable(self) -> None:
        """包含 Git 跟踪文件的构建目录应跳过，避免误删源码资产。"""
        with TemporaryDirectory() as temp_dir:
            repo = Path(temp_dir) / "repo"
            build_dir = repo / "build"
            build_dir.mkdir(parents=True)
            tracked_icon = build_dir / "icon.png"
            tracked_icon.write_text("icon", encoding="utf-8")

            self.run_command(["git", "init"], cwd=repo)
            self.run_command(["git", "add", "build/icon.png"], cwd=repo)

            self.assertTrue(has_tracked_files(build_dir))

            candidates = discover_candidates(Path(temp_dir) / "work", repo, include_assets=False)
            build_candidate = next(candidate for candidate in candidates if candidate.path == build_dir)

            self.assertEqual(build_candidate.status, "skipped")
            self.assertEqual(build_candidate.reason, "contains_git_tracked_files")
            self.assertEqual(summarize_candidates(candidates)["skipped"], 1)

    def test_build_cleanup_report_defaults_to_dry_run(self) -> None:
        """默认报告应为 dry-run，不执行删除动作。"""
        with TemporaryDirectory() as temp_dir:
            dev_root = Path(temp_dir) / "DEV"
            node_modules = dev_root / "demo" / "node_modules"
            node_modules.mkdir(parents=True)

            report = build_cleanup_report(
                documents_work_root=Path(temp_dir) / "work",
                dev_root=dev_root,
                apply=False,
                include_assets=False,
            )

            self.assertTrue(node_modules.exists())
            self.assertFalse(report["apply"])
            self.assertEqual(report["summary"]["planned"], 1)
            self.assertEqual(report["summary"]["deleted"], 0)

    def test_file_organizer_section_reuses_core_rules_in_dry_run(self) -> None:
        """主脚本应复用文件整理核心规则生成整理报告。"""
        with TemporaryDirectory() as temp_dir:
            source = Path(temp_dir) / "Downloads"
            source.mkdir()
            document = source / "继续医学教育-课程安排.docx"
            document.write_text("demo", encoding="utf-8")
            pending_path = Path(temp_dir) / "pending.json"

            section = build_file_organizer_section(
                dry_run=True,
                source_rules=[SimpleNamespace(path=source, recursive=False)],
                pending_path=pending_path,
                write_standalone_report=False,
                ensure_destinations=False,
            )

            self.assertTrue(document.exists())
            self.assertTrue(pending_path.exists())
            self.assertTrue(section["dry_run"])
            self.assertEqual(section["summary"]["action_count"], 1)
            self.assertEqual(section["sources"][0]["actions"][0]["status"], "dry-run")
            self.assertEqual(section["sources"][0]["actions"][0]["category"], "named_document")

    def test_build_cleanup_report_can_run_only_file_organizer(self) -> None:
        """主脚本应支持只运行文件整理，避免每日整理触发磁盘缓存清理。"""
        with TemporaryDirectory() as temp_dir:
            dev_root = Path(temp_dir) / "DEV"
            node_modules = dev_root / "demo" / "node_modules"
            node_modules.mkdir(parents=True)

            report = build_cleanup_report(
                documents_work_root=Path(temp_dir) / "work",
                dev_root=dev_root,
                apply=True,
                include_assets=False,
                include_file_organizer=True,
                skip_disk_cleanup=True,
                file_organizer_source_rules=[],
                file_organizer_write_standalone_report=False,
                file_organizer_ensure_destinations=False,
            )

            self.assertTrue(node_modules.exists())
            self.assertTrue(report["skip_disk_cleanup"])
            self.assertEqual(report["summary"]["planned"], 0)
            self.assertIn("file_organizer", report)

    def test_parse_btm_dump_extracts_login_item_fields(self) -> None:
        """sfltool dumpbtm 输出应解析为结构化登录项记录。"""
        dump = """
========================
 Records for UID 501 : FCA38B75-CB36-4BEF-ABC1-090616349C78
========================

 Items:

 #1:
                 UUID: 90E24AD5-B008-4F6C-BCA6-A5A119E8878A
                 Name: node
       Developer Name: (null)
                 Type: legacy agent (0x10008)
          Disposition: [enabled, allowed, notified] (0xb)
           Identifier: 8.ai.openclaw.gateway
                  URL: file:///Users/idefeng/Library/LaunchAgents/ai.openclaw.gateway.plist
      Executable Path: /opt/homebrew/opt/node/bin/node
    Parent Identifier: Unknown Developer
"""

        records = parse_btm_dump(dump)

        self.assertEqual(len(records), 1)
        self.assertEqual(records[0].uid, "501")
        self.assertEqual(records[0].name, "node")
        self.assertEqual(records[0].item_type, "legacy agent")
        self.assertEqual(records[0].identifier, "8.ai.openclaw.gateway")
        self.assertEqual(records[0].url_path, Path("/Users/idefeng/Library/LaunchAgents/ai.openclaw.gateway.plist"))
        self.assertEqual(records[0].executable_path, Path("/opt/homebrew/opt/node/bin/node"))
        self.assertEqual(records[0].parent_identifier, "Unknown Developer")

    def test_login_items_section_classifies_own_automation_and_remnants(self) -> None:
        """登录项报告应区分自有自动化和疑似卸载残留。"""
        dump = """
========================
 Records for UID 501 : FCA38B75-CB36-4BEF-ABC1-090616349C78
========================

 Items:

 #1:
                 UUID: 2350651A-D3F2-4E79-8963-43906D63EC8A
                 Name: osascript
       Developer Name: (null)
                 Type: legacy agent (0x10008)
          Disposition: [enabled, disallowed, notified] (0x9)
           Identifier: 8.com.idefeng.disk-cleanup
                  URL: file:///Users/idefeng/Library/LaunchAgents/com.idefeng.disk-cleanup.plist
      Executable Path: /usr/bin/osascript
    Parent Identifier: Unknown Developer

 #2:
                 UUID: D24422D4-FFDC-4B73-9EBA-CFF99AEE2A0B
                 Name: TeamViewer Uninstaller
       Developer Name: TeamViewer Germany GmbH
                 Type: legacy daemon (0x10010)
          Disposition: [enabled, disallowed, notified] (0x9)
           Identifier: 16.com.teamviewer.UninstallerWatcher
                  URL: file:///Library/LaunchDaemons/com.teamviewer.UninstallerWatcher.plist
      Executable Path: /Library/Application Support/TeamViewer/TeamViewerUninstaller.app/Contents/Helpers/com.teamviewer.UninstallerStarter
    Parent Identifier: TeamViewer Germany GmbH

 #3:
                 UUID: 4C2E66DC-965F-474F-80BA-BF287E35C098
                 Name: ToDesk
       Developer Name: Hainan Youqu Technology Co., Ltd.
                 Type: legacy agent (0x10008)
          Disposition: [enabled, disallowed, notified] (0x9)
           Identifier: 8.com.youqu.todesk.client.startup
                  URL: file:///Library/LaunchAgents/com.youqu.todesk.startup.plist
      Executable Path: /Applications/ToDesk.app/Contents/MacOS/ToDesk
    Parent Identifier: Hainan Youqu Technology Co., Ltd.

 #4:
                 UUID: 68FB919D-54F3-42C2-A0E3-42165525A8D6
                 Name: ToDesk
       Developer Name: Hainan Youqu Technology Co., Ltd.
                 Type: legacy agent (0x10008)
          Disposition: [enabled, disallowed, notified] (0x9)
           Identifier: 8.com.youqu.todesk.desktop
                  URL: file:///Library/LaunchAgents/com.youqu.todesk.session.plist
      Executable Path: /Applications/ToDesk.app/Contents/MacOS/ToDesk_Session_Proxy
    Parent Identifier: Hainan Youqu Technology Co., Ltd.
"""

        section = build_login_items_section(btm_output=dump, launch_roots=[])
        by_identifier = {item["identifier"]: item for item in section["items"]}

        self.assertEqual(by_identifier["8.com.idefeng.disk-cleanup"]["category"], "own_automation")
        self.assertEqual(by_identifier["8.com.idefeng.disk-cleanup"]["suggested_action"], "keep")
        self.assertEqual(by_identifier["16.com.teamviewer.UninstallerWatcher"]["category"], "possible_remnant")
        self.assertEqual(by_identifier["16.com.teamviewer.UninstallerWatcher"]["suggested_action"], "manual_review")
        self.assertEqual(section["summary"]["item_count"], 4)
        self.assertEqual(section["summary"]["possible_remnant_count"], 1)
        self.assertEqual(section["duplicate_display_names"][0]["display_name"], "ToDesk")
        self.assertEqual(section["duplicate_display_names"][0]["count"], 2)

    def run_command(self, command: list[str], cwd: Path) -> None:
        """运行测试用 Git 命令。"""
        import subprocess

        result = subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False)
        if result.returncode != 0:
            self.fail(f"command failed: {' '.join(command)}\n{result.stderr}")


if __name__ == "__main__":
    unittest.main()
