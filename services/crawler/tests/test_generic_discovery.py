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

    def test_带发布字样的可见日期可以认(self):
        body = b"<p>Published 19 November 2025</p>"
        self.assertTrue(extract_published_at(body).startswith("2025-11-19"))

    def test_序数后缀也认(self):
        self.assertTrue(
            extract_published_at(b"<p>Posted 22nd Jul 2024</p>").startswith("2024-07-22")
        )

    def test_没有标签的裸日期不认(self):
        # 收紧的代价：少认一些。政策页上到处是日期，认错一个比少认十个贵。
        self.assertEqual(extract_published_at(b"<p>22nd Jul 2024</p>"), "")

    def test_取不到日期返回空串而不是猜一个(self):
        # 猜出来的日期会让用户以为某条政策是今天生效的。宁可丢弃这一篇。
        self.assertEqual(extract_published_at(b"<p>no date here</p>"), "")


if __name__ == "__main__":
    unittest.main()


class DateSafetyTests(unittest.TestCase):
    """这些用例来自真实抓到的错误数据，不是假想。"""

    def test_不把标题里的截止日期当成发布日期(self):
        # WA 真实页面：「…access the Goldfields DAMA until 31 December 2026」。
        # 旧实现取页面第一个日期，把这条 2025 年的公告标成 2026-12-31。
        body = (
            b"<h1>Goldfields employers continue to access the Goldfields DAMA "
            b"until 31 December 2026</h1>"
        )
        self.assertEqual(extract_published_at(body), "")

    def test_未来日期一律拒绝(self):
        from datetime import datetime, timezone
        body = b'<time datetime="2030-01-01T00:00:00Z">soon</time>'
        now = datetime(2026, 8, 30, tzinfo=timezone.utc)
        self.assertEqual(extract_published_at(body, now=now), "")

    def test_可见日期要挨着发布字样才认(self):
        self.assertTrue(
            extract_published_at(b"<p>Published 19 November 2025</p>").startswith("2025-11-19")
        )
        # 正文里随便一个日期不算——政策页遍地是生效日和财年区间。
        self.assertEqual(
            extract_published_at(b"<p>Applications close 30 June 2026 for the round</p>"),
            "",
        )

    def test_time_元素优先于正文(self):
        body = (
            b'<time datetime="2025-03-04T00:00:00+10:00">x</time>'
            b"<p>Published 19 November 2025</p>"
        )
        self.assertTrue(extract_published_at(body).startswith("2025-03-04"))


class LabelWordTests(unittest.TestCase):
    def test_不把生效日截止日当成发布日(self):
        # 词表里原先有裸的 "date"，于是 closing date / commencement date /
        # effective date 全都会被当成发布日期。未来日期守卫挡不住这些——
        # 它们通常是过去的日期。
        for text in [
            b"<p>Closing date 30 June 2024 for this round</p>",
            b"<p>Commencement date 1 July 2023</p>",
            b"<p>Effective date 15 March 2025</p>",
            b"<p>Expiry date 31 December 2024</p>",
        ]:
            self.assertEqual(extract_published_at(text), "", text.decode())

    def test_真正的发布字样仍然认(self):
        for text, expect in [
            (b"<p>Published 19 November 2025</p>", "2025-11-19"),
            (b"<p>Posted 3 Mar 2024</p>", "2024-03-03"),
            (b"<p>Last updated 8 Aug 2025</p>", "2025-08-08"),
        ]:
            self.assertTrue(extract_published_at(text).startswith(expect), text.decode())
