r"""
sync_readme_index.py - Scan UWAcomm module READMEs, generate wiki function indexes

Usage:
    python scripts/sync_readme_index.py
    python scripts/sync_readme_index.py --project D:\Claude\TechReq\UWAcomm\modules --output wiki/modules
"""

import re
import os
import sys
import argparse
from datetime import date
from pathlib import Path


# ─── 配置 ───────────────────────────────────────────────

DEFAULT_PROJECTS = [
    {
        "name": "UWAcomm",
        "root": r"D:\Claude\TechReq\UWAcomm\modules",
        "vault_subdir": r"modules",
        "module_pattern": r"(\d{2}_\w+)",  # 01_SourceCoding 等
        "readme_subpath": r"src\Matlab\README.md",
    },
]

DEFAULT_VAULT = r"D:\Claude\TechReq\UWAcomm\wiki"


# ─── 解析 README ────────────────────────────────────────

def parse_readme(readme_path: str) -> dict:
    """解析一个模块 README.md，提取关键信息"""
    with open(readme_path, "r", encoding="utf-8") as f:
        content = f.read()

    result = {
        "title": "",
        "description": "",
        "functions": [],
        "test_info": "",
        "source_path": readme_path,
    }

    lines = content.split("\n")

    # 1. 标题（第一个 # 标题）
    for line in lines:
        if line.startswith("# "):
            result["title"] = line[2:].strip()
            break

    # 2. 描述（标题后第一段非空文字）
    title_found = False
    for line in lines:
        if line.startswith("# "):
            title_found = True
            continue
        if title_found and line.strip() and not line.startswith("#") and not line.startswith("---"):
            result["description"] = line.strip()
            break

    # 3. 对外接口函数（从表格中提取）
    result["functions"] = extract_functions(content)

    # 4. 测试覆盖信息
    test_match = re.search(r"## 测试覆盖[^\n]*\n", content)
    if test_match:
        result["test_info"] = test_match.group(0).strip().replace("## ", "")

    return result


def extract_functions(content: str) -> list:
    """从 README 中提取函数列表

    支持两种格式：
    1. 表格行：| `func_name` | `[out] = func(in)` | 说明 |
    2. ### func_name 章节标题
    """
    functions = []
    seen = set()

    # 模式1：表格中 | `func_name` | ... 格式
    # 匹配 | `ch_est_ls` | `[H_est, h_est] = ch_est_ls(...)` | 说明 |
    table_pattern = re.compile(
        r"\|\s*`(\w+)`\s*\|\s*`([^`]+)`\s*\|\s*([^|]+)\|"
    )
    for m in table_pattern.finditer(content):
        name = m.group(1)
        signature = m.group(2).strip()
        desc = m.group(3).strip()
        if name not in seen and not name.startswith("参数"):
            functions.append({"name": name, "signature": signature, "description": desc})
            seen.add(name)

    # 模式2：### func_name 章节 + **功能**：xxx
    section_pattern = re.compile(r"^### (\w+)\s*$", re.MULTILINE)
    func_desc_pattern = re.compile(r"\*\*功能\*\*[：:]\s*(.+)")
    for m in section_pattern.finditer(content):
        name = m.group(1)
        if name in seen or name[0].isdigit():
            continue
        # 在该章节后查找功能描述
        after = content[m.end():m.end() + 500]
        desc_match = func_desc_pattern.search(after)
        desc = desc_match.group(1).strip() if desc_match else ""
        if desc:
            functions.append({"name": name, "signature": "", "description": desc})
            seen.add(name)

    # 模式3：#### `func_name` -- 说明 或 ### func_name — 说明
    h4_pattern = re.compile(r"^#{3,4}\s+`?(\w+)`?\s*[-—]+\s*(.+)$", re.MULTILINE)
    for m in h4_pattern.finditer(content):
        name = m.group(1)
        desc = m.group(2).strip()
        if name not in seen:
            functions.append({"name": name, "signature": "", "description": desc})
            seen.add(name)

    # 模式4：### `func_name`（反引号包裹的标题，描述在下一行或 **功能** 标记中）
    h3_bt_pattern = re.compile(r"^#{3,4}\s+`(\w+)`\s*$", re.MULTILINE)
    for m in h3_bt_pattern.finditer(content):
        name = m.group(1)
        if name in seen:
            continue
        after = content[m.end():m.end() + 500]
        # 尝试 **功能**：标记
        desc_match = func_desc_pattern.search(after)
        if desc_match:
            desc = desc_match.group(1).strip()
        else:
            # 取下一个非空行作为描述
            for line in after.split("\n"):
                line = line.strip()
                if line and not line.startswith("|") and not line.startswith("#") and not line.startswith("**"):
                    desc = line
                    break
            else:
                desc = ""
        if name not in seen:
            functions.append({"name": name, "signature": "", "description": desc[:80]})
            seen.add(name)

    return functions


# ─── 生成 Obsidian 索引 ─────────────────────────────────

