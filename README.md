# Zynq7020 以太网视频处理与 HDMI 双窗显示

上位机经 **UDP** 推送 RGB565 视频；**PL 侧硬件完成** RGMII 收包、ARP/ICMP/UDP 协议、帧重组、图像处理与 HDMI 输出；**PS 仅做控制面**（串口命令、效果使能）。

| 项 | 值 |
|----|-----|
| 板卡 | RK-ZYNQ7020-F（XC7Z020-CLG484-2） |
| 工具 | Vivado / Vitis **2025.2.1** |
| 源分辨率 | **512×300 RGB565**（维持原分辨率） |
| 显示 | HDMI **1024×600 @ 50 MHz**，左原图 / 右处理，垂直 2× |
| 网络 | 板卡 **PL 网口** `192.168.1.10:5001`，PC `192.168.1.100` |
| 控制 | AXI GPIO @ `0x41200000`，UART 115200 |
| 许可 | MIT |

---

## 目录结构

```
zynq_video_pipeline/
├── README.md                 本文件
├── .gitignore
├── LICENSE
├── rtl/                      PL 源码
│   ├── top/                  system_top, pl_video_top
│   ├── eth/                  PL 以太网协议栈（RGMII/ARP/ICMP/UDP）
│   ├── video/                时序、彩条、分屏、帧缓、OSD
│   ├── process/              五效果流水线 + rotate/
│   ├── axi/                  axi_frame_writer（HP0 读 DDR）
│   ├── hdmi/                 TMDS 编码串化
│   ├── clocks/               MMCM（50/250/200 MHz）
│   └── util/                 按键消抖
├── constraints/              rk_zynq7020.xdc（含 PL ETH PHY2）
├── tcl/                      Vivado 一键脚本
├── sim/                      单元/集成仿真
├── scripts/                  金标模型、sin/cos ROM
├── sw/
│   ├── ps/                   PS 控制面（串口 + AXI GPIO）
│   └── host/                 上位机 UDP 推流
├── skill/                    可复用技能包
├── docs/                     设计文档（见下）
├── output/                   system.bit / system.xsa / 时序报告
└── sim_out/                  金标图输出
```

**本机工程位置（不入库）：**

| 工程 | 路径 |
|------|------|
| Vivado 工程 | `D:\Xilinx\Prj\video_pl\zynq_video_pipeline\vivado_system\zynq_video_sys.xpr` |
| Vitis 工作区 | `D:\Xilinx\Prj\video_pl\zynq_video_pipeline\vitis_udp\`（或 `vitis_prj\`） |
| 仓库根 | `D:\Xilinx\Prj\video_pl\zynq_video_pipeline\` |

---

## 快速开始

### 1. 生成比特流

```bat
cd /d D:\Xilinx\Prj\video_pl\zynq_video_pipeline
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
%VIVADO% -mode batch -source tcl\build_system_axigpio.tcl
```

产物：`output/system.bit`、`output/system.xsa`

### 2. 下载比特流

```bat
%VIVADO% -mode batch -source tcl\program_system.tcl
```

### 3. Vitis 下载 PS ELF（串口命令需要）

1. 用 Vitis 打开工作区，Platform 使用最新 `output/system.xsa`
2. 应用源码：`sw/ps/main.c`
3. Build → Run

### 4. 推流

```bat
:: PC 网卡 192.168.1.100/24，网线接 PL 网口
sw\host\run_sender.bat
:: 或真实视频
sw\host\run_video.bat D:\path\to\video.mp4
```

---

## 串口命令（115200 8N1，发送加 CR+LF）

| 命令 | 作用 |
|------|------|
| `00000` | 关闭全部效果 |
| `10000` | 灰度 |
| `01000` | 二值化 |
| `00111` | 模糊+Sobel+反色 |
| `SRC0` / `SRC1` | 彩条 / DDR 视频 |
| `TH80` | 二值化阈值 |
| `FILL` | 诊断色块 |
| `STAT` | 状态 |

效果位顺序：**gray / binary / blur / sobel invert**（左起 bit0）

**注意：** 下载 bit 后 PS 会复位，必须再 Vitis Run 一次 ELF，串口才有效。  
ETH 有包时会**自动切到视频画面**，不依赖 `SRC1`。

---

## 文档索引

| 文档 | 内容 |
|------|------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 数据通路、时钟、带宽、模块框图 |
| [docs/MODULES.md](docs/MODULES.md) | 各模块详解 |
| [docs/ISSUES.md](docs/ISSUES.md) | 问题与修复记录 |
| [docs/PS_VS_PL.md](docs/PS_VS_PL.md) | PS 软件 vs PL 硬件方案对比 |
| [docs/ETH_BRINGUP.md](docs/ETH_BRINGUP.md) | 以太网上板 |
| [docs/ROTATION_AND_EFFECTS.md](docs/ROTATION_AND_EFFECTS.md) | 旋转与效果（目标域重构） |
| [docs/PERF_REPORT.md](docs/PERF_REPORT.md) | 性能对比 |
| [docs/COMPETITION.md](docs/COMPETITION.md) | 竞赛提交清单 |
| [docs/BOARD_PINS.md](docs/BOARD_PINS.md) | 管脚 |
| [skill/README.md](skill/README.md) | 技能包 |

---

## 关键设计摘要

- **PL 网口硬件协议栈**：RGMII → ARP/ICMP/UDP → offset 拼帧 → BRAM/DDR  
- **PS 只做控制**：UART → AXI GPIO → 效果使能  
- **目标域窗滤**：任意旋转角下 blur/sobel 可用（不再旁路）  
- **OSD**：左上角三行状态（FPS/ANG/EN）  
- **协议兼容**：上位机 `[u32 LE offset][payload]` 无需修改  

详见 `docs/ARCHITECTURE.md` 与 `docs/ISSUES.md`。
