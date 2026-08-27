import hashlib
import json
import os
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass
class SourceState:
    content_hash: str | None = None
    normalized_text: str = ""
    etag: str | None = None
    last_modified: str | None = None


class LocalEvidenceStore:
    """Local-development adapter. Production replaces this with private S3/KMS."""

    def __init__(self, root: Path) -> None:
        self.root = root.resolve()
        self.root.mkdir(parents=True, exist_ok=True)

    def load(self, source_id: str) -> SourceState:
        path = self.root / source_id / "state.json"
        if not path.exists():
            return SourceState()
        return SourceState(**json.loads(path.read_text(encoding="utf-8")))

    def save(self, source_id: str, raw: bytes, normalized_text: str, etag: str | None, last_modified: str | None) -> str:
        digest = hashlib.sha256(raw).hexdigest()
        source_dir = self.root / source_id
        source_dir.mkdir(parents=True, exist_ok=True)
        evidence_path = source_dir / f"{digest}.evidence"
        if not evidence_path.exists():
            evidence_path.write_bytes(raw)
        state = SourceState(digest, normalized_text, etag, last_modified)
        self._atomic_text(source_dir / "state.json", json.dumps(asdict(state), ensure_ascii=False, indent=2))
        return digest

    @staticmethod
    def _atomic_text(path: Path, value: str) -> None:
        handle, temp_name = tempfile.mkstemp(prefix="state-", suffix=".json", dir=path.parent)
        try:
            with os.fdopen(handle, "w", encoding="utf-8") as stream:
                stream.write(value)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temp_name, path)
        finally:
            if os.path.exists(temp_name):
                os.unlink(temp_name)

