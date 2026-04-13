#!/usr/bin/env python3
"""
网页抓取脚本：使用 Firecrawl 将 URL 内容转为 markdown。
用法：
  python scripts/scrape.py <URL> [--type article|video|thread]

需要设置环境变量：FIRECRAWL_API_KEY
或在项目根目录 .env 中配置。

示例：
  python scripts/scrape.py "https://example.com/article" --type article
  python scripts/scrape.py "https://youtube.com/watch?v=xxx" --type video
"""
import sys
import os
import io
import argparse
import re
from datetime import date

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

# 尝试从 .env 文件加载 API key
ENV_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env")
if os.path.exists(ENV_PATH):
    with open(ENV_PATH, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, val = line.split("=", 1)
                os.environ.setdefault(key.strip(), val.strip())


def slugify(text, max_len=50):
    """将标题转为文件名友好格式"""
    text = re.sub(r'[^\w\s-]', '', text.lower())
    text = re.sub(r'[\s_]+', '-', text)
    return text[:max_len].rstrip('-')


def scrape(url, output_type):
    from firecrawl import FirecrawlApp

    api_key = os.environ.get("FIRECRAWL_API_KEY")
    if not api_key:
        print("错误：未设置 FIRECRAWL_API_KEY")
        print(f"请在 {ENV_PATH} 中添加：FIRECRAWL_API_KEY=your_key")
        print("获取 API Key：https://firecrawl.dev")
        sys.exit(1)

    app = FirecrawlApp(api_key=api_key)

    print(f"抓取中：{url}")
    result = app.scrape_url(url, params={"formats": ["markdown"]})

    markdown = result.get("markdown", "")
    metadata = result.get("metadata", {})
    title = metadata.get("title", "untitled")

    today = date.today().isoformat()
    filename = f"{today}-{slugify(title)}.md"

    type_map = {
        "article": ("raw/articles", "文章"),
        "video": ("raw/videos", "视频"),
        "thread": ("raw/threads", "帖子"),
    }
    output_dir, type_label = type_map.get(output_type, ("raw/articles", "文章"))
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, filename)

    md_content = f"""# {title}

- **来源**：{url}
- **日期**：{today}
- **类型**：{type_label}
- **抓取工具**：Firecrawl

---

{markdown}
"""

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(md_content)

    print(f"保存成功：{output_path}")
    print(f"下一步：运行 /ingest-source {output_path}")


def main():
    parser = argparse.ArgumentParser(description="Firecrawl 网页抓取")
    parser.add_argument("url", help="目标 URL")
    parser.add_argument("--type", dest="output_type", default="article",
                        choices=["article", "video", "thread"],
                        help="输出类型（默认 article）")
    args = parser.parse_args()
    scrape(args.url, args.output_type)


if __name__ == "__main__":
    main()
