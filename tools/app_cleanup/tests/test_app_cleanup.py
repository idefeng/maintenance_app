import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from app_cleanup import (  # type: ignore
    REPORT_ROOT,
    ScanRoot,
    apply_cleanup_actions,
    build_report,
    find_matches_in_root,
    match_path,
    normalize_name,
    write_report,
)


class AppCleanupTests(unittest.TestCase):
    """应用残留扫描脚本测试。"""

    def test_normalize_name_removes_separators_and_lowercases(self) -> None:
        """应用名规范化后应忽略大小写和常见分隔符。"""
        self.assertEqual(normalize_name("Lets VPN"), "letsvpn")
        self.assertEqual(normalize_name("lets-vpn"), "letsvpn")
        self.assertEqual(normalize_name("Lets_VPN"), "letsvpn")

    def test_match_path_detects_bundle_style_preference_file(self) -> None:
        """bundle id 风格的 plist 文件应被识别。"""
        matched, reason = match_path(Path("/tmp/com.letsvpn.client.plist"), "LetsVPN")
        self.assertTrue(matched)
        self.assertEqual(reason, "bundle_id_match")

    def test_find_matches_in_root_returns_unique_matches(self) -> None:
        """同一路径即使被多个规则命中，也只应返回一条结果。"""
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            target = root / "com.letsvpn.client.plist"
            target.write_text("demo", encoding="utf-8")

            matches = find_matches_in_root(
                ScanRoot(category="preferences", path=root),
                "LetsVPN",
            )

            self.assertEqual(len(matches), 1)
            self.assertEqual(matches[0]["path"], str(target))
            self.assertEqual(matches[0]["category"], "preferences")
            self.assertEqual(matches[0]["planned_action"], "report_only")
            self.assertEqual(matches[0]["risk_level"], "high")

    def test_build_report_includes_scan_status_and_match_count(self) -> None:
        """报告应包含扫描根目录状态和命中数量。"""
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            match_path_value = root / "LetsVPN"
            match_path_value.mkdir()

            scan_root = ScanRoot(category="app_support", path=root)
            matches = find_matches_in_root(scan_root, "LetsVPN")
            report = build_report("LetsVPN", [scan_root], [matches])

            self.assertEqual(report["app_name"], "LetsVPN")
            self.assertEqual(report["match_count"], 1)
            self.assertEqual(report["scan_roots"][0]["status"], "scanned")
            self.assertEqual(report["cleanup_mode"], "scan")
            self.assertEqual(report["action_summary"]["report_only"], 1)

    def test_find_matches_in_root_marks_cache_as_safe_delete(self) -> None:
        """低风险目录中的命中项应标记为自动删除。"""
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            target = root / "LetsVPN"
            target.mkdir()

            matches = find_matches_in_root(
                ScanRoot(category="caches", path=root),
                "LetsVPN",
            )

            self.assertEqual(len(matches), 1)
            self.assertEqual(matches[0]["planned_action"], "safe_delete")
            self.assertEqual(matches[0]["risk_level"], "low")

    def test_apply_cleanup_actions_only_deletes_safe_delete_matches(self) -> None:
        """执行清理时只应删除低风险白名单目录里的命中项。"""
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            cache_target = root / "Caches" / "LetsVPN"
            cache_target.mkdir(parents=True)
            preference_target = root / "Preferences" / "com.letsvpn.client.plist"
            preference_target.parent.mkdir(parents=True)
            preference_target.write_text("demo", encoding="utf-8")

            matches = [
                {
                    "path": str(cache_target),
                    "category": "caches",
                    "name": cache_target.name,
                    "match_reason": "name_match",
                    "path_type": "directory",
                    "risk_level": "low",
                    "planned_action": "safe_delete",
                    "action_status": "pending",
                },
                {
                    "path": str(preference_target),
                    "category": "preferences",
                    "name": preference_target.name,
                    "match_reason": "bundle_id_match",
                    "path_type": "file",
                    "risk_level": "high",
                    "planned_action": "report_only",
                    "action_status": "pending",
                },
            ]

            summary = apply_cleanup_actions(matches)

            self.assertFalse(cache_target.exists())
            self.assertTrue(preference_target.exists())
            self.assertEqual(matches[0]["action_status"], "deleted")
            self.assertEqual(matches[1]["action_status"], "reported")
            self.assertEqual(summary["deleted"], 1)
            self.assertEqual(summary["reported"], 1)

    def test_write_report_persists_json_payload(self) -> None:
        """报告写入后应为合法 JSON。"""
        with TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            report = {
                "app_name": "LetsVPN",
                "generated_at": "2026-05-04T00:00:00",
                "scan_roots": [],
                "matches": [],
                "match_count": 0,
                "cleanup_mode": "scan",
                "action_summary": {"safe_delete": 0, "report_only": 0, "skip": 0, "deleted": 0, "reported": 0, "failed": 0},
            }

            returned_path = write_report(report, report_path)

            self.assertEqual(returned_path, report_path)
            self.assertNotEqual(returned_path.parent, REPORT_ROOT)
            self.assertEqual(json.loads(report_path.read_text(encoding="utf-8"))["app_name"], "LetsVPN")


if __name__ == "__main__":
    unittest.main()
