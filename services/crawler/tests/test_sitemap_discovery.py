import unittest
from datetime import datetime, timezone

from migration_crawler.models import FetchResult, Source
from migration_crawler.sitemap_discovery import discover_sitemap_articles


class FakeFetcher:
    def __init__(self, responses):
        self.responses = responses

    def fetch(self, source, _conditional):
        return FetchResult(200, self.responses[source.url], "application/xml", None, None)


class SitemapDiscoveryTests(unittest.TestCase):
    def test_keeps_recent_relevant_same_host_article(self):
        year = datetime.now(timezone.utc).year
        root = f"""<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <sitemap><loc>https://official.example/sitemap.xml?page=1</loc></sitemap>
        </sitemapindex>""".encode()
        page = f"""<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>https://official.example/new-visa-program</loc><lastmod>{year}-08-01T00:00:00Z</lastmod></url>
          <url><loc>https://other.example/migration-story</loc><lastmod>{year}-08-01T00:00:00Z</lastmod></url>
          <url><loc>https://official.example/new-hospital</loc><lastmod>{year}-08-01T00:00:00Z</lastmod></url>
        </urlset>""".encode()
        article = f"""<html><head><meta property="article:published_time" content="{year}-08-01T00:00:00Z"></head><body><h1>New visa program</h1></body></html>""".encode()
        source = Source(
            id="official",
            name="Official",
            url="https://official.example/sitemap.xml",
            discovery_url="https://official.example/sitemap.xml",
            jurisdiction="AU-VIC",
            license_note="official",
            enabled=True,
            discovery_format="sitemap",
            relevance_pattern=r"\b(visa|migration)\b",
        )
        fetcher = FakeFetcher({
            source.url: root,
            "https://official.example/sitemap.xml?page=1": page,
            "https://official.example/new-visa-program": article,
        })

        items = discover_sitemap_articles(source, fetcher, limit=4)
        self.assertEqual([item.title for item in items], ["New visa program"])


if __name__ == "__main__":
    unittest.main()
