import unittest

from migration_crawler.generic_discovery import (
    extract_links,
    extract_published_at,
    extract_title,
)

BASE = "https://migration.wa.gov.au/news"
PATTERN = r"^/news/[a-z0-9][a-z0-9\-]+$"


class ExtractLinksTests(unittest.TestCase):
    def test_只取符合模式的链接并补全为绝对地址(self):
        body = b"""
            <a href="/news/2025-26-december-invitation-round">A</a>
            <a href="/news/goldfields-dama">B</a>
            <a href="/about">C</a>
            <a href="https://example.com/news/other">D</a>
        """
        links = extract_links(body, BASE, PATTERN)
        self.assertEqual(links, [
            "https://migration.wa.gov.au/news/2025-26-december-invitation-round",
            "https://migration.wa.gov.au/news/goldfields-dama",
        ])

    def test_同一篇的锚点与查询串视为同一条(self):
        body = (
            b'<a href="/news/round-one#top">A</a>'
            b'<a href="/news/round-one?utm=x">B</a>'
            b'<a href="/news/round-one/">C</a>'
        )
        self.assertEqual(len(extract_links(body, BASE, PATTERN)), 1)

    def test_站外链接不跟(self):
        # 列表页上出现别的域名是常事（社媒、合作方）。跟出去就越过了白名单。
        body = b'<a href="https://evil.example/news/fake">x</a>'
        self.assertEqual(extract_links(body, BASE, PATTERN), [])


class ExtractTitleTests(unittest.TestCase):
    def test_优先取_h1(self):
        self.assertEqual(extract_title(b"<h1>2025-26 Invitation Round</h1>"), "2025-26 Invitation Round")

    def test_h1_是栏目名时退回_og_title(self):
        # 南澳的文章页 h1 就是「News」，真正的标题在别处。
        body = (
            b"<h1>News</h1>"
            b'<meta property="og:title" content="December invitation round">'
        )
        self.assertEqual(extract_title(body), "December invitation round")

    def test_去掉标签与多余空白(self):
        self.assertEqual(
            extract_title(b"<h1>  Program <span>closed</span>\n for 2024 </h1>"),
            "Program closed for 2024",
        )


class ExtractPublishedAtTests(unittest.TestCase):
    def test_优先_json_ld(self):
        body = b'{"datePublished":"2024-08-15T00:00:00+09:30"} <p>1 Jan 2020</p>'
        self.assertTrue(extract_published_at(body).startswith("2024-08-15"))

    def test_退回可见日期文本(self):
        body = b"<p>Published 19 November 2025</p>"
        self.assertTrue(extract_published_at(body).startswith("2025-11-19"))

    def test_序数后缀也认(self):
        self.assertTrue(extract_published_at(b"<p>22nd Jul 2024</p>").startswith("2024-07-22"))

    def test_取不到日期返回空串而不是猜一个(self):
        # 猜出来的日期会让用户以为某条政策是今天生效的。宁可丢弃这一篇。
        self.assertEqual(extract_published_at(b"<p>no date here</p>"), "")


if __name__ == "__main__":
    unittest.main()
