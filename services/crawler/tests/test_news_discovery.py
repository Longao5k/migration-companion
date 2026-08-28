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


if __name__ == "__main__":
    unittest.main()
