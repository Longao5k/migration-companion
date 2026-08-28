import os
import signal
import threading
from pathlib import Path

from .runner import load_sources, run_source


def main() -> None:
    stopping = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopping.set())
    signal.signal(signal.SIGINT, lambda *_: stopping.set())
    registry = Path(os.environ.get("SOURCE_REGISTRY", "/worker/sources.json"))
    state_dir = Path(os.environ.get("CRAWLER_STATE_DIR", "/data/evidence"))
    interval = max(900, int(os.environ.get("CRAWLER_INTERVAL_SECONDS", "21600")))

    while not stopping.is_set():
        sources = load_sources(registry)
        for source in sources:
            if stopping.is_set():
                break
            if not source.enabled:
                continue
            try:
                print(f"{source.id}: {run_source(source, sources, state_dir)}", flush=True)
            except Exception as error:
                print(f"{source.id}: failed:{type(error).__name__}:{error}", flush=True)
        stopping.wait(interval)


if __name__ == "__main__":
    main()
