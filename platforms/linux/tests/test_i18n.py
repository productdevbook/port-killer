"""
Tests for Linux tray app localization helper.

Run with:  python3 -m unittest discover -s platforms/linux/tests
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from src.i18n import is_chinese_locale, tr


class TestI18n(unittest.TestCase):
    def test_detects_chinese_locale_from_env(self):
        self.assertTrue(is_chinese_locale({"LANG": "zh_CN.UTF-8"}))
        self.assertTrue(is_chinese_locale({"LC_ALL": "zh_TW.UTF-8", "LANG": "en_US.UTF-8"}))
        self.assertFalse(is_chinese_locale({"LANG": "en_US.UTF-8"}))

    def test_returns_english_when_lang_is_en(self):
        self.assertEqual(tr("No open ports", lang="en"), "No open ports")
        self.assertEqual(
            tr("Port {port} copied to clipboard!", lang="en", port=3000),
            "Port 3000 copied to clipboard!",
        )

    def test_translates_to_chinese_when_lang_is_zh(self):
        self.assertEqual(tr("No open ports", lang="zh"), "暂无开放端口")
        self.assertEqual(
            tr("Port {port} copied to clipboard!", lang="zh", port=3000),
            "端口 3000 已复制到剪贴板！",
        )


if __name__ == "__main__":
    unittest.main()
