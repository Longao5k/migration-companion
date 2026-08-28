import html
import re
from datetime import datetime, timezone
from html.parser import HTMLParser

from .models import DiscoveredNews
from .normalizer import normalize_html


class _NewsListingParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._card_depth = 0
        self._capture: str | None = None
        self._date = ""
        self._category = ""
        self._title = ""
        self._url = ""
        self.items: list[DiscoveredNews] = []

    def handle_starttag(self, tag: str, attrs) -> None:
        values = dict(attrs)
        classes = values.get("class", "")
        if tag == "div" and self._card_depth == 0 and "xl:col-span-6" in classes:
            self._card_depth = 1
            self._date = self._category = self._title = self._url = ""
            return
        if self._card_depth:
            if tag == "div":
                self._card_depth += 1
            if tag == "h3":
                self._capture = "title"
            elif tag == "a" and "news_tags" not in classes:
                href = values.get("href", "")
                if "/news/" in href:
                    self._url = href
                elif href.startswith("?category="):
                    self._capture = "category"

    def handle_endtag(self, tag: str) -> None:
        if self._capture and tag in {"span", "h3", "a"}:
            self._capture = None
        if tag == "div" and self._card_depth:
            self._card_depth -= 1
            if self._card_depth == 0 and self._title and self._url and self._date:
                self.items.append(
                    DiscoveredNews(
                        title=self._title,
                        url=self._url,
                        category=self._category,
                        published_at=_parse_date(self._date),
                    )
                )

    def handle_data(self, data: str) -> None:
        value = re.sub(r"\s+", " ", html.unescape(data)).strip()
        if not value:
            return
        if not self._date and re.fullmatch(
            r"\d{1,2}(?:st|nd|rd|th)? [A-Z][a-z]{2} \d{4}", value
        ):
            self._date = value
        elif self._capture == "title":
            self._title = f"{self._title} {value}".strip()
        elif self._capture == "category":
            self._category = value


def _parse_date(value: str) -> str:
    cleaned = re.sub(r"(?<=\d)(?:st|nd|rd|th)\b", "", value, flags=re.I)
    # The source publishes a calendar date without a time. Noon UTC keeps that
    # date stable in every Australian time zone without adding a tzdata runtime
    # dependency to the small worker image.
    return datetime.strptime(cleaned, "%d %b %Y").replace(
        hour=12, tzinfo=timezone.utc
    ).isoformat()


def discover_sa_news(raw: bytes, limit: int = 6) -> list[DiscoveredNews]:
    parser = _NewsListingParser()
    parser.feed(raw.decode("utf-8", errors="replace"))
    deduped: dict[str, DiscoveredNews] = {}
    for item in parser.items:
        deduped.setdefault(item.url, item)
    return list(deduped.values())[: max(0, limit)]


def extract_article_excerpt(raw: bytes, title: str, limit: int = 1200) -> str:
    lines = normalize_html(raw).splitlines()
    try:
        start = next(index for index, line in enumerate(lines) if line.strip() == title.strip()) + 1
    except StopIteration:
        start = 0

    ignored = {"View All", "Read More", "News"}
    selected: list[str] = []
    for line in lines[start:]:
        value = line.strip()
        if value in {"Up Next", "Subscribe", "Related News"}:
            break
        if (
            not value
            or value == title
            or value in ignored
            or value.startswith("Subscribe for the latest")
            or re.fullmatch(r"\d{1,2}(?:st|nd|rd|th)? [A-Z][a-z]{2} \d{4}", value)
        ):
            continue
        selected.append(value)
        if len(" ".join(selected)) >= limit:
            break
    excerpt = re.sub(r"\s+", " ", " ".join(selected)).strip()
    return excerpt[:limit].rstrip()
