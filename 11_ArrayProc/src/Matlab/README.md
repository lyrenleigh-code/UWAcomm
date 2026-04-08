# 阵列接收预处理模块 (ArrayProc)

可选的接收链路前端预处理模块，对多通道阵列信号进行波束形成或非均匀变采样重建，输出单路高质量信号供下游模块透明使用。

## 对外接口

其他模块/端到端应调用的函数：

### `gen_array_config`

阵列配置生成（ULA/UCA/自定义）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `array_type` | string | 阵列类型: `'ula'`(均匀线阵)/`'uca'`(均匀圆阵)/`'custom'`(任意阵型) | `'ula'` |
| `M` | integer | 阵元数 | 8 |
| `d` | scalar (m) | 阵元间距(ULA)或半径(UCA) | lambda/2 |
| `fc` | scalar (Hz) | 载频（用于计算波长） | 12000 |
| `varargin` | Mx3 matrix | 自定义阵型时的坐标矩阵（每行[x,y,z]） | (仅custom) |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `config` | struct | `.type`, `.M`, `.positions`(Mx3坐标), `.d`, `.fc`, `.lambda`, `.c`(=1500) |

---

### `gen_doppler_channel_array`

多通道阵列信道仿真（每个阵元独立经历信道+精确空间时延）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `s` | 1xN complex | 发射基带信号 | (必需) |
| `fs` | scalar (Hz) | 采样率 | (必需) |
| `alpha_base` | scalar | 基础多普勒因子 | (必需) |
| `paths` | struct | 多径参数（同gen_doppler_channel） | (必需) |
| `snr_db` | scalar (dB) | 信噪比 | (必需) |
| `array_config` | struct | 阵列配置（由gen_array_config生成） | (必需) |
| `theta` | scalar (rad) | 信号入射角（相对阵列法线） | 0 |
| `time_varying` | struct | 时变参数（同gen_doppler_channel） | enable=false |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `R_array` | MxN_rx complex | 多通道接收信号（每行一个阵元） |
| `channel_info` | struct | `.tau_array`(1xM秒各阵元空间时延), `.alpha_true`, 及单通道信息 |

---

### `bf_das`

DAS（Delay-And-Sum）常规波束形成（时延对齐+相干叠加）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `R_array` | MxN complex | 多通道接收信号 | (必需) |
| `tau_delays` | 1xM (s) | 各阵元时延补偿量 | zeros(1,M) |
| `fs` | scalar (Hz) | 采样率 | 48000 |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `output` | 1xN complex | 波束形成后的单路信号 |
| `snr_gain` | scalar (dB) | SNR提升（理论值 = 10*log10(M)） |

---

### `bf_mvdr`

MVDR/Capon自适应波束形成（最小方差无失真响应）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `R_array` | MxN complex | 多通道接收信号 | (必需) |
| `steering_vector` | Mx1 complex | 期望方向导向矢量 | ones(M,1)/sqrt(M) |
| `diag_loading` | scalar | 对角加载量（提高数值稳定性） | 0.01 |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `output` | 1xN complex | 波束形成后的单路信号 |
| `weights` | Mx1 complex | MVDR权重向量 |

---

### `bf_delay_calibration`

阵元时延标定（互相关法）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `R_array` | MxN complex | 多通道接收信号 | (必需) |
| `preamble` | 1xL complex | 已知前导码 | (必需) |
| `fs` | scalar (Hz) | 采样率 | (必需) |
| `tau_true` | 1xM (s) | 真实时延（可选，用于计算误差） | [] |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `tau_est` | 1xM (s) | 估计的各阵元时延（第1阵元=0） |
| `tau_error` | 1xM (s) | 标定误差（需提供tau_true） |

---

### `bf_nonuniform_resample`

空时联合非均匀变采样重建（等效采样率提升至M*fs）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `R_array` | MxN complex | 多通道接收信号 | (必需) |
| `tau_delays` | 1xM (s) | 各阵元时延（精确值） | (必需) |
| `fs` | scalar (Hz) | 原始采样率 | (必需) |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `output` | 1x(M*N) complex | 重建后的高采样率信号 |
| `effective_fs` | scalar (Hz) | 等效采样率（约M*fs） |

## 内部函数

辅助/测试函数（不建议外部直接调用）：

### `plot_beampattern` (internal)

波束方向图可视化（直角坐标+极坐标）。

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `array_config` | struct | 阵列配置（由gen_array_config生成） | (必需) |
| `weights` | Mx1 complex | 波束形成权重 | ones(M,1)/sqrt(M)（等权DAS） |
| `title_str` | string | 标题 | `'Beam Pattern'` |

### `test_array_proc` (internal)

单元测试脚本（V1.0, 11项）。

## 核心算法技术描述

### 1. DAS波束形成（bf_das）

**原理：** 对各阵元信号做时延对齐后相干求和。

$$y_{\text{DAS}}(n) = \frac{1}{M} \sum_{m=1}^{M} R_m(n - \tau_m \cdot f_s)$$

时延补偿分为整数样本（循环移位）和分数样本（线性插值）两步。

- **SNR增益：** 理论值 `G = 10·log10(M)` dB（如4元=6dB）
- **适用条件：** 适合信号方向已知、干扰较少的场景
- **局限性：** 等权叠加无法抑制方向性干扰

### 2. MVDR/Capon自适应波束形成（bf_mvdr）

**原理：** 在保持期望方向增益不变的约束下最小化输出功率。

