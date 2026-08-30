import unittest

from migration_crawler.tagging import extract_tags


class VisaSubclassTests(unittest.TestCase):
    def test_抽出联邦法规标题里的签证类别(self):
        # 这些是真实入库的标题。原先只判断 190/491 两个子串，
        # 结果它们一个签证标签都没有——订阅 485 的人收不到 485 的法规。
        cases = [
            ("Migration (English Language Requirements for Subclass 485 "
             "(Temporary Graduate) Visa) Instrument 2025", "485"),
            ("Migration (LIN 19/219: Occupations for Subclass 494 Visas) Instrument 2019", "494"),
            ("Migration (Specified Subclass 417 Work Exemption) Instrument 2024", "417"),
            ("Migration (Specification of Foreign Countries for Subclass 462) 2024", "462"),
            ("Migration (Income Threshold and Exemptions for Subclass 189 Visa) 2021", "189"),
        ]
        for text, expected in cases:
            self.assertIn(expected, extract_tags("联邦", text), text[:48])

    def test_一条内容可以带多个签证类别(self):
        tags = extract_tags("南澳", "Skilled Nominated (subclass 190) and Skilled Work Regional (subclass 491)")
        self.assertIn("190", tags)
        self.assertIn("491", tags)

    def test_不把名额数字当成签证类别(self):
        # 「3800 个名额」「2000 places」不是签证类别。收进去会让用户以为
        # 一条名额公告和某个签证有关。
        tags = extract_tags("南澳", "More than 2000 places available; 3,000 nomination places in total")
        self.assertEqual([t for t in tags if t.isdigit()], [])

    def test_年份不会被当成签证类别(self):
        tags = extract_tags("南澳", "The 2024-25 program year closed on 30 June 2025")
        self.assertEqual([t for t in tags if t.isdigit()], [])


class TopicTests(unittest.TestCase):
    def test_识别主题(self):
        cases = [
            ("South Australia's Skilled Occupation List is available", "职业清单"),
            ("Registration of Interest applications have closed", "ROI"),
            ("Designated Area Migration Agreements extended", "DAMA"),
            ("Temporary Skilled Migration Income Threshold will increase", "薪资门槛"),
            ("Invitations issued this week across four streams", "邀请数据"),
            ("English language requirements for the visa", "英语要求"),
            ("Current processing times for nomination", "审理进度"),
        ]
        for text, expected in cases:
            self.assertIn(expected, extract_tags("南澳", text), text[:44])

    def test_辖区标签永远在第一位(self):
        tags = extract_tags("昆士兰", "Subclass 190 occupation list update")
        self.assertEqual(tags[0], "昆士兰")

    def test_不收站点自己的分类名(self):
        # 「Other news」是站点栏目名，不是用户会订阅的东西。
        self.assertNotIn("Other news", extract_tags("南澳", "x", "Other news"))
        self.assertIn("Invitations issued", extract_tags("南澳", "x", "Invitations issued"))

    def test_没有可靠信号时只留辖区(self):
        # 猜一个标签比不打标签糟：用户会因此收到不相关的提醒。
        self.assertEqual(extract_tags("南澳", "Office closed for the holiday period"), ["南澳"])

    def test_标签不重复(self):
        tags = extract_tags("南澳", "subclass 190 visa, subclass 190 nomination, occupation list, occupation list")
        self.assertEqual(len(tags), len(set(tags)))


if __name__ == "__main__":
    unittest.main()
