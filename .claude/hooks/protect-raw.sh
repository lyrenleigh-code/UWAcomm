#!/usr/bin/env bash
set -euo pipefail

INPUT="$(cat)"
FILE_PATH="$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path','') or d.get('tool_input',{}).get('path',''))" 2>/dev/null || echo "")"

if [[ "$FILE_PATH" == *"/raw/"* ]] || [[ "$FILE_PATH" == raw/* ]]; then
  echo "禁止修改 raw/ 目录。请将整理后的内容写入 wiki/。" >&2
  exit 2
fi

exit 0
