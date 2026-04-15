#!/usr/bin/env python3
"""
14_Streaming/sessions/ 清理工具

每次 demo 运行会在 modules/14_Streaming/sessions/ 下产生 session_<ts>/ 目录，
含 raw_frames/channel_frames/rx_out 子目录与 wav/meta.mat/ready 等文件。
长期累积占空间。本脚本删除超过 N 天的 session 目录。

用法：
  python scripts/clean_streaming_sessions.py             # 默认 dry-run，删 7 天前
  python scripts/clean_streaming_sessions.py --days 3    # 改 3 天
  python scripts/clean_streaming_sessions.py --apply     # 真删除
  python scripts/clean_streaming_sessions.py --keep-last 5  # 保留最近 5 个
"""

import argparse
import datetime
import re
import shutil
import sys
from pathlib import Path

SESSION_DIR_PATTERN = re.compile(r"^session_(\d{4}-\d{2}-\d{2}-\d{6})(?:-\d+)?$")


def parse_session_timestamp(name: str) -> datetime.datetime | None:
    m = SESSION_DIR_PATTERN.match(name)
    if not m:
        return None
    try:
        return datetime.datetime.strptime(m.group(1), "%Y-%m-%d-%H%M%S")
    except ValueError:
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description="清理 14_Streaming sessions/")
    parser.add_argument("--root", default=None,
                        help="项目根目录（默认 git rev-parse 推断）")
    parser.add_argument("--days", type=int, default=7,
                        help="删除超过 N 天的 session（默认 7）")
    parser.add_argument("--keep-last", type=int, default=0,
                        help="始终保留最近 N 个 session（不论年龄）")
    parser.add_argument("--apply", action="store_true",
                        help="真删除（默认 dry-run，仅打印）")
    args = parser.parse_args()

    if args.root:
        root = Path(args.root).resolve()
    else:
        # 从本脚本路径推断（scripts/.. = 项目根）
        root = Path(__file__).resolve().parent.parent

    sessions_dir = root / "modules" / "14_Streaming" / "sessions"
    if not sessions_dir.exists():
        print(f"[INFO] sessions 目录不存在：{sessions_dir}")
        return 0

    cutoff = datetime.datetime.now() - datetime.timedelta(days=args.days)

    sessions = []
    for entry in sessions_dir.iterdir():
        if not entry.is_dir():
            continue
        ts = parse_session_timestamp(entry.name)
        if ts is None:
            continue
        sessions.append((entry, ts))

    if not sessions:
        print("[INFO] 没有 session 目录")
        return 0

    sessions.sort(key=lambda x: x[1], reverse=True)

    keep_recent = set()
    if args.keep_last > 0:
        keep_recent = {p for p, _ in sessions[:args.keep_last]}
        print(f"[KEEP] 保留最近 {args.keep_last} 个 session")

    to_delete = []
    to_keep = []
    for path, ts in sessions:
        if path in keep_recent:
            to_keep.append((path, ts, "recent"))
        elif ts < cutoff:
            to_delete.append((path, ts))
        else:
            to_keep.append((path, ts, f"<{args.days}d"))

    print(f"\n--- {sessions_dir} ---")
    print(f"总 session: {len(sessions)}")
    print(f"待删除（>{args.days} 天且不在最近 {args.keep_last} 个）: {len(to_delete)}")
    print(f"保留: {len(to_keep)}\n")

    if to_delete:
        print("--- 待删除 ---")
        for path, ts in to_delete:
            size_mb = sum(f.stat().st_size for f in path.rglob("*") if f.is_file()) / 1e6
            print(f"  {path.name}  ({ts.strftime('%Y-%m-%d %H:%M')}, {size_mb:.1f} MB)")
        print()

    if to_keep:
        print("--- 保留 ---")
        for path, ts, reason in to_keep:
            print(f"  {path.name}  ({ts.strftime('%Y-%m-%d %H:%M')}, {reason})")
        print()

    if not args.apply:
        print("[DRY-RUN] 加 --apply 参数实际删除")
        return 0

    if not to_delete:
        print("[INFO] 无需删除")
        return 0

    print(f"[APPLY] 删除 {len(to_delete)} 个 session...")
    deleted_mb = 0
    for path, _ in to_delete:
        size_mb = sum(f.stat().st_size for f in path.rglob("*") if f.is_file()) / 1e6
        try:
            shutil.rmtree(path)
            deleted_mb += size_mb
            print(f"  [OK] {path.name}")
        except Exception as e:
            print(f"  [FAIL] {path.name}: {e}")
    print(f"\n[DONE] 释放 ~{deleted_mb:.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
