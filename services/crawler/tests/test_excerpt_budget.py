import unittest

from migration_crawler.diffing import (
    EXCERPT_COMBINED,
    EXCERPT_PER_FIELD,
    excerpt_budget,
    make_candidate,
)

# services/api/src/content/excerpt-quota.ts 的合计上限。两端必须一致：
# 采集器按更宽的配额产出时，API 会以 HTTP 400 拒绝，该来源本轮直接失败，
# 也就是真实政策变更被我们自己的规则吃掉。
API_COMBINED_LIMIT = 1200
API_PER_FIELD_LIMIT = 600
API_BODY_RATIO = 0.2


class ExcerptBudgetTests(unittest.TestCase):
    def test_配额常量与_api_一致(self):
        self.assertEqual(EXCERPT_COMBINED, API_COMBINED_LIMIT)
        self.assertEqual(EXCERPT_PER_FIELD, API_PER_FIELD_LIMIT)

    def test_大幅改动仍在_api_可接受范围内(self):
        old = "\n".join(f"old line {i}" for i in range(120))
        new = "\n".join(f"new line {i}" for i in range(120))
        candidate = make_candidate(old, new, "来源", body_chars=len(new))
        assert candidate is not None
        used = len(candidate.old_excerpt) + len(candidate.new_excerpt) + len(candidate.context)
        self.assertLessEqual(used, API_COMBINED_LIMIT)
        self.assertLessEqual(len(candidate.old_excerpt), API_PER_FIELD_LIMIT)
        self.assertLessEqual(len(candidate.new_excerpt), API_PER_FIELD_LIMIT)

    def test_长正文页面顶到单字段上限时合计仍不越界(self):
        # 上一条用例的 body_chars 很小，比例上限先生效，per_field 只到一百多——
        # 它永远碰不到 600/600 的边界，所以守不住它声称守的东西。
        # Migration Act / Regulations 这类长页面才是真实的最坏情况：
        # 比例上限失效，两个字段都顶到单字段上限，加上 context 就会越过 1200。
        old = chr(10).join(f"old line number {i:04d} with a good amount of padding text" for i in range(120))
        new = chr(10).join(f"new line number {i:04d} with a good amount of padding text" for i in range(120))
        candidate = make_candidate(old, new, "来源", body_chars=60_000)
        assert candidate is not None
        self.assertGreater(
            len(candidate.old_excerpt), 500, "这条用例必须真的顶到单字段上限"
        )
        used = (
            len(candidate.old_excerpt)
            + len(candidate.new_excerpt)
            + len(candidate.context)
        )
        self.assertLessEqual(used, API_COMBINED_LIMIT)

    def test_短页面按比例进一步收紧(self):
        # 实测南澳新闻页规范化正文约 2219 字符：20% 约 443，比固定上限严得多。
        body = 2219
        self.assertLessEqual(excerpt_budget(body), int(body * API_BODY_RATIO))
        old = "\n".join(f"old {i}" for i in range(120))
        new = "\n".join(f"new {i}" for i in range(120))
        candidate = make_candidate(old, new, "来源", body_chars=body)
        assert candidate is not None
        used = len(candidate.old_excerpt) + len(candidate.new_excerpt)
        self.assertLessEqual(used, int(body * API_BODY_RATIO))

    def test_未知正文长度退回固定上限(self):
        self.assertEqual(excerpt_budget(0), EXCERPT_COMBINED)

    def test_无变化仍然返回_none(self):
        self.assertIsNone(make_candidate("same", "same", "来源", 100))


if __name__ == "__main__":
    unittest.main()
