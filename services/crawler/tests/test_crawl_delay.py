import time
import unittest
from unittest.mock import patch

from migration_crawler.fetcher import (
    DEFAULT_CRAWL_DELAY_SECONDS,
    MAX_CRAWL_DELAY_SECONDS,
    OfficialFetcher,
)

UA = "MigrationCompanionMonitor/0.1 (+https://example.org/privacy)"


class _Robots:
    """只提供 crawl_delay 的替身，够 _respect_crawl_delay 使用。"""

    def __init__(self, delay):
        self._delay = delay

    def crawl_delay(self, _agent):
        return self._delay


class CrawlDelayTests(unittest.TestCase):
    def setUp(self):
        self.fetcher = OfficialFetcher(UA, {"example.org"})

    def test_首次请求不等待(self):
        with patch("migration_crawler.fetcher.time.sleep") as sleep:
            self.fetcher._respect_crawl_delay("example.org", _Robots(10))
        sleep.assert_not_called()

    def test_遵守站点声明的_crawl_delay(self):
        # legislation.gov.au 声明 Crawl-delay: 10，此前完全没有遵守。
        self.fetcher._last_request_at["example.org"] = time.monotonic()
        with patch("migration_crawler.fetcher.time.sleep") as sleep:
            self.fetcher._respect_crawl_delay("example.org", _Robots(10))
        sleep.assert_called_once()
        self.assertGreater(sleep.call_args[0][0], 9)

    def test_未声明时仍有最小间隔(self):
        # 新闻发现会连续抓列表页和多篇文章，没有节流就是一次突发。
        self.fetcher._last_request_at["example.org"] = time.monotonic()
        with patch("migration_crawler.fetcher.time.sleep") as sleep:
            self.fetcher._respect_crawl_delay("example.org", _Robots(None))
        sleep.assert_called_once()
        self.assertAlmostEqual(sleep.call_args[0][0], DEFAULT_CRAWL_DELAY_SECONDS, delta=0.5)

    def test_异常长的声明被封顶(self):
        self.fetcher._last_request_at["example.org"] = time.monotonic()
        with patch("migration_crawler.fetcher.time.sleep") as sleep:
            self.fetcher._respect_crawl_delay("example.org", _Robots(9999))
        self.assertLessEqual(sleep.call_args[0][0], MAX_CRAWL_DELAY_SECONDS)

    def test_已过足够时间则不再等待(self):
        self.fetcher._last_request_at["example.org"] = time.monotonic() - 60
        with patch("migration_crawler.fetcher.time.sleep") as sleep:
            self.fetcher._respect_crawl_delay("example.org", _Robots(10))
        sleep.assert_not_called()


if __name__ == "__main__":
    unittest.main()
