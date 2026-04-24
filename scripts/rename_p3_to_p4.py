#!/usr/bin/env python
"""
P4 Step F: 把 p4_*.m 里的 p3_ 标识符全部改为 p4_。

只改代码标识符：
  - function 定义行：function [...] = p3_xxx(...)
  - 函数调用：p3_xxx(...)
注释里的历史说明（如"抽自 p3_demo_ui.m L1306"）保留。
"""
import re
from pathlib import Path

ui = Path("D:/Claude/TechReq/UWAcomm/modules/14_Streaming/src/Matlab/ui")

# 匹配：function 定义 + 调用
# 只匹配非注释区的 p3_xxx(
# MATLAB 注释以 % 开头。我们用简单策略：替换所有 p3_xxx( 为 p4_xxx(（即便在注释中，也是合理的，因为
# P4 版本里原 p3 的 demo 历史行号等已对应新文件，但历史引用如"L1306 抽自 p3_demo_ui.m"
# 本意指向 P3 文件，应保留）。折中：
#   - 替换 function 头部的 p3_ → p4_
#   - 替换调用模式：p3_xxx(  → p4_xxx(  （包含注释内的，简单起见）
#     但如果 p3_xxx 前紧邻 %，当前行是注释，就不替换
#
# 最安全：行级，如果行是注释（首个非空字符是 %）就只替换 "p3_" 后面紧跟参数(  形式中属于标识符引用的
# 但历史注释"抽自 p3_demo_ui.m L1306" 没有( 紧跟，所以不会命中。
# 于是只要替换 p3_\w+( → p4_\w+( 就行，注释中的 "抽自 p3_demo_ui.m" 不受影响。

CALL_RE = re.compile(r'\bp3_(\w+)\s*\(')
FUNC_DEF_RE = re.compile(r'^(\s*function\s+(?:\[?[^\]=]*\]?\s*=\s*)?)p3_(\w+)\s*\(')

for fp in sorted(ui.glob("p4_*.m")):
    src = fp.read_text(encoding='utf-8')
    new_lines = []
    for ln in src.splitlines():
        # function def at line start (possibly indented)
        m = FUNC_DEF_RE.match(ln)
        if m:
            ln = FUNC_DEF_RE.sub(r'\1p4_\2(', ln)
        # call sites: p3_xxx(  → p4_xxx(
        ln = CALL_RE.sub(lambda mo: 'p4_' + mo.group(1) + '(', ln)
        new_lines.append(ln)
    fp.write_text('\n'.join(new_lines) + '\n', encoding='utf-8')

print(f"Renamed {len(list(ui.glob('p4_*.m')))} files")
