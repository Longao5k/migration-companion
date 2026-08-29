import unittest

from migration_crawler.backfill import SA_NEWS_VIEWS, collect_sa_news_archive
from migration_crawler.models import Source

SOURCE = Source(
    id="sa-news",
    name="Move to South Australia — News",
    url="https://migration.sa.gov.au/news",
    jurisdiction="AU-SA",
    license_note="© Government of South Australia",
    enabled=True,
    discovery_url="https://migration.sa.gov.au/news",
)


def card(title: str, slug: str, date: str) -> str:
    """一张列表卡片，结构照抄站点：xl:col-span-6 容器 + 日期 + h3 标题 + 链接。"""
    return (
        '<div class="xl:col-span-6">'
        f"<span>{date}</span>"
        f"<h3>{title}</h3>"
        f'<a href="https://migration.sa.gov.au/news/{slug}">Read More</a>'
        "</div>"
    )


class _StubFetcher:
    """按 URL 返回不同列表页，用来验证三个视图的合并。"""

    def __init__(self, pages: dict[str, str]) -> None:
        self.pages = pages
        self.requested: list[str] = []

    def fetch(self, source, conditional):
        self.requested.append(source.url)
        body = self.pages.get(source.url, "").encode("utf-8")
        return type("R", (), {"body": body})()


class BackfillArchiveTests(unittest.TestCase):
    def test_合并三个视图并按时间升序去重(self):
        # 分类视图会露出主列表上没有的旧条目——这正是回填能比日常发现多拿到东西的原因。
        fetcher = _StubFetcher(
            {
                SA_NEWS_VIEWS[0]: card("New thing", "new-thing", "2nd Jul 2026"),
                SA_NEWS_VIEWS[1]: (
                    card("Old thing", "old-thing", "22nd Jul 2024")
                    + card("New thing", "new-thing", "2nd Jul 2026")
                ),
                SA_NEWS_VIEWS[2]: card("Invitations", "inv-dec", "4th Dec 2025"),
            }
        )

        archive = collect_sa_news_archive(SOURCE, fetcher)

        self.assertEqual(fetcher.requested, list(SA_NEWS_VIEWS))
        self.assertEqual(
            [item.title for item in archive],
            ["Old thing", "Invitations", "New thing"],
        )

    def test_同一篇在多个视图出现只保留一条(self):
        page = card("Same", "same", "1st Jan 2026")
        fetcher = _StubFetcher({view: page for view in SA_NEWS_VIEWS})
        self.assertEqual(len(collect_sa_news_archive(SOURCE, fetcher)), 1)

    def test_主列表为空时仍从分类视图取到历史(self):
        # 站点主列表只给最近一屏；回填如果只看它，2024 年的条目永远补不进来。
        fetcher = _StubFetcher({SA_NEWS_VIEWS[1]: card("Old", "old", "22nd Jul 2024")})
        archive = collect_sa_news_archive(SOURCE, fetcher)
        self.assertEqual([item.published_at[:10] for item in archive], ["2024-07-22"])


if __name__ == "__main__":
    unittest.main()
