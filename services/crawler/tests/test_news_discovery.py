import unittest

from migration_crawler.news_discovery import discover_sa_news, extract_article_excerpt


class NewsDiscoveryTests(unittest.TestCase):
    def test_discovers_structured_sa_news_cards(self):
        raw = b"""
        <div class="col-span-full xl:col-span-6 pb-site border-b">
          <div><div class="font-bold"><span>2nd Jul 2026</span></div>
          <div class="news_tags"><a href="?category=program-updates">Program updates</a></div>
          <h3 class="t-subheading">Increase to the Temporary Skilled Migration Income Threshold</h3>
          <a href="https://migration.sa.gov.au/news/tsmit-increase"><span>Read More</span></a></div>
        </div>
        """
        items = discover_sa_news(raw)
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0].category, "Program updates")
        self.assertEqual(items[0].url, "https://migration.sa.gov.au/news/tsmit-increase")
        self.assertTrue(items[0].published_at.startswith("2026-07-02T"))

    def test_extracts_article_body_without_navigation_or_up_next(self):
        raw = b"""
        <html><body><nav>Menu</nav><main>
          <h1>Threshold increase</h1><span>2nd Jul 2026</span><a>View All</a>
          <p>From 1 July, the threshold increased.</p>
          <p>Employers should review nomination settings.</p>
          <h2>Up Next</h2><p>Another story</p>
        </main></body></html>
        """
        excerpt = extract_article_excerpt(raw, "Threshold increase")
        self.assertIn("threshold increased", excerpt)
        self.assertNotIn("Another story", excerpt)
        self.assertNotIn("View All", excerpt)

    def test_preserves_table_columns_for_editorial_review(self):
        raw = b"""
        <main><h1>Invitations issued</h1>
          <p>Results for this round:</p>
          <table>
            <tr><th>Group</th><th>190 this round</th><th>491 this round</th>
                <th>190 to date</th><th>491 to date</th></tr>
            <tr><td>ICT Professionals</td><td>1</td><td>32</td><td>7</td><td>84</td></tr>
            <tr><td>Total</td><td>235</td><td>109</td><td>610</td><td>321</td></tr>
          </table>
          <h2>Up Next</h2><p>Another story</p>
        </main>
        """
        excerpt = extract_article_excerpt(raw, "Invitations issued")
        self.assertIn("ICT Professionals | 1 | 32 | 7 | 84", excerpt)
        self.assertIn("Total | 235 | 109 | 610 | 321", excerpt)
        self.assertNotIn("Another story", excerpt)


if __name__ == "__main__":
    unittest.main()
