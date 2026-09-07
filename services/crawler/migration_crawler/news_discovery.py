import html
import re
from datetime import datetime, timezone
from html.parser import HTMLParser

from .models import DiscoveredNews


class _ArticleTextParser(HTMLParser):
    """Extract visible text while retaining table row and column boundaries."""

    skipped_tags = {"script", "style", "svg", "noscript", "nav", "footer"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._skip_depth = 0
        self._table_depth = 0
        self._cell_depth = 0
        self._cell: list[str] = []
        self._row: list[str] = []
        self.lines: list[str] = []

    def handle_starttag(self, tag: str, _attrs) -> None:
        tag = tag.lower()
        if tag in self.skipped_tags:
            self._skip_depth += 1
            return
        if self._skip_depth:
            return
        if tag == "table":
            self._table_depth += 1
        elif self._table_depth and tag in {"td", "th"}:
            self._cell_depth += 1
            self._cell = []

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if tag in self.skipped_tags and self._skip_depth:
            self._skip_depth -= 1
            return
        if self._skip_depth:
            return
        if self._table_depth and tag in {"td", "th"} and self._cell_depth:
            value = re.sub(r"\s+", " ", " ".join(self._cell)).strip()
            self._row.append(value)
            self._cell_depth -= 1
            self._cell = []
        elif self._table_depth and tag == "tr":
            if any(self._row):
                self.lines.append(" | ".join(self._row))
            self._row = []
        elif tag == "table" and self._table_depth:
            self._table_depth -= 1

    def handle_data(self, data: str) -> None:
        if self._skip_depth:
            return
        value = re.sub(r"\s+", " ", html.unescape(data)).strip()
        if not value:
            return
        if self._table_depth:
            if self._cell_depth:
                self._cell.append(value)
            return
        if value not in self.lines[-3:]:
            self.lines.append(value)


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


def extract_article_excerpt(raw: bytes, title: str, limit: int = 2000) -> str:
    # `normalize_html` intentionally flattens all visible text. That is fine for
    # prose diffs, but it turns a seven-column invitation table into an ambiguous
    # number stream. Keep `|` between cells here so a reviewer can distinguish
    # this round from year-to-date totals.
    parser = _ArticleTextParser()
    parser.feed(raw.decode("utf-8", errors="replace"))
    lines = parser.lines
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
