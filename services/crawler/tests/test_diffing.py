import unittest
from migration_crawler.diffing import classify, make_candidate


class DiffingTests(unittest.TestCase):
    def test_no_candidate_for_identical_content(self):
        self.assertIsNone(make_candidate("same", "same", "Source"))

    def test_eligibility_change_requires_important_review(self):
        candidate = make_candidate(
            "General information",
            "New eligibility requirement applies from July",
            "Official source",
        )
        self.assertIsNotNone(candidate)
        self.assertEqual(candidate.importance, "IMPORTANT")

    def test_closed_program_is_major(self):
        self.assertEqual(classify("The program is closed to new applications"), "MAJOR")

    def test_comparison_includes_unchanged_context(self):
        old = "Heading\nBefore context\nOld requirement\nAfter context\nFooter"
        new = "Heading\nBefore context\nNew eligibility requirement\nAfter context\nFooter"
        candidate = make_candidate(old, new, "Official source", body_chars=10_000)
        self.assertIsNotNone(candidate)
        assert candidate is not None
        self.assertIn("  Before context", candidate.old_excerpt)
        self.assertIn("- Old requirement", candidate.old_excerpt)
        self.assertIn("+ New eligibility requirement", candidate.new_excerpt)
        self.assertIn("  After context", candidate.new_excerpt)

    def test_sitemap_timestamp_only_change_is_ignored(self):
        self.assertIsNone(
            make_candidate(
                "lastmod 2026-09-01T01:02:03Z",
                "lastmod 2026-09-02T01:02:03Z",
                "Sitemap",
            )
        )

    def test_maintenance_banner_only_change_is_ignored(self):
        self.assertIsNone(
            make_candidate(
                "Online services will be unavailable due to scheduled maintenance",
                "Online services are unavailable due to scheduled maintenance",
                "Official source",
            )
        )


if __name__ == "__main__":
    unittest.main()
