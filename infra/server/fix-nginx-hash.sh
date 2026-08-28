#!/usr/bin/env bash
# 提高 nginx 的 server_names_hash_bucket_size。
#
# 产品域名较长（migration-companion-api.<主域名>），默认 64 字节的桶装不下，
# nginx -t 会直接失败。这是官方给出的标准修复，改动只影响哈希表容量，不改变任何站点行为。
# 修改前会备份原文件。
set -euo pipefail

conf=/etc/nginx/nginx.conf
backup="${conf}.bak.$(date +%Y%m%d%H%M%S)"

if grep -qE '^\s*server_names_hash_bucket_size\s+' "$conf"; then
  echo "已存在生效中的 server_names_hash_bucket_size，未改动。"
  exit 0
fi

sudo cp -a "$conf" "$backup"
echo "已备份到 $backup"

# 把被注释掉的那一行替换成生效的 128。
sudo sed -i 's|^\(\s*\)#\s*server_names_hash_bucket_size .*|\1server_names_hash_bucket_size 128;|' "$conf"

if ! grep -qE '^\s*server_names_hash_bucket_size\s+128;' "$conf"; then
  echo "未能就地替换，回滚。" >&2
  sudo cp -a "$backup" "$conf"
  exit 1
fi

sudo nginx -t
echo "nginx 配置校验通过。"
