import unittest

from migration_crawler.models import FetchResult, Source
from migration_crawler.rss_discovery import discover_rss_articles


SOURCE = Source(
    id="minister-media",
    name="Minister media",
    url="https://minister.example/_layouts/rss?mini=Minister",
    discovery_url="https://minister.example/_layouts/rss?mini=Minister",
    jurisdiction="AU-FED",
    license_note="official",
    enabled=True,
    discovery_format="rss",
    article_pattern=r"^/Minister/Pages/[a-z0-9\-]+\.aspx$",
    relevance_pattern=r"\b(migration|visa|citizenship)\b",
)


class Fetcher:
    def __init__(self, body: bytes):
        self.body = body

    def fetch(self, _source, _headers):
        return FetchResult(200, self.body, "text/xml", None, None)


def feed(*items: str) -> bytes:
    return (
        "<?xml version='1.0'?><rss><channel>" + "".join(items) + "</channel></rss>"
    ).encode()


def item(title: str, link: str, description: str = "visa update") -> str:
    return (
        f"<item><title>{title}</title><link>{link}</link>"
        f"<description>{description}</description>"
        "<pubDate>Wed, 25 Mar 2026 07:00:00 +1000</pubDate></item>"
    )


class RssDiscoveryTests(unittest.TestCase):
    def test_keeps_relevant_same_host_articles(self):
        body = feed(
            item(
                "Permanent migration program update",
                "https://minister.example/Minister/Pages/migration-update.aspx",
            )
        )
        found = discover_rss_articles(SOURCE, Fetcher(body))
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0].published_at, "2026-03-24T21:00:00+00:00")

    def test_rejects_unrelated_and_cross_host_items(self):
        body = feed(
            item(
                "Cyber security strategy",
                "https://minister.example/Minister/Pages/cyber.aspx",
                "cyber update",
            ),
            item(
                "Visa update",
                "https://attacker.example/Minister/Pages/visa.aspx",
            ),
        )
        self.assertEqual(discover_rss_articles(SOURCE, Fetcher(body)), [])


if __name__ == "__main__":
    unittest.main()
