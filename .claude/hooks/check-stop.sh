#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

python3 "$PROJECT_DIR/scripts/validate_task.py" || {
  echo "任务未完成：缺少必要文件、测试或 wiki 更新。" >&2
  exit 2
}

exit 0
