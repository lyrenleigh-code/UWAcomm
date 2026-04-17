#!/usr/bin/env python3
"""
PreToolUse hook：阻止含 `<private>...</private>` 标签的内容写入公开路径。

动机：
- Hub 有 Pricing 🔒 等私人项目，内容不应漏到公开 wiki/ 或 projects/ 导航页
- 借鉴自 claude-mem 的 `<private>` tag + hook 层脱敏模式（see wiki/source-summaries/thedotmack-claude-mem.md §4）
- Ohmybrain 选择"阻断"而非"脱敏"，强制用户显式处理（避免隐式丢失）

协议：Claude Code 通过 stdin 传入 JSON，格式：
  {"tool_name": "Write"|"Edit", "tool_input": {"file_path": "...", "content"|"new_string": "..."}}
阻断方式：exit(2) + stderr 输出原因。

保护范围：
- `wiki/**` — 知识层
- `projects/**` — 项目导航页
- 可通过 `.claude/private-paths.txt` 扩展（每行一个 glob；未实现则用默认）

放行范围：
- `raw/**` — 原始资料（独立由 check_raw_write.py 完全只读保护）
- 其他路径（specs/scripts/...）— 项目内部工作区，允许 `<private>` 存在
"""
from __future__ import annotations

import io
import json
import re
import sys
from typing import Final

sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8")

PROTECTED_GLOBS: Final[tuple[str, ...]] = ("wiki/", "projects/")
PRIVATE_TAG_RE: Final[re.Pattern[str]] = re.compile(
    r"<private\b[^>]*>.*?</private>", re.DOTALL | re.IGNORECASE
)


def extract_content(tool_name: str, tool_input: dict) -> str:
    """从 tool_input 提取将要写入的内容字符串。"""
    if tool_name == "Write":
        return tool_input.get("content", "") or ""
    if tool_name == "Edit":
        return tool_input.get("new_string", "") or ""
    return ""


def is_protected(path: str) -> bool:
    """判断路径是否属于受保护的公开路径。"""
    normalized = path.replace("\\", "/")
    return any(glob in normalized for glob in PROTECTED_GLOBS)


def main() -> None:
    try:
        data = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {}) or {}
    path = tool_input.get("file_path", "") or ""

    if not is_protected(path):
        sys.exit(0)

    content = extract_content(tool_name, tool_input)
    match = PRIVATE_TAG_RE.search(content)
    if match is None:
        sys.exit(0)

    snippet = match.group(0)
    preview = snippet[:80].replace("\n", " ") + ("..." if len(snippet) > 80 else "")
    print(
        f"[BLOCKED] 检测到 <private> 标签内容即将写入公开路径：{path}\n"
        f"片段预览：{preview}\n"
        "\n"
        "Ohmybrain 策略：公开 wiki/ 与 projects/ 下禁止出现 <private> 标签。\n"
        "处理方式（任选其一）：\n"
        "  1. 移除 <private>...</private> 块，写入公开摘要（推荐）\n"
        "  2. 将内容改写到对应私项目仓内部（如 Pricing）\n"
        "  3. 仅在 raw/notes/ 或项目私人路径下保留\n",
        file=sys.stderr,
    )
    sys.exit(2)


if __name__ == "__main__":
    main()
