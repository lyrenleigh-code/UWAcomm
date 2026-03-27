# 多载波/多域变换模块 (MultiCarrier)

水声通信系统多载波调制算法库，覆盖OFDM(CP/ZP)、SC-FDE分块CP、OTFS(DFT/Zak两种实现)，含PAPR计算/抑制和可视化工具。

## 文件清单

| 文件 | 功能 | 类别 |
|------|------|------|
| `ofdm_modulate.m` | OFDM调制（IFFT + CP/ZP插入） | OFDM |
| `ofdm_demodulate.m` | OFDM解调（去CP/ZP + FFT） | OFDM |
| `ofdm_pilot_insert.m` | 频域导频插入（梳状/块状/自定义） | OFDM |
| `ofdm_pilot_extract.m` | 频域导频提取 | OFDM |
| `scfde_add_cp.m` | SC-FDE分块CP插入 | SC-FDE |
| `scfde_remove_cp.m` | SC-FDE去CP + 分块FFT | SC-FDE |
| `otfs_modulate.m` | OTFS调制（ISFFT+Heisenberg，DFT/Zak两种） | OTFS |
| `otfs_demodulate.m` | OTFS解调（Wigner+SFFT） | OTFS |
| `otfs_pilot_embed.m` | DD域嵌入导频+保护区 | OTFS |
| `otfs_get_data_indices.m` | DD域数据格点索引提取 | OTFS |
| `papr_calculate.m` | PAPR计算 | PAPR |
| `papr_clip.m` | PAPR抑制（硬限幅/限幅滤波/幅度缩放） | PAPR |
| `plot_ofdm_spectrum.m` | OFDM频谱+时域+PAPR CCDF可视化 | 可视化 |
| `plot_otfs_dd_grid.m` | OTFS DD域格点幅度/相位热图 | 可视化 |
| `test_multicarrier.m` | 单元测试（14项） | 测试 |

## 三种多载波方案对比

| 方案 | 域变换 | CP类型 | 导频方式 | 适用场景 |
|------|--------|--------|----------|----------|
| CP-OFDM | IFFT/FFT | 每符号CP | 频域梳状/块状 | 宽带高速率 |
| ZP-OFDM | IFFT/FFT+OLA | 每符号ZP | 同CP-OFDM | 频选衰落信道 |
| SC-FDE | 分块FFT/IFFT | 每块CP | 时域前导码 | 低PAPR，长延时 |
| OTFS-DFT | ISFFT+Heisenberg | 整帧CP | DD域嵌入脉冲 | 快时变高移动 |
| OTFS-Zak | 2D-IFFT(等价) | 整帧CP | 同DFT方法 | 同上，另一种实现 |

## 运行测试

```matlab
cd('D:\TechReq\UWAcomm\MultiCarrier\src\Matlab');
run('test_multicarrier.m');
```

### 测试用例说明

**1. OFDM（3项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 1.1 CP-OFDM回环 | 误差<1e-10 | 10个OFDM符号IFFT+CP→去CP+FFT完全还原 |
| 1.2 ZP-OFDM回环 | 误差<1e-10 | ZP模式+overlap-add解调完全还原 |
| 1.3 导频插入/提取 | 导频值和数据值均一致 | comb_4导频模式回环 |

**2. SC-FDE（1项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 2.1 SC-FDE CP回环 | 时域块和FFT块均与原始一致 | 分块CP插入→去CP→FFT验证 |

**3. OTFS（4项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 3.1 DFT方法回环 | 误差<1e-8 | ISFFT+Heisenberg→Wigner+SFFT |
| 3.2 Zak方法回环 | 误差<1e-8 | 2D-IFFT→2D-FFT |
| 3.3 DFT/Zak一致性 | 两种方法输出差异<1e-8 | 验证两种实现数学等价 |
| 3.4 DD域导频嵌入 | 导频值/数据值/保护区均正确 | 单脉冲导频+保护区+数据格点 |

**4. PAPR（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 4.1 PAPR计算 | 恒模≈0dB，OFDM>3dB | 不同信号的PAPR差异验证 |
| 4.2 PAPR削峰 | 削峰后PAPR≤目标+余量 | 硬限幅有效降低PAPR |

**5. 可视化（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 5.1 OFDM频谱 | 绘图无报错 | 时域/功率/PSD/CCDF四格图 |
| 5.2 OTFS DD域 | 绘图无报错 | 幅度/相位热图+导频标注 |

**6. 异常输入（1项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 6.1 空输入 | 9个函数均报错 | 覆盖全部核心函数 |