def generate_index(module_name: str, parsed: dict, project_name: str) -> str:
    """生成一个模块的 Obsidian 函数索引 Markdown"""
    today = date.today().isoformat()
    source = parsed["source_path"].replace("\\", "/")

    lines = [
        "---",
        f'tags: [自动生成, 函数索引, {project_name}]',
        f'sync-source: "{source}"',
        f"last-sync: {today}",
        "---",
        "",
        f"# {module_name} — 函数索引",
        "",
        f"> 自动生成，勿手动编辑。源文件：`{source}`",
        f"> {parsed['description']}" if parsed["description"] else "",
        "",
    ]

    if parsed["test_info"]:
        lines.append(f"**{parsed['test_info']}**")
        lines.append("")

    if parsed["functions"]:
        lines.append(f"## 函数列表（{len(parsed['functions'])} 个）")
        lines.append("")
        lines.append("| 函数 | 说明 |")
        lines.append("|------|------|")
        for func in parsed["functions"]:
            name = func["name"]
            desc = func["description"]
            lines.append(f"| `{name}` | {desc} |")
        lines.append("")
    else:
        lines.append("*未检测到函数定义*")
        lines.append("")

    return "\n".join(lines)


def generate_summary(all_modules: list, project_name: str) -> str:
    """生成汇总索引"""
    today = date.today().isoformat()
    total_funcs = sum(len(m["parsed"]["functions"]) for m in all_modules)

    lines = [
        "---",
        f"tags: [自动生成, 函数索引, {project_name}]",
        f"last-sync: {today}",
        "---",
        "",
        f"# {project_name} 全模块函数索引",
        "",
        f"> 自动生成，勿手动编辑。共 {len(all_modules)} 个模块，{total_funcs} 个函数。",
        "",
        "## 模块概览",
        "",
        "| 模块 | 函数数 | 说明 |",
        "|------|--------|------|",
    ]

    for m in all_modules:
        name = m["module_name"]
        count = len(m["parsed"]["functions"])
        desc = m["parsed"]["description"][:50] if m["parsed"]["description"] else ""
        lines.append(f"| [[{name}\\|{name}]] | {count} | {desc} |")

    lines.append("")
    lines.append("## 全部函数")
    lines.append("")
    lines.append("| 函数 | 模块 | 说明 |")
    lines.append("|------|------|------|")

    for m in all_modules:
        mod = m["module_name"]
        for func in m["parsed"]["functions"]:
            lines.append(f"| `{func['name']}` | {mod} | {func['description']} |")

    lines.append("")
    return "\n".join(lines)


# ─── 主逻辑 ─────────────────────────────────────────────

def sync_project(project_config: dict, vault_root: str):
    """同步一个项目的所有模块"""
    proj_root = project_config["root"]
    proj_name = project_config["name"]
    vault_subdir = project_config["vault_subdir"]
    readme_subpath = project_config["readme_subpath"]
    module_pattern = re.compile(project_config["module_pattern"])

    vault_proj_dir = os.path.join(vault_root, vault_subdir)

    print(f"项目: {proj_name}")
    print(f"  源目录: {proj_root}")
    print(f"  Vault: {vault_proj_dir}")
    print()

    all_modules = []

    # 扫描模块目录
    if not os.path.isdir(proj_root):
        print(f"  ERROR: 项目目录不存在: {proj_root}")
        return

    for entry in sorted(os.listdir(proj_root)):
        if not module_pattern.match(entry):
            continue

        readme_path = os.path.join(proj_root, entry, readme_subpath)
        if not os.path.isfile(readme_path):
            print(f"  SKIP: {entry} (无 README.md)")
            continue

        # 解析 README
        parsed = parse_readme(readme_path)
        func_count = len(parsed["functions"])

        module_info = {
            "module_name": entry,
            "parsed": parsed,
        }
        all_modules.append(module_info)

        # 生成索引文件
        index_content = generate_index(entry, parsed, proj_name)

        # 确保输出目录存在
        output_dir = os.path.join(vault_proj_dir, entry)
        os.makedirs(output_dir, exist_ok=True)

        output_path = os.path.join(output_dir, "函数索引.md")
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(index_content)

        print(f"  {entry}: {func_count} 个函数 -> {output_path}")

    # 生成汇总索引
    if all_modules:
        summary = generate_summary(all_modules, proj_name)
        summary_path = os.path.join(vault_proj_dir, "全模块函数索引.md")
        with open(summary_path, "w", encoding="utf-8") as f:
            f.write(summary)
        total = sum(len(m["parsed"]["functions"]) for m in all_modules)
        print(f"\n  汇总: {len(all_modules)} 模块, {total} 函数 -> {summary_path}")


def main():
    parser = argparse.ArgumentParser(description="同步项目 README 到 wiki 函数索引")
    parser.add_argument("--vault", default=DEFAULT_VAULT, help="wiki 输出根目录")
    parser.add_argument("--project", help="模块根目录（覆盖默认配置）")
    parser.add_argument("--name", default="UWAcomm", help="项目名称")
    args = parser.parse_args()

    if args.project:
        projects = [{
            "name": args.name,
            "root": args.project,
            "vault_subdir": "modules",
            "module_pattern": r"(\d{2}_\w+)",
            "readme_subpath": r"src\Matlab\README.md",
        }]
    else:
        projects = DEFAULT_PROJECTS

    print(f"=== sync_readme_index.py ===")
    print(f"Vault: {args.vault}")
    print()

    for proj in projects:
        sync_project(proj, args.vault)

    print("\nDone!")


if __name__ == "__main__":
    main()
