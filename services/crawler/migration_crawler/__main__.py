import argparse
import os
from pathlib import Path
from urllib.parse import urlparse

from .backfill import backfill_sa_news
from .fetcher import OfficialFetcher
from .runner import load_sources, run_source

DEFAULT_REGISTRY = Path(__file__).resolve().parents[1] / "sources.json"


def _resolve(sources, source_id):
    source = next(
        (item for item in sources if item.id == source_id and item.enabled), None
    )
    if not source:
        raise SystemExit("source is not enabled in the approved registry")
    return source


def main() -> None:
    parser = argparse.ArgumentParser(prog="migration_crawler")
    parser.add_argument("--source", required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    parser.add_argument(
        "--backfill",
        action="store_true",
        help="一次性补齐该来源的历史新闻草稿；不进定时任务，手动跑",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="只列出会补哪些条目，不提交",
    )
    args = parser.parse_args()

    sources = load_sources(args.registry)
    source = _resolve(sources, args.source)

    if not args.backfill:
        print(run_source(source, sources, args.state_dir))
        return

    api_url = os.environ.get("REVIEW_API_URL", "")
    worker_key = os.environ.get("WORKER_API_KEY", "")
    if not args.dry_run and not (api_url and worker_key):
        raise SystemExit("回填需要 REVIEW_API_URL 和 WORKER_API_KEY")

    user_agent = os.environ.get("CRAWLER_USER_AGENT", "")
    if not user_agent:
        raise SystemExit("回填需要 CRAWLER_USER_AGENT")

    fetcher = OfficialFetcher(user_agent, approved_hosts(sources))
    results = backfill_sa_news(
        source, fetcher, api_url, worker_key, dry_run=args.dry_run
    )

    for date, title, outcome in results:
        print(f"{date}  {outcome:<10}  {title[:70]}")
    print(f"共 {len(results)} 条")


def approved_hosts(sources) -> set[str]:
    """白名单主机集合，只从注册表里的来源推导。

    回填要取的文章 URL 不在注册表里（是从列表页发现的），但它们必须落在
    已登记来源的同一批主机上——发现到一个站外链接就该被拒，而不是跟着跳出去。
    """
    hosts: set[str] = set()
    for source in sources:
        for url in (source.url, source.discovery_url):
            host = urlparse(url).hostname if url else None
            if host:
                hosts.add(host)
    return hosts


if __name__ == "__main__":
    main()
