import unittest

from migration_crawler.tagging import TOPICS, VISA_SUBCLASSES, extract_tags


class VisaSubclassTests(unittest.TestCase):
    def test_抽出真实标题里的签证类别(self):
        cases = [
            ("Migration (English Language Requirements for Subclass 485 "
             "(Temporary Graduate) Visa) Instrument 2025", "485"),
            ("Migration (LIN 19/219: Occupations for Subclass 494 Visas) 2019", "494"),
            ("Migration (Specification of Foreign Countries for Subclass 462) 2024", "462"),
            ("Skilled Nominated (subclass 190) visa - 3,000 places", "190"),
            ("Income Threshold and Exemptions for Subclass 189 Visa", "189"),
        ]
        for text, expected in cases:
            self.assertIn(expected, extract_tags(text), text[:48])

    def test_必须有签证词邻接(self):
        # 子串判断会命中日期、金额、条目编号。宁可漏，不可错：
        # 错了就是把 482 的政策推给 491 的用户。
        self.assertEqual(
            [t for t in extract_tags("More than 2000 places; 190 nomination places issued")
             if t in VISA_SUBCLASSES],
            [],
        )
        self.assertIn("190", extract_tags("places under the subclass 190 program"))

    def test_年份与金额不会被当成签证(self):
        for text in ["The 2024-25 program year", "TSMIT rises to 76,515 from 1 July"]:
            self.assertEqual([t for t in extract_tags(text) if t in VISA_SUBCLASSES], [], text)

    def test_辖区不再进标签(self):
        # 辖区是一等字段。留在标签里是双份真相，而且会把签证标签挤没。
        tags = extract_tags("South Australia subclass 190 occupation list")
        self.assertNotIn("南澳", tags)
        self.assertNotIn("AU-SA", tags)


class TopicTests(unittest.TestCase):
    def test_来源登记的主题直接继承(self):
        # 从来源推导比从标题猜可靠：接一个新的职业清单页时主题是先验已知的。
        self.assertIn("职业清单", extract_tags("Any title at all", ("职业清单",)))

    def test_标题关键词作为补充(self):
        self.assertIn("邀请轮次", extract_tags("Invitations issued - May 2026"))
        self.assertIn("审理时间", extract_tags("Current processing times"))
        self.assertIn("打分规则", extract_tags("Pool and Pass Marks for General Skilled Migration"))

    def test_只收词表内的主题(self):
        tags = extract_tags("x", ("职业清单", "不存在的主题"))
        self.assertIn("职业清单", tags)
        self.assertNotIn("不存在的主题", tags)
        for tag in tags:
            self.assertTrue(tag in TOPICS or tag in VISA_SUBCLASSES)

    def test_抽不出就留空不猜(self):
        self.assertEqual(extract_tags("Office closed for the holiday period"), [])

    def test_不重复(self):
        tags = extract_tags("subclass 190 visa and subclass 190 nomination", ("职业清单", "职业清单"))
        self.assertEqual(len(tags), len(set(tags)))


if __name__ == "__main__":
    unittest.main()
