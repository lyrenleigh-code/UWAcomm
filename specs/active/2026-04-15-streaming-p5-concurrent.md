---
project: uwacomm
type: task
status: placeholder
created: 2026-04-15
updated: 2026-04-15
parent: 2026-04-15-streaming-framework-master.md
phase: P5
depends_on: [P4]
tags: [流式仿真, 14_Streaming, 并发, 多进程]
---

# Streaming P5 — 三进程并发（TX / Channel / RX）

## Spec

### 目标

三个独立 MATLAB 进程（手动或脚本分别启动），通过**每帧独立 wav 文件 + `.ready` 标记**共享数据流（方案 B，见 master spec）：

- **TX 进程**：读文本输入（stdin/文件），每帧生成 `session/raw_frames/NNNN.wav`，close 后创建 `NNNN.ready`
- **Channel daemon**：轮询 `raw_frames/*.ready`，读对应 wav，做信道+噪声，写 `session/channel_frames/NNNN.wav` + `NNNN.ready`
- **RX 进程**：轮询 `channel_frames/*.ready`，读对应 wav，检测+解码，写 `session/rx_out/NNNN.meta.json` 和 `session_text.log`

### 验收标准

- [ ] 三脚本可独立启动（`start_tx.m` / `start_channel.m` / `start_rx.m`）
- [ ] TX 边输入文本，RX 边输出解码结果（延迟 <10 秒）
- [ ] Channel daemon 可切换信道配置（静态/低 Doppler/高 Doppler）
- [ ] 三进程之一崩溃不影响其他两个（文件重连）
- [ ] 持续运行 10 分钟无 wav 文件锁冲突

### 依赖

- P4 完成（scheme 路由可用）

### 关键点

- **帧文件协议**：每帧写完 wav→close→touch `.ready`（原子序列），下游只读 `.ready` 存在的 wav（必然已 close）
- **监控方式**：`dir(session/raw_frames/*.ready)` 轮询（0.1–0.5s 间隔），按帧号递增顺序处理
- **无锁冲突**：方案 B 避开了 Windows 文件锁（每帧独立 wav 文件，写完才对下游可见）
- **进程握手**：启动时每进程写 `.pid` 文件，互相等待；会话目录用 `session_<timestamp>/` 隔离
- **信号丢失恢复**：RX 若 30s 无新 `.ready` 进入待机；重启后扫描 `channel_frames/*.ready` 跳过已处理的
- **会话汇总**：结束时可选运行 `session_wavconcat.m` 合并为单文件归档（raw_session.wav / channel_session.wav）
- **清理策略**：默认保留最近 N=100 帧，旧的移至 `session/archive/`

---

## Plan / Log / Result

（P4 完成后补）
