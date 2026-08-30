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
# 后台会话签名密钥，与内测密钥独立：内测密钥泄露不应该顺带交出管理后台。
# 缺了它管理员登录直接不可用——上一版这个脚本没有它，照它重建出来的服务器
# 会一切正常地跑起来，只有后台登不进去，而且看不出原因。
ADMIN_JWT_SECRET=$(rand 32)
# 逐邮箱绑定的内测访问码：一个码只能登录它对应的邮箱。
PILOT_ACCESS_CODES=${pilot_codes}

# 回环部署：尚未确定域名前，只通过 SSH 隧道访问，不对外暴露。
# 确定域名后改成 https:// 地址，并同步更新 nginx 与 Certbot。
PUBLIC_WEB_URL=http://127.0.0.1:53103
PUBLIC_FILES_URL=http://127.0.0.1:59100
APP_ORIGIN=http://127.0.0.1:53103,http://127.0.0.1:53005,http://127.0.0.1:53004
# 分享与协作邀请链接的对外地址。代码读的是 SHARE_ORIGIN；这里曾经写成
# SHARE_BASE_URL，没有任何代码读它，等于没配——生产环境下分享接口会直接
# 返回 503，而不是悄悄生成一条指向 localhost 的链接。
SHARE_ORIGIN=http://127.0.0.1:53103
# web 落地页镜像在构建期把它烘进 NEXT_PUBLIC_API_BASE，见 docker-compose.yml。
PUBLIC_API_URL=http://127.0.0.1:53101
# 云端文件默认关闭。代码判的是 === 'true'，缺失即关闭；这里写明白，
# 免得靠「没配置」来保证不上传。
CLOUD_FILES_ENABLED=false
CRAWLER_USER_AGENT=MigrationCompanionMonitor/0.1 (+http://127.0.0.1:53103/privacy)
CRAWLER_INTERVAL_SECONDS=21600
NEWS_DISCOVERY_LIMIT=6

# 以下三组需要在拿到对应账号后手工填写，留空不影响服务启动：
# 托管登录（未接入时留空，走内测访问码）
COGNITO_USER_POOL_ID=
COGNITO_CLIENT_ID=
# 应用内订阅的商品 ID，与商店后台保持一致
STORE_MONTHLY_PRODUCT_ID=
STORE_YEARLY_PRODUCT_ID=

API_PORT=53101
ADMIN_PORT=53102
WEB_PORT=53103
MINIO_PORT=59100
EOF

chmod 600 "$target"
echo "已生成 $target（权限 600）。"
