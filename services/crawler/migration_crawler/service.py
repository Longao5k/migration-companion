import os
import signal
import threading
from pathlib import Path

from .api import submit_news_draft
from .legislation import discover_legislation, set_user_agent
from .runner import load_sources, run_source


def main() -> None:
    stopping = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopping.set())
    signal.signal(signal.SIGINT, lambda *_: stopping.set())
    registry = Path(os.environ.get("SOURCE_REGISTRY", "/worker/sources.json"))
    state_dir = Path(os.environ.get("CRAWLER_STATE_DIR", "/data/evidence"))
    interval = max(900, int(os.environ.get("CRAWLER_INTERVAL_SECONDS", "21600")))
    # 法规库每天查一次就够：立法文书不是每小时都有。用轮次计数而不是单独起一个
    # 线程——少一个并发路径，也避免两个循环同时打同一个站点。
    legislation_every = max(1, int(os.environ.get("LEGISLATION_EVERY_N_ROUNDS", "4")))
    legislation_since = os.environ.get("LEGISLATION_SINCE", "2019-01-01")
    round_index = 0

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
        if round_index % legislation_every == 0:
            _run_legislation(load_sources(registry), legislation_since)
        round_index += 1
        stopping.wait(interval)


def _run_legislation(sources, since: str) -> None:
    """联邦法规进定时循环。

    原先只有手工命令能跑，回填过一次之后就静止了——**2026-08-30 之后新增或修订的
    移民及公民法规，系统看不见**。而内政部的说明页抓不到，法规库是重要的联邦替代品；
    一个静止的替代品等于没有替代。

    失败不影响主循环：法规库不可用时，各州的抓取照常。
    """
    api_url = os.environ.get("REVIEW_API_URL", "")
    worker_key = os.environ.get("WORKER_API_KEY", "")
    user_agent = os.environ.get("CRAWLER_USER_AGENT", "")
    if not (api_url and worker_key and user_agent):
        print("legislation: skipped:missing-config", flush=True)
        return

    source = next(
        (s for s in sources if s.id == "migration-regulations" and s.enabled), None
    )
    if source is None:
        print("legislation: skipped:no-source", flush=True)
        return

    set_user_agent(user_agent)
    try:
        items = discover_legislation(since=since)
    except Exception as error:
        print(f"legislation: failed:{type(error).__name__}:{error}", flush=True)
        return

    created = 0
    for item in items:
        try:
            submit_news_draft(api_url, worker_key, source, item)
            created += 1
        except Exception as error:
            print(f"legislation: submit-failed:{type(error).__name__}", flush=True)
    print(f"legislation: {created}/{len(items)} drafts", flush=True)


if __name__ == "__main__":
    main()
