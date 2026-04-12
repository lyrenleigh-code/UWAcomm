#!/usr/bin/env python3
"""
自动同步 wiki/index.md 的页面计数。
扫描 wiki/ 下所有 .md 文件（排除 index.md 和 log.md），更新总数。
"""
import os
import re
import sys
import io
from datetime import date

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

WIKI_DIR = "wiki"
INDEX_PATH = "wiki/index.md"


def count_pages():
    count = 0
    for root, _, files in os.walk(WIKI_DIR):
        for f in files:
            if f.endswith(".md") and f not in ("index.md", "log.md"):
                count += 1
    return count


def main():
    if not os.path.exists(INDEX_PATH):
        print("错误：wiki/index.md 不存在")
        sys.exit(1)

    with open(INDEX_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    actual = count_pages()
    today = date.today().isoformat()

    # 更新页面总数
    content = re.sub(
        r"页面总数：\d+",
        f"页面总数：{actual}",
        content
    )
    # 更新日期
    content = re.sub(
        r"最后更新：\d{4}-\d{2}-\d{2}",
        f"最后更新：{today}",
        content
    )

    with open(INDEX_PATH, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"✓ index.md 已同步：{actual} 个页面，日期 {today}")


if __name__ == "__main__":
    main()
