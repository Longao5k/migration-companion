#!/usr/bin/env bash
# 提高 nginx 的 server_names_hash_bucket_size。
#
# 产品域名较长（migration-companion-api.<主域名>），默认 64 字节的桶装不下，
# nginx -t 会直接失败。这是官方给出的标准修复，改动只影响哈希表容量，不改变任何站点行为。
# 修改前会备份原文件。
set -euo pipefail

conf=/etc/nginx/nginx.conf
# 备份一律写到 /etc/nginx/backups/，不要写在被 nginx include 的目录里。
# 曾经在 sites-enabled/ 里留下过两份 .bak，nginx 会把该目录下**所有**文件当配置加载，
# 结果是同一个 server_name 有三份配置同时生效、16 条 conflicting server name 告警，
# 靠加载顺序侥幸没出事——而其中一份比后台路由和安全头都旧。
backup_dir=/etc/nginx/backups
sudo mkdir -p "$backup_dir"
backup="$backup_dir/$(basename "$conf").bak.$(date +%Y%m%d%H%M%S)"

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
