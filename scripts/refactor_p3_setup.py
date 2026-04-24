#!/usr/bin/env python
"""
P3 Step 3: 将 p3_demo_ui.m 的 setup 段（L113-543）拆成 4 个嵌套函数。

Sections:
  build_topbar(main)         : L113-224  (顶栏)
  build_middle_panels(main)  : L226-434  (中部 TX/RX)
  build_bottom_tabs(main)    : L436-532  (底部 7 tab + 深色样式)
  start_timer_and_init()     : L534-543  (定时器 + 初始化)
"""
from pathlib import Path

FP = Path("D:/Claude/TechReq/UWAcomm/modules/14_Streaming/src/Matlab/ui/p3_demo_ui.m")

lines = FP.read_text(encoding='utf-8').splitlines(keepends=False)

# 1-based → 0-based
def block(start, end):
    return lines[start-1:end]

preamble        = block(1, 112)     # function header + state + style + main figure/grid
sec_topbar      = block(113, 224)   # 顶栏
sec_middle      = block(226, 434)   # 中部 TX/RX
# L225 空行
sec_bottom      = block(436, 532)   # 底部 tab + 深色样式应用
sec_timer_init  = block(534, 543)   # 定时器 + 初始化 + on_scheme_changed
nested_tail     = block(545, len(lines))  # 所有既有嵌套函数 + outer end

def indent_block(block_lines, spaces=4):
    pad = ' ' * spaces
    out = []
    for ln in block_lines:
        if ln == '':
            out.append('')
        else:
            out.append(pad + ln)
    return out

def wrap_nested(name, args, body_lines):
    header = f"function {name}({args})"
    return [header] + indent_block(body_lines, 4) + ['end', '']

# Build new file content
new_lines = []
new_lines.extend(preamble)
new_lines.append('')
new_lines.append('%% ==== UI 构建（嵌套函数）====')
new_lines.append('build_topbar(main);')
new_lines.append('build_middle_panels(main);')
new_lines.append('build_bottom_tabs(main);')
new_lines.append('start_timer_and_init();')
new_lines.append('')
# Nested function block header (preserving the original separator)
new_lines.append('%% ============================================================')
new_lines.append('%% 内部函数')
new_lines.append('%% ============================================================')
new_lines.append('')

# 4 new nested functions — insert first (before mk_row etc.)
new_lines.extend(wrap_nested('build_topbar', 'main', sec_topbar))
new_lines.extend(wrap_nested('build_middle_panels', 'main', sec_middle))
new_lines.extend(wrap_nested('build_bottom_tabs', 'main', sec_bottom))
new_lines.extend(wrap_nested('start_timer_and_init', '', sec_timer_init))

# Keep all existing nested functions — skip the "%% ============" header and "%% 内部函数"
# nested_tail starts at L545 which is "%% ==============..."
# We already added that header above, so skip to first actual 'function' keyword
for i, ln in enumerate(nested_tail):
    stripped = ln.lstrip()
    if stripped.startswith('function '):
        start_idx = i
        break
else:
    raise RuntimeError("Could not find first nested function in nested_tail")

new_lines.extend(nested_tail[start_idx:])

FP.write_text('\n'.join(new_lines) + '\n', encoding='utf-8')
print(f"Rewrote {FP}, total lines: {len(new_lines)}")
