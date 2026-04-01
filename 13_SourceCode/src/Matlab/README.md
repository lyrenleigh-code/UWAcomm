# 模块13 端到端仿真 (SourceCode)

## 目录结构

```
13_SourceCode/src/Matlab/
├── common/                      公共函数
│   ├── gen_uwa_channel.m        简化水声信道（多径+Jakes+多普勒+AWGN）
│   ├── sys_params.m             6体制统一参数配置
│   ├── tx_chain.m               通用发射链路
│   ├── rx_chain.m               通用接收链路
│   └── main_sim_single.m        单SNR点6体制仿真
│
├── tests/                       逐体制独立测试
│   ├── SC-FDE/
│   │   └── test_scfde_e2e.m     SC-FDE完整framework_v5链路测试
│   ├── OFDM/                    待开发
│   ├── SC-TDE/                  待开发
│   ├── OTFS/                    待开发
│   ├── DSSS/                    待开发
│   └── FH-MFSK/                 待开发
│
└── README.md
```

## 信号流（对齐framework_v5）

```
TX: 信息比特 → 02编码 → 03交织 → 04调制 → [06加CP] → 09RRC成形 → 09上变频 → 通带实信号(DAC)
信道: 基带复数 → gen_uwa_channel(多径时变+多普勒+AWGN)
RX: 09下变频 → 10-1粗多普勒(估计+重采样) → 09RRC匹配+下采样
    → [06去CP+FFT] → 10-2残余CFO → 07均衡 → [12 Turbo迭代] → 03解交织 → 02译码
```

## 运行方式

```matlab
% 6体制静态信道快速测试
cd('13_SourceCode/src/Matlab/common');
run('main_sim_single.m');

% SC-FDE完整时变信道测试
cd('13_SourceCode/src/Matlab/tests/SC-FDE');
run('test_scfde_e2e.m');
```
