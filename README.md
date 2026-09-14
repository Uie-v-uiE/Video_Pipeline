# Zynq7020 以太网视频处理流水线

上位机经 **UDP** 推送 RGB565 视频；**PL 硬件**完成 RGMII 收包、ARP/ICMP/UDP 协议、帧重组、图像处理与 HDMI 双窗输出；**PS 仅做控制面**（串口命令、效果使能）。

| 项 | 值 |
|----|-----|
| 板卡 | RK-ZYNQ7020-F（XC7Z020-CLG484-2） |
| 工具 | Vivado / Vitis **2025.2.1** |
| 源分辨率 | **512×300 RGB565** |
| 显示 | HDMI **1024×600 @ 50 MHz**，左原图 / 右处理，垂直 2× |
| 网络 | 板卡 **PL 网口** `192.168.1.10:5001`，PC `192.168.1.100` |
| 控制 | AXI GPIO @ `0x41200000`，UART 115200 |
| 协议 | MIT |

---

## 目录结构

按竞赛推荐结构组织（目录与文件名均为英文）：

```
<project_name>/
├── README.md
├── src/                      设计源码
│   ├── rtl/                  Verilog（top / eth / video / process / axi / hdmi）
│   ├── ps/                   裸机控制（UART + GPIO）
│   ├── host/                 上位机 UDP 推流
│   └── constraints/          管脚与时序约束
├── sim/                      仿真脚本与测试台
├── build/                    构建脚本、报告、bit / xsa
│   ├── tcl/
│   ├── scripts/
│   ├── reports/
│   ├── system.bit
│   └── system.xsa
├── board/                    上板说明
├── data/golden/              金标参考图
├── skill/                    可复用技能包
└── report/                   设计文档与问题记录
```

---

## 快速开始

### 1. 生成比特流与 XSA

```bat
cd /d <仓库根目录>
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
%VIVADO% -mode batch -source build\tcl\build_system_axigpio.tcl
```

产物：`build/system.bit`、`build/system.xsa`

### 2. 下载比特流

```bat
%VIVADO% -mode batch -source build\tcl\program_system.tcl
```

### 3. 下载 PS ELF（串口命令需要）

1. 用 Vitis 打开工作区，Platform 使用最新 `build/system.xsa`
2. 应用源码：`src/ps/main.c`
3. Build → Run

> 下载 bit 后 PS 会复位，必须再 Run 一次 ELF，串口才有效。

### 4. 推流

```bat
:: PC 网卡 192.168.1.100/24，网线接板卡 PL 网口
src\host\run_sender.bat
:: 或真实视频
src\host\run_video.bat D:\path\to\video.mp4
```

---

## 串口命令（115200 8N1，发送加 CR+LF）

| 命令 | 作用 |
|------|------|
| `00000` | 关闭全部效果 |
| `10000` | 灰度 |
| `01000` | 二值化 |
| `00111` | 模糊 + Sobel + 反色 |
| `SRC0` / `SRC1` | 彩条 / DDR 视频 |
| `TH80` | 二值化阈值 |
| `FILL` | 诊断色块 |
| `STAT` | 状态 |

效果位顺序：**gray / binary / blur / sobel / invert**（左起 bit0）

ETH 收到包后会**自动切到视频画面**，不依赖 `SRC1`。

---

## UDP 协议（上位机 ↔ 板卡）

```
[u32 小端 byte_offset][RGB565 载荷]
```

- 一帧：512×300×2 = 307200 字节
- 每包载荷 ≤ 1396 字节
- 板端按 offset 写入帧缓，乱序可拼对
- 坏帧丢弃、不重传，下一帧自动恢复

---

## 文档索引

| 文件 | 内容 |
|------|------|
| [report/ARCHITECTURE.md](report/ARCHITECTURE.md) | 数据通路、时钟、带宽 |
| [report/MODULES.md](report/MODULES.md) | 各模块详解 |
| [report/ISSUES.md](report/ISSUES.md) | 问题定位与修复 |
| [report/PS_VS_PL.md](report/PS_VS_PL.md) | PS/PL 划分、旋转窗滤方案对比 |
| [report/ETH_BRINGUP.md](report/ETH_BRINGUP.md) | 以太网上板 |
| [report/ROTATION_AND_EFFECTS.md](report/ROTATION_AND_EFFECTS.md) | 目标域窗口滤波 |
| [report/PERF_REPORT.md](report/PERF_REPORT.md) | 性能对比 |
| [report/COMPETITION.md](report/COMPETITION.md) | 竞赛提交清单 |
| [skill/README.md](skill/README.md) | 技能包 |

---

## 关键设计摘要

- **PL 硬件协议栈**：RGMII → ARP/ICMP/UDP → offset 拼帧 → 帧缓  
- **PS 只做控制**：UART → AXI GPIO → 效果使能  
- **目标域窗滤**：任意旋转角下 blur/sobel 可用（不再旁路）  
- **OSD**：左上角三行状态（FPS / ANG / EN）  
- **上位机协议不变**；网线需接 **PL 网口**
