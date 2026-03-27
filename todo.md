# UWAcomm 水声通信算法开发进度（v3.0框架）

> 框架参考：`framework/framework_v3.html`
> 规范参考：`DopplerProc/UWA_Doppler_MATLAB_Spec.md`
> 覆盖6种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强

## 已完成模块

### 模块1. SourceCoding — 信源编解码 (5个函数, 14项测试)
### 模块2. ChannelCoding — 信道编解码 (10个函数, 22项测试)
### 模块3. Interleaving — 交织/解交织 (7个函数, 19项测试)
### 模块4. Modulation — 符号映射/判决 (6个函数, 25项测试)
### 模块5. SpreadSpectrum — 扩频/解扩 (15个函数, 19项测试)
### 模块8. Sync — 同步+帧组装 (16个函数, 16项测试)
### 模块9. Waveform — 脉冲成形/上下变频 (8个函数, 20项测试)

## 待开发模块

### 阶段一（续）：多载波支持 + 信道估计均衡

#### 模块6. MultiCarrier — 多载波/多域变换 + CP
- [ ] **OFDM**
  - [ ] ofdm_modulate.m — IFFT + CP插入
  - [ ] ofdm_demodulate.m — 去CP + FFT
  - [ ] ofdm_pilot_insert.m — 频域梳状/块状导频插入
  - [ ] ofdm_pilot_extract.m — 导频提取
- [ ] **SC-FDE**
  - [ ] scfde_add_cp.m — 分块CP/ZP插入
  - [ ] scfde_remove_cp.m — 去CP + 分块FFT
- [ ] **OTFS**
  - [ ] otfs_modulate.m — ISFFT + Heisenberg变换 + 整帧CP
  - [ ] otfs_demodulate.m — 去整帧CP + Wigner变换 + SFFT
  - [ ] otfs_pilot_embed.m — DD域嵌入单脉冲导频+保护区
  - [ ] otfs_get_data_indices.m — DD域数据格点索引提取
- [ ] 测试 + README

#### 模块7. ChannelEstEq — 信道估计与均衡
- [ ] **信道估计算法（共用）**
  - [ ] ch_est_ls.m — LS最小二乘估计
  - [ ] ch_est_omp.m — OMP正交匹配追踪（稀疏信道）
  - [ ] ch_est_sbl.m — 稀疏贝叶斯学习（SBL）
  - [ ] ch_est_vamp.m — VAMP变分近似消息传递
  - [ ] ch_est_turbo_vamp.m — Turbo-VAMP（支持热启动WS-Turbo-VAMP）
- [ ] **SC-TDE均衡**
  - [ ] eq_dfe.m — 判决反馈均衡器（前馈+反馈+PLL）
  - [ ] eq_lms.m — LMS自适应均衡
  - [ ] eq_rls.m — RLS自适应均衡
- [ ] **SC-FDE均衡**
  - [ ] eq_mmse_fde.m — MMSE频域均衡（H→MMSE权→IFFT）
  - [ ] turbo_equalizer.m — Turbo迭代软均衡（SISO-MMSE ⇌ BCJR）
- [ ] **OFDM均衡**
  - [ ] eq_ofdm_fde.m — 频域单抽头MMSE/ZF均衡
  - [ ] comp_ici_matrix.m — ICI矩阵补偿（高速场景）
- [ ] **OTFS均衡**
  - [ ] ch_est_otfs.m — DD域嵌入导频稀疏路径估计 {h_i, l_i, k_i}
  - [ ] mp_detector.m — 消息传递检测器（高斯近似BP, 10~30次迭代）
- [ ] 测试 + README

### 阶段二：多普勒处理

#### 模块10. DopplerProc — 多普勒估计与补偿（10-1粗 + 10-2残余）
> 参考：`DopplerProc/UWA_Doppler_MATLAB_Spec.md` 完整规范
- [ ] **10-1 粗多普勒估计（6'之前）**
  - [ ] est_doppler_caf.m — 二维CAF搜索法（通用，高精度，离线）
  - [ ] est_doppler_cp.m — CP自相关法（OFDM专用，低开销）
  - [ ] est_doppler_xcorr.m — 复自相关幅相联合法（SC-FDE推荐，前后导码）
  - [ ] est_doppler_zoomfft.m — Zoom-FFT频谱细化法
- [ ] **10-1 粗多普勒补偿**
  - [ ] comp_resample.m — 宽带重采样补偿（三次样条/Farrow滤波器）
- [ ] **10-2 残余多普勒补偿（7'之后）**
  - [ ] comp_cfo.m — 残余CFO相位旋转校正
  - [ ] comp_ici_matrix.m — ICI矩阵补偿（OFDM高速场景）
- [ ] 测试 + README

### 阶段三：阵列接收

