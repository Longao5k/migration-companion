import html
import re
from html.parser import HTMLParser


class VisibleTextParser(HTMLParser):
    skipped_tags = {"script", "style", "svg", "noscript", "nav", "footer"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._depth = 0
        self._chunks: list[str] = []

    def handle_starttag(self, tag: str, _attrs) -> None:
        if tag.lower() in self.skipped_tags:
            self._depth += 1

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() in self.skipped_tags and self._depth:
            self._depth -= 1

    def handle_data(self, data: str) -> None:
        if self._depth == 0 and data.strip():
            self._chunks.append(data)

    @property
    def text(self) -> str:
        return "\n".join(self._chunks)


def normalize_html(raw: bytes, charset: str = "utf-8") -> str:
    decoded = raw.decode(charset, errors="replace")
    parser = VisibleTextParser()
    parser.feed(decoded)
    lines: list[str] = []
    for line in parser.text.splitlines():
        value = re.sub(r"\s+", " ", html.unescape(line)).strip()
        if not value:
            continue
        if re.fullmatch(r"(?:Last updated|Updated)[: ]+\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}", value, re.I):
            continue
        if value not in lines[-3:]:
            lines.append(value)
    return "\n".join(lines)

