#!/usr/bin/env python3
"""
音视频转录脚本：使用 Whisper 将本地音视频文件转录为 markdown。
用法：
  python scripts/transcribe.py <输入文件> [--lang Chinese] [--type video|podcast]

依赖：pip install openai-whisper  （需要 ffmpeg）

示例：
  python scripts/transcribe.py lecture.mp4
  python scripts/transcribe.py podcast.mp3 --type podcast --lang Chinese
"""
import sys
import os
import io
import argparse
from datetime import date

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")


def transcribe(input_path, language, output_type, model_size):
    import whisper

    if not os.path.exists(input_path):
        print(f"错误：文件不存在 — {input_path}")
        sys.exit(1)

    filename = os.path.splitext(os.path.basename(input_path))[0]
    today = date.today().isoformat()
    output_name = f"{today}-{filename}.md"

    if output_type == "podcast":
        output_dir = "raw/podcasts"
    else:
        output_dir = "raw/videos"

    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, output_name)

    print(f"加载 Whisper 模型（{model_size}）...")
    model = whisper.load_model(model_size)

    print(f"转录中：{input_path}")
    result = model.transcribe(input_path, language=language)

    # 按段落组织文本
    segments = result.get("segments", [])
    paragraphs = []
    current_paragraph = []
    for seg in segments:
        text = seg["text"].strip()
        if text:
            current_paragraph.append(text)
        if len(current_paragraph) >= 5:
            paragraphs.append("".join(current_paragraph))
            current_paragraph = []
    if current_paragraph:
        paragraphs.append("".join(current_paragraph))

    body = "\n\n".join(paragraphs) if paragraphs else result["text"]

    type_label = "播客" if output_type == "podcast" else "视频"
    md_content = f"""# {filename}

- **来源**：{os.path.abspath(input_path)}
- **日期**：{today}
- **类型**：{type_label}
- **语言**：{language}
- **转录工具**：Whisper ({model_size})

---

{body}
"""

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(md_content)

    print(f"转录完成：{output_path}")
    print(f"下一步：运行 /ingest-source {output_path}")


def main():
    parser = argparse.ArgumentParser(description="Whisper 音视频转录")
    parser.add_argument("input", help="输入音视频文件路径")
    parser.add_argument("--lang", default="Chinese", help="语言（默认 Chinese）")
    parser.add_argument("--type", dest="output_type", default="video",
                        choices=["video", "podcast"], help="输出类型")
    parser.add_argument("--model", default="base",
                        choices=["tiny", "base", "small", "medium", "large"],
                        help="Whisper 模型大小（默认 base）")
    args = parser.parse_args()
    transcribe(args.input, args.lang, args.output_type, args.model)


if __name__ == "__main__":
    main()
