/**
 * Local acceptance environment.
 *
 * The values here mirror `infra/docker-compose.yml` so `pnpm test:e2e` runs against the
 * same PostgreSQL and MinIO containers the one-click local stack uses. Anything already
 * present in the environment wins, so CI can point the suite at its own throwaway stack.
 *
 * DEV_AUTH / DEV_AUTO_SCAN / DEV_STORE are development-only switches. `applyLocalE2eEnv`
 * refuses to run with NODE_ENV=production so the suite can never enable them against a
 * real deployment.
 */
const defaults: Record<string, string> = {
  DATABASE_URL: 'postgresql://migration:local-only-migration@localhost:55432/migration?schema=public',
  AWS_ACCESS_KEY_ID: 'localmigration',
  AWS_SECRET_ACCESS_KEY: 'local-only-migration-storage',
  S3_ENDPOINT: 'http://127.0.0.1:59000',
  S3_FORCE_PATH_STYLE: 'true',
  S3_USER_BUCKET: 'migration-user-files',
  S3_REGION: 'ap-southeast-2',
  SHARE_ORIGIN: 'http://127.0.0.1:53003',
  DEV_AUTH: 'true',
  DEV_AUTO_SCAN: 'true',
  DEV_STORE: 'true',
  WORKER_API_KEY: 'local-worker',
  ADMIN_API_KEY: 'local-admin',
};

export function applyLocalE2eEnv() {
  if (process.env.NODE_ENV === 'production') {
    throw new Error('端到端验收套件不允许在 NODE_ENV=production 下运行');
  }
  for (const [key, value] of Object.entries(defaults)) {
    process.env[key] ??= value;
  }
}
