from dataclasses import dataclass
from typing import Literal

Importance = Literal["GENERAL", "IMPORTANT", "MAJOR"]


@dataclass(frozen=True)
class Source:
    id: str
    name: str
    url: str
    jurisdiction: str
    license_note: str
    enabled: bool


@dataclass(frozen=True)
class FetchResult:
    status: int
    body: bytes
    content_type: str
    etag: str | None
    last_modified: str | None


@dataclass(frozen=True)
class ChangeCandidate:
    title_zh: str
    old_excerpt: str
    new_excerpt: str
    context: str
    importance: Importance

