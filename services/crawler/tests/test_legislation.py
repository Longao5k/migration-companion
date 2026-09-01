import unittest

from migration_crawler.legislation import describe, is_relevant

SINCE = "2024-01-01"


def row(name, *, date="2025-06-01T00:00:00", in_force=True, principal=True, collection="LegislativeInstrument"):
    return {
        "id": "F2025L00001",
        "name": name,
        "makingDate": date,
        "collection": collection,
        "isPrincipal": principal,
        "isInForce": in_force,
        "status": "InForce",
    }


class RelevanceTests(unittest.TestCase):
    def test_收录与技术移民直接相关的(self):
        for name in [
            "Migration (ANZSCO Definition) Specification 2024",
            "Migration (English Language Requirements for Subclass 485) Instrument 2025",
            "Migration Amendment (Strengthening Employer Compliance) Act 2024",
            "Migration (Specification of Language Tests, Test Scores) Instrument 2025",
            "Migration Amendment (Skills in Demand) Regulations 2025",
        ]:
            self.assertTrue(is_relevant(row(name), since=SINCE), name)

    def test_收录技术移民以外的签证与入籍主题(self):
        for name in [
            "Migration (Subclass 600 (Visitor) Visa) Instrument 2026",
            "Migration (Family and Partner Visa Arrangements) Instrument 2025",
            "Migration (Protection Visa Requirements) Instrument 2025",
            "Migration (Subclass 192 (Pacific Engagement) Visa Pre-application) 2025",
            "Australian Citizenship Amendment Act 2026",
        ]:
            self.assertTrue(is_relevant(row(name), since=SINCE), name)

    def test_不收与技术移民无关的(self):
        # 这些都真实出现在 contains(name,'Migration') 的结果里。
        # 收进来用户会以为它跟自己的 190/491 申请有关。
        for name in [
            "Migration (Prohibited Things) Determination 2025",
            "Migration (Daily Maintenance Amount for Persons in Detention) 2026",
            "Combatting Antisemitism, Hate and Extremism (Criminal and Migration) Act 2026",
            # 这一条真的被收进过库：命中了 regional，其实是离岸处理国指定。
            "Migration (Regional Processing Country—Republic of Nauru) Designation 2023",
            "Migration Amendment (Removal and Other Measures) Act 2024",
        ]:
            self.assertFalse(is_relevant(row(name), since=SINCE), name)

    def test_已失效的不收(self):
        # 失效法规容易被读成现行规定，比不收更糟。
        name = "Migration (ANZSCO Definition) Specification 2024"
        self.assertFalse(is_relevant(row(name, in_force=False), since=SINCE))

    def test_早于时间线的不收(self):
        name = "Migration (ANZSCO Definition) Specification 2019"
        self.assertFalse(is_relevant(row(name, date="2019-03-01T00:00:00"), since=SINCE))

    def test_没有日期的不收(self):
        item = row("Migration Skilled Occupation Instrument 2025")
        item["makingDate"] = None
        self.assertFalse(is_relevant(item, since=SINCE))


class DescribeTests(unittest.TestCase):
    def test_只给元数据不给法条原文(self):
        text = describe(row("Migration (ANZSCO Definition) Specification 2024"))
        self.assertIn("Legislative Instrument", text)
        self.assertIn("2025-06-01", text)
        self.assertIn("Registered title", text)
        # 法条正文是 Crown copyright，我们的引用配额也只允许很短的摘录。
        # 描述必须短到不可能构成转载。
        self.assertLess(len(text), 400)

    def test_区分主体法规与修正案(self):
        self.assertIn("主体法规", describe(row("x", principal=True)))
        self.assertIn("修正", describe(row("x", principal=False)))


if __name__ == "__main__":
    unittest.main()
