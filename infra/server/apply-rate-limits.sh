#!/usr/bin/env bash
# 给 API 站点加上按来源 IP 的速率限制。
#
# 服务端已按邮箱做登录失败锁定，但那挡不住换邮箱轮询，也挡不住单一来源对整个 API 洪泛。
# 这里在 nginx 层补一层，并且只做**定点插入**——Certbot 管理的 listen/ssl 行原样保留。
# 修改前备份，nginx -t 失败自动回滚。
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
site=/etc/nginx/sites-available/migration-companion
zones=/etc/nginx/conf.d/migration-companion-ratelimit.conf

if [ ! -f "$site" ]; then
  echo "找不到 $site" >&2
  exit 1
fi
if ! grep -q 'include /etc/nginx/conf.d/\*\.conf;' /etc/nginx/nginx.conf; then
  echo "nginx.conf 未 include conf.d，脚本不做隐式修改，请手动确认。" >&2
  exit 1
fi

sudo cp "$here/migration-companion-ratelimit.conf" "$zones"
backup="${site}.bak.$(date +%Y%m%d%H%M%S)"
sudo cp -a "$site" "$backup"
echo "已备份站点配置到 $backup"

sudo python3 - "$site" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding='utf-8').read()

if 'limit_req zone=mc_' in text:
    print('速率限制已存在，未重复插入。')
    raise SystemExit(0)

# 只处理 API 那个 server 块（含 client_max_body_size 55m 的那个）。
start = text.index('server_name migration-companion-api')
end = text.index('\n}', start)
block = text[start:end]

extra_locations = '''
    # 速率限制区定义在 /etc/nginx/conf.d/migration-companion-ratelimit.conf。
    limit_conn mc_conn 20;

    # 内测登录：服务端已按邮箱锁定，这里按来源 IP 挡住换邮箱轮询与洪泛。
    location = /v1/auth/pilot {
        limit_req zone=mc_login burst=5 nodelay;
        proxy_pass http://127.0.0.1:53101;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # 无账号的分享访问码交换：允许收件人输错几次，但不允许暴力枚举。
    location ~ ^/v1/public/shares/[^/]+/access$ {
        limit_req zone=mc_share burst=10 nodelay;
        proxy_pass http://127.0.0.1:53101;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        # App 同步会有突发，用较大的 burst 吸收，正常使用不会触发。
        limit_req zone=mc_api burst=60 nodelay;'''

updated = block.replace('\n    location / {', extra_locations, 1)
if updated == block:
    raise SystemExit('未找到 API 站点的 location / 块，放弃修改。')

open(path, 'w', encoding='utf-8').write(text[:start] + updated + text[end:])
print('已插入速率限制。')
PY

if ! sudo nginx -t; then
  echo "nginx 校验失败，回滚。" >&2
  sudo cp -a "$backup" "$site"
  sudo rm -f "$zones"
  sudo nginx -t
  exit 1
fi

sudo systemctl reload nginx
echo "nginx 已重载，速率限制生效。"
