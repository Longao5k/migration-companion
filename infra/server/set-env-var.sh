#!/usr/bin/env bash
# 设置或替换 infra/server/.env 中的一个变量，并清理空行/残留行。
# 用法：bash infra/server/set-env-var.sh <KEY> <VALUE>
# 敏感值可从标准输入读取，避免出现在进程参数里：
#   printf '%s' "$SECRET" | bash infra/server/set-env-var.sh <KEY> --stdin
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
env_file="$here/.env"
key="${1:-}"
value_arg="${2:-}"

if [ ! -f "$env_file" ]; then
  echo "找不到 $env_file。" >&2
  exit 1
fi
if [ -z "$key" ]; then
  echo "用法：set-env-var.sh <KEY> <VALUE|--stdin>" >&2
  exit 1
fi
if [ "$value_arg" = "--stdin" ]; then
  value="$(cat)"
else
  value="$value_arg"
fi

python3 - "$env_file" "$key" "$value" <<'PY'
import re, sys
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path, encoding='utf-8').read().splitlines()
# 丢掉之前被 shell 转义搞坏的残留行：既不是注释也不含 '='。
lines = [l for l in lines if not l.strip() or l.lstrip().startswith('#') or '=' in l]
out, replaced = [], False
for line in lines:
    if re.match(rf'^{re.escape(key)}=', line):
        if not replaced:
            out.append(f'{key}={value}')
            replaced = True
    else:
        out.append(line)
if not replaced:
    out.append(f'{key}={value}')
open(path, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
PY

chmod 600 "$env_file"
echo "已设置 ${key}。"
