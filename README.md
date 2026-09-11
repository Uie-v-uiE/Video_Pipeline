# Zynq7020 以太网视频处理与 HDMI 双窗显示

基于 **RK-ZYNQ7020-F（XC7Z020-CLG484-2）** 的实时视频流水线：上位机经 **UDP** 推送 RGB565 图像，PS 侧收包写入 DDR，PL 侧完成 **五种图像处理** 与 **0–359° 任意角旋转**，并以 **左原图 / 右处理结果** 双窗输出 **HDMI 1024×600**。

开发环境：Vivado / Vitis **2025.2.1**。

---

## 功能一览

| 功能 | 说明 |
|------|------|
| 以太网视频 | PC → UDP:5001 → DDR → PL，源分辨率 512×300 RGB565 |
| HDMI 输出 | 1024×600@50 MHz，左右各 512 宽，垂直 2× 放大 |
| 图像处理 | 灰度、二值化、3×3 模糊、Sobel 边缘、反色（可组合） |
| 图像旋转 | 按键 KEY1/KEY2，角度 0–359° |
| 串口控制 | 115200，5 位效果字 + 源切换 / 阈值 / 本地测试图 |
| 仿真 | 单元测试 + Python 金标图 |

**说明：** 角度非 0 时，模糊与 Sobel 会自动旁路（窗口滤波在旋转坐标系下不成立）；灰度、二值、反色仍有效。详见 `docs/KNOWLEDGE.md`。

---

## 目录结构

```
rtl/            PL 源码（顶层、视频、效果、旋转、AXI、HDMI）
constraints/    管脚与时序约束
tcl/            工程创建与实现脚本
sim/            仿真顶层与用例
sw/ps/          裸机程序（与 Vitis 工程源码保持同步）
sw/host/        上位机 UDP 发送与一键脚本
scripts/        金标模型、sin/cos ROM 生成
docs/           架构、知识点、上板与赛事材料
output/         比特流与报告输出目录
```

---

## 快速上板

### 1. 比特流

已生成的 `output/system.bit` 可直接下载；或：

```bat
cd /d <仓库根目录>
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
%VIVADO% -mode batch -source tcl\build_system_axigpio.tcl
%VIVADO% -mode batch -source tcl\program_system.tcl
```

### 2. PS 应用

用 Vitis 打开 `vitis_udp` 工作区，Build Platform（需含 **lwip220**）后 Build `app_component`，下载 ELF。

串口 115200，应看到 `[BOOT]`、`[NET] ip=192.168.1.10`。

### 3. 网络与推流

- 板卡：`192.168.1.10/24`，网线接 **PS ETH**  
- PC 网卡：`192.168.1.100/24`  

```bat
sw\host\run_sender.bat
:: 或指定视频文件（需带 H.264 解码的完整 FFmpeg）
sw\host\run_video.bat D:\path\to\video.mp4
```

上位机默认绑定源地址 `192.168.1.100`，避免双网卡路由错误。

---

## 串口命令

| 命令 | 作用 |
|------|------|
| `00111` | 打开模糊+边缘+反色（左起为 bit0：灰/二值/模糊/边缘/反色） |
| `00000` | 关闭全部效果 |
| `SRC0` / `SRC1` | 彩条 / DDR 视频 |
| `TH80` | 二值化阈值 |
| `FILL` | DDR 本地渐变测试 |
| `STAT` | 查看帧计数与网口状态 |

第三方串口助手请设 **115200 8N1、无流控、发送加 CR+LF**。Vitis 终端默认带换行，故可直接用。

---

## 网络参数

| 项 | 值 |
|----|-----|
| 板卡 IP | 192.168.1.10 |
| UDP 端口 | 5001 |
| MAC | 00:0A:35:00:01:02 |
| 帧格式 | RGB565 小端，512×300，一帧 307200 字节 |
| AXI GPIO | 0x41200000 |

---

## 文档索引

| 文档 | 内容 |
|------|------|
| `docs/ARCHITECTURE.md` | 数据通路与 PL 框图 |
| `docs/KNOWLEDGE.md` | 学习要点与常见坑 |
| `docs/ETH_BRINGUP.md` | 以太网调试 |
| `docs/SYSTEM_BRINGUP.md` | 系统工程上板 |
| `docs/COMPETITION.md` | 赛事材料清单 |
| `docs/TIMING_REPORT.md` | 时序分析（需自行导出填写） |

---

## 仿真

```bat
%VIVADO% -mode batch -source sim\run_sim.tcl
python scripts\golden_model.py
```

---

## 许可与说明

本仓库面向教学与 FPGA 创新竞赛使用。第三方 IP（lwIP、板级原理）遵循其原许可。使用前请根据实际原理图核对管脚与 PHY 型号。
