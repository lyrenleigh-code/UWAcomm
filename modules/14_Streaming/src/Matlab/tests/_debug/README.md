# 14_Streaming 调试脚本档案

P1/P2 实施过程中用过的一次性诊断脚本，保留参考。

| 文件 | 用途 | 关联问题 |
|------|------|----------|
| `diag_uilabel.m` | MATLAB R2025b 中 `uilabel` 是否可用（路径/缓存检查 + ver 完整列表） | P1 UI 启动报"函数无法识别"误诊 |
| `diag_ui_error.m` | 用 try/catch 包住 p1_demo_ui，捕获完整错误堆栈 | 定位 MATLAB 链式赋值陷阱 `uilabel(...).Layout = X` |

**常驻测试**（在父目录 `tests/`）：
- `test_p1_loopback_fhmfsk.m` — P1 单帧端到端
- `test_p2_multiframe.m` — P2 多帧端到端

未来 phase 的诊断脚本（如盲 Doppler 估计、并发 race 调试）也放这里，避免 tests/ 主目录污染。
