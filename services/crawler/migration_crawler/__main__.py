import argparse
from pathlib import Path
from .runner import load_sources, run_source


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument(
        "--registry",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "sources.json",
    )
    args = parser.parse_args()
    sources = load_sources(args.registry)
    source = next((item for item in sources if item.id == args.source and item.enabled), None)
    if not source:
        raise SystemExit("source is not enabled in the approved registry")
    print(run_source(source, sources, args.state_dir))


if __name__ == "__main__":
    main()

