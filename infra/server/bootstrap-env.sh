#!/usr/bin/env bash
# 在服务器上生成 infra/server/.env。
#
# 所有密钥都在服务器本机用 openssl 生成，不经过任何外部渠道。已存在的 .env 不会被覆盖，
# 避免重跑时更换数据库密码导致既有数据卷无法访问。
#
# 用法：bash infra/server/bootstrap-env.sh <PILOT_ACCESS_CODES 条目文件>
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
target="$here/.env"
pilot_codes_file="${1:-}"

if [ -f "$target" ]; then
  echo "已存在 $target，未覆盖。要重新生成请先手动备份并删除。" >&2
  exit 0
fi
if [ -z "$pilot_codes_file" ] || [ ! -s "$pilot_codes_file" ]; then
  echo "需要传入内测访问码条目文件（形如 email=salt:hash）。" >&2
  exit 1
fi

rand() { openssl rand -hex "${1:-24}"; }

storage_password="$(rand 24)"
pilot_codes="$(tr -d '\r\n' < "$pilot_codes_file")"

cat > "$target" <<EOF
POSTGRES_PASSWORD=$(rand 24)
MINIO_ROOT_USER=migration_storage
MINIO_ROOT_PASSWORD=${storage_password}
AWS_ACCESS_KEY_ID=migration_storage
AWS_SECRET_ACCESS_KEY=${storage_password}
S3_REGION=ap-southeast-2
S3_USER_BUCKET=migration-user-files

ADMIN_API_KEY=$(rand 24)
WORKER_API_KEY=$(rand 24)
PILOT_AUTH_ENABLED=true
PILOT_JWT_SECRET=$(rand 32)
# 逐邮箱绑定的内测访问码：一个码只能登录它对应的邮箱。
PILOT_ACCESS_CODES=${pilot_codes}

# 回环部署：尚未确定域名前，只通过 SSH 隧道访问，不对外暴露。
# 确定域名后改成 https:// 地址，并同步更新 nginx 与 Certbot。
PUBLIC_WEB_URL=http://127.0.0.1:53103
PUBLIC_FILES_URL=http://127.0.0.1:59100
APP_ORIGIN=http://127.0.0.1:53103,http://127.0.0.1:53005,http://127.0.0.1:53004
SHARE_BASE_URL=http://127.0.0.1:53103
CRAWLER_USER_AGENT=MigrationCompanionMonitor/0.1 (+http://127.0.0.1:53103/privacy)
CRAWLER_INTERVAL_SECONDS=21600
NEWS_DISCOVERY_LIMIT=6

API_PORT=53101
ADMIN_PORT=53102
WEB_PORT=53103
MINIO_PORT=59100
EOF

chmod 600 "$target"
echo "已生成 $target（权限 600）。"
