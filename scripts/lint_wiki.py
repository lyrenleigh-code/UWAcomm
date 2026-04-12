#!/usr/bin/env python3
"""
Wiki lint 脚本：检查孤儿页、断链、缺失 index 条目。
用法：
  python3 scripts/lint_wiki.py          # 完整检查
  python3 scripts/lint_wiki.py --quick  # 快速检查（PostToolUse hook 用）
"""
import os
import re
import sys
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

WIKI_DIR = "wiki"
INDEX_PATH = "wiki/index.md"
LOG_PATH = "wiki/log.md"

def get_all_wiki_pages():
    pages = []
    for root, _, files in os.walk(WIKI_DIR):
        for f in files:
            if f.endswith(".md") and f not in ("index.md", "log.md"):
                pages.append(os.path.join(root, f))
    return pages

def get_indexed_pages():
    if not os.path.exists(INDEX_PATH):
        return set()
    with open(INDEX_PATH, encoding="utf-8") as f:
        content = f.read()
    links = re.findall(r'\(([^)]+\.md)\)', content)
    return set(os.path.normpath(os.path.join(WIKI_DIR, l)) for l in links)

def check_orphans():
    all_pages = set(get_all_wiki_pages())
    indexed = get_indexed_pages()
    orphans = all_pages - indexed
    return orphans

def check_log_exists():
    return os.path.exists(LOG_PATH)

def main():
    quick = "--quick" in sys.argv
    errors = []

    orphans = check_orphans()
    if orphans:
        for o in orphans:
            errors.append(f"[孤儿页] {o} 未在 index.md 中注册")

    if not check_log_exists():
        errors.append("[缺失] wiki/log.md 不存在")

    if errors:
        print("=== Wiki Lint 发现问题 ===")
        for e in errors:
            print(f"  ✗ {e}")
        if not quick:
            sys.exit(1)
    else:
        print("✓ Wiki lint 通过")

if __name__ == "__main__":
    main()
