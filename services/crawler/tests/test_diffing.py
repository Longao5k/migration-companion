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


if __name__ == "__main__":
    unittest.main()