$$\mathbf{w}_{\text{MVDR}} = \frac{R^{-1} \mathbf{a}}{\mathbf{a}^H R^{-1} \mathbf{a}}$$

其中R为协方差矩阵，a为导向矢量。对角加载 `R + σ²I` 提高求逆稳定性。

- **导向矢量构建：** `a_m = exp(-j·2π·fc·τ_m)`，其中 `τ_m = pos_m · look_dir / c`
- **适用条件：** 需要足够快拍数估计协方差（N >> M）；适合抑制方向性干扰
- **局限性：** 低快拍数时协方差估计不准，对角加载为必要措施；运动平台指向误差导致信号自消

### 3. 阵元时延标定（bf_delay_calibration）

**原理：** 以第1阵元为参考，各阵元与已知前导码互相关，峰位置差即为时延差。

$$\tau_m = \frac{\text{peak}_m - \text{peak}_{\text{ref}}}{f_s}$$

- **适用条件：** 需要已知前导码
- **局限性：** 精度受限于采样率（未做亚样本精化）

### 4. 非均匀变采样重建（bf_nonuniform_resample）

**原理：** M个阵元在不同时刻采样（因空间时延），组合后等效为M倍过采样。

$$f_{s,\text{eff}} \approx M \cdot f_s$$

将所有阵元的采样点按时间排序，用三次插值重建到均匀高速率网格。

- **要求：** 各阵元时延精确已知（标定精度 < Ts/(2M)）
- **增益：** CRLB降低M^2倍（多普勒估计精度提升）
- **局限性：** 要求时延精确标定；重建后信号长度为M*N

### 5. 阵列信道仿真（gen_doppler_channel_array）

**原理：** 计算远场平面波假设下各阵元的空间时延，叠加到多径时延后逐阵元调用gen_doppler_channel。

$$\tau_m = -\frac{\mathbf{pos}_m \cdot \mathbf{look\_dir}}{c}$$

look_dir为入射方向单位向量 `[sin(θ), cos(θ), 0]`，归一化后第1阵元时延为0。

## 使用示例

```matlab
% 配置8元ULA + 仿真多通道信道
cfg = gen_array_config('ula', 8, [], 12000);
[R, info] = gen_doppler_channel_array(s, fs, alpha, paths, snr, cfg, theta);

% 模式B: DAS波束形成（SNR增益约10*log10(M) dB）
[y_das, gain] = bf_das(R, info.tau_array, fs);

% 模式B: MVDR自适应波束形成（干扰抑制）
a = exp(-1j*2*pi*fc*cfg.positions*look_dir.'/cfg.c);
[y_mvdr, w] = bf_mvdr(R, a, 0.01);

% 模式A: 非均匀变采样重建（等效采样率提升至M*fs）
[y_hi, eff_fs] = bf_nonuniform_resample(R, info.tau_array, fs);
```

## 依赖关系

- 依赖模块10 (DopplerProc) 的 `gen_doppler_channel`（gen_doppler_channel_array内部扩展为多通道）
- 依赖模块10 (DopplerProc) 的 `doppler_coarse_compensate`（联合测试中对比DAS增强后的多普勒估计精度）
- 依赖模块10 (DopplerProc) 的 `est_doppler_caf`（联合测试中使用）
- 依赖模块08 (Sync) 的 `gen_lfm`（测试中用于生成LFM前导码）

## 测试覆盖 (test_array_proc.m V1.0, 11项)

| 编号 | 测试名称 | 断言条件 | 说明 |
|------|---------|---------|------|
| 1.1 | ULA配置(8元) | `cfg_ula.M == 8`, `size(cfg_ula.positions,1) == 8`, `abs(cfg_ula.d - cfg_ula.lambda/2) < 1e-6` | 阵元数、坐标行数、默认半波长间距 |
| 1.2 | UCA配置(6元) | `cfg_uca.M == 6` | 圆阵阵元数正确 |
| 2.1 | 阵列信道生成 | `size(R_array,1) == 4`, `size(R_array,2) > length(s_test)`, `length(ch_info.tau_array) == 4`, `ch_info.tau_array(1) == 0` | 4通道，含多径扩展，时延正确 |
| 3.1 | DAS波束形成 | `~isempty(y_das)`, `length(y_das) == size(R_array,2)` | 输出非空，长度一致 |
| 3.2 | MVDR波束形成 | `~isempty(y_mvdr)`, `length(w_mvdr) == cfg.M` | 输出非空，权重长度=M |
| 3.3 | 时延标定 | `length(tau_est) == cfg.M` | 估计时延数=M |
| 3.4 | 波束方向图可视化 | 不抛异常（DAS和MVDR各一次） | 生成方向图figure |
| 4.1 | 非均匀重建采样率提升 | `eff_fs > fs`, `length(y_hi) > size(R_array,2)` | 等效采样率提高，信号更长 |
| 5.1 | DAS增强多普勒估计精度 | 不抛异常，输出单通道和DAS后误差对比 | 验证DAS后多普勒估计改善 |
| 6.1 | 空输入拒绝 | `caught == 4`（4个函数均报错） | gen_array_config('unknown')/bf_das/bf_mvdr/bf_delay_calibration |

## 可视化说明

测试生成的figure：

- **DAS波束方向图：** 直角坐标+极坐标显示DAS等权波束方向图，展示主瓣宽度和旁瓣电平
- **MVDR波束方向图：** 直角坐标+极坐标显示MVDR自适应波束方向图，展示干扰方向零陷