#### 模块11. ArrayProc — 阵列接收预处理
> 参考：Spec文档模块七
- [ ] gen_uwa_channel_array.m — 阵列信道仿真（M阵元，精确空间时延）
- [ ] bf_delay_calibration.m — 阵元时延标定
- [ ] bf_nonuniform_resample.m — 空时联合非均匀变采样重建（等效M·fs）
- [ ] bf_conventional.m — 常规DAS波束形成（时延对齐+相位补偿）
- [ ] est_doppler_beamforming.m — 基于波束域信号的高精度多普勒估计
- [ ] 测试 + README

### 阶段四：集成

#### 模块13. SourceCode — 端到端仿真
- [ ] **水声信道仿真器**
  - [ ] gen_uwa_channel.m — 单路信道（多径+宽带Doppler伸缩+AWGN）
  - [ ] gen_uwa_channel_array.m — 阵列信道
- [ ] **参数配置**
  - [ ] sys_params_ofdm.m / sys_params_scfde.m / sys_params_otfs.m
- [ ] **端到端链路**
  - [ ] main_sim.m — 统一仿真入口（体制切换）
  - [ ] tx_chain.m / rx_chain.m — 收发链路
- [ ] **性能评估**
  - [ ] BER/FER vs SNR曲线
  - [ ] 多普勒估计RMSE vs SNR
  - [ ] 信道估计NMSE收敛曲线
- [ ] 6种体制 + 阵列增强场景测试

## 补充：稀疏信道估计算法族（来自Turbo_VAMP_TVC.m）

以下算法可集成到模块7的信道估计部分：

| 算法 | 函数名 | 特点 |
|------|--------|------|
| ISTA | ch_est_ista.m | 基础稀疏估计，收敛慢 |
| AMP | ch_est_amp.m | 近似消息传递，快速但需高斯测量矩阵 |
| GAMP | ch_est_gamp.m | 广义AMP，支持非高斯 |
| VAMP | ch_est_vamp.m | 变分AMP，对测量矩阵条件更鲁棒 |
| Turbo-AMP | ch_est_turbo_amp.m | 结合稀疏先验的Turbo框架 |
| Turbo-VAMP | ch_est_turbo_vamp.m | VAMP+Turbo，当前最优 |
| **WS-Turbo-VAMP** | ch_est_ws_turbo_vamp.m | **热启动**：利用前帧后验概率修正先验LLR，慢时变信道加速收敛 |
| LAMP | ch_est_lamp.m | 学习型AMP，离线训练参数 |

WS-Turbo-VAMP创新点：
```
LLR_prior,i^(t) = log(λ/(1-λ)) + β · log(ρ_i^(t-1) / (1-ρ_i^(t-1)))
```
- β为时间相关系数（0~1），自适应估计
- 慢时变：β大，利用前帧信息加速收敛
- 快时变：β→0，退化为标准Turbo-VAMP

## 框架图演进

| 版本 | 文件 | 主要变更 |
|------|------|----------|
| v1.0 | `framework_diagram.html` | 10个成对模块，4种体制 |
| v2.0 | `framework/framework_v2.html` | 新增SC-FDE/OTFS体制，阵列/迭代模块 |
| **v3.0** | **`framework/framework_v3.html`** | 10拆分为10-1/10-2，6'调序，迭代回环(非独立模块)，配置卡只保留启用模块 |

## 其他待办

- [x] framework_v3.html 完成
- [x] 配置卡移除未使用模块，只展示启用模块
- [x] SC-TDE/SC-FDE/OTFS迭代回环U形箭头可视化
- [ ] CLAUDE.md 更新
- [ ] 跨模块路径管理统一方案（startup.m）
- [ ] 全模块集成测试

## 统计

| 指标 | 数值 |
|------|------|
| 已完成模块 | 9 / 11（迭代回环融入模块7） |
| 待开发模块 | 2 + IterativeProc + 集成 |
| 已完成 .m 文件 | 89 个 |
| 已完成测试项 | 151 项 |
| 总代码行数 | ~9500 行 |
| 总提交数 | 60 次 |

## 模块与文件夹对照

| 编号 | 模块名 | 文件夹 | 状态 |
|------|--------|--------|------|
| 1 | 信源编解码 | `SourceCoding/` | 已完成 |
| 2 | 信道编解码 | `ChannelCoding/` | 已完成 |
| 3 | 交织/解交织 | `Interleaving/` | 已完成 |
| 4 | 符号映射/判决 | `Modulation/` | 已完成 |
| 5 | 扩频/解扩 | `SpreadSpectrum/` | 已完成 |
| 6 | 多载波变换+CP | `MultiCarrier/` | **下一个** |
| 7 | 信道估计与均衡 | `ChannelEstEq/` | 已完成 |
| 8 | 同步+帧组装 | `Sync/` | 已完成 |
| 9 | 脉冲成形/变频 | `Waveform/` | 已完成 |
| 10 | 多普勒处理(10-1/10-2) | `DopplerProc/` | 待开发 |
| 11 | 阵列预处理 | `ArrayProc/` | 待开发 |
| ↻ | 迭代回环(7'⇌10-2⇌2') | 非独立模块 | 融入模块7 |
| 13 | 端到端仿真 | `SourceCode/` | 待开发 |
