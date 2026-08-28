#!/usr/bin/env bash
# 把内测访问码条目写入 infra/server/.env 的 PILOT_ACCESS_CODES。
#
# 只接受哈希条目（形如 email=salt:hash），访问码明文不进入服务器，也不进入命令行历史。
# 用法：bash infra/server/set-pilot-codes.sh <条目文件>
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
env_file="$here/.env"
entries_file="${1:-}"

if [ ! -f "$env_file" ]; then
  echo "找不到 $env_file，请先运行 bootstrap-env.sh。" >&2
  exit 1
fi
if [ -z "$entries_file" ] || [ ! -s "$entries_file" ]; then
  echo "需要传入内测访问码条目文件。" >&2
  exit 1
fi

entries="$(tr -d '\r' < "$entries_file" | tr '\n' ',' | sed 's/,\+$//')"
if ! printf '%s' "$entries" | grep -Eq '^[^=,]+=[a-f0-9]{32}:[a-f0-9]{64}(,[^=,]+=[a-f0-9]{32}:[a-f0-9]{64})*$'; then
  echo "条目格式无效，期望 email=<32位salt>:<64位hash>，多个用换行或逗号分隔。" >&2
  exit 1
fi

python3 - "$env_file" "$entries" <<'PY'
import sys
path, entries = sys.argv[1], sys.argv[2]
lines = open(path, encoding='utf-8').read().splitlines()
out, replaced = [], False
for line in lines:
    if line.startswith('PILOT_ACCESS_CODES='):
        out.append('PILOT_ACCESS_CODES=' + entries)
        replaced = True
    else:
        out.append(line)
if not replaced:
    out.append('PILOT_ACCESS_CODES=' + entries)
open(path, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
PY

chmod 600 "$env_file"
count="$(printf '%s' "$entries" | tr ',' '\n' | grep -c .)"
echo "已写入 ${count} 个内测账号条目。"
