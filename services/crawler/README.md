# Official source monitor

This worker only accepts URLs from `sources.json`. It checks robots rules, rejects private/metadata IP targets, sends conditional HTTP requests, stores immutable evidence, normalises page text and emits review candidates. Approved news listing URLs may also discover article links on the same official host; discovered stories are private editorial drafts and never auto-publish. Major and important candidates remain unpublished until a human reviewer verifies the official source.

Production requires a truthful contact URL in `CRAWLER_USER_AGENT`, approved page-level copyright/terms notes, private evidence storage, and a worker API key. Do not add a source merely because it is publicly reachable.

```powershell
python -m unittest discover -s tests
$env:CRAWLER_USER_AGENT='MigrationCompanionMonitor/0.1 (+https://your-domain.example/bot)'
python -m migration_crawler --source sa-news --state-dir .local-state
```
