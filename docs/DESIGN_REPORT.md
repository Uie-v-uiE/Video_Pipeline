# 设计报告素材 · 2026 架构变更

## 1. 变更摘要

| 任务 | 变更 |
|------|------|
| UDP 数据面 | PS lwIP → **PL RGMII PHY2 全硬件收包重组**，PS 控制面 |
| 旋转×窗滤 | 去掉 angle≠0 旁路，改为 **目标域 3×3** |
| OSD | 左上角叠加 FPS/ANG/EN/NET/RUN，不改双窗布局 |
| 分辨率 | 维持 **512×300** |
| 协议 | 上位机 offset 格式不变；**网线改插 PL 口** |

## 2. 新增/修改 RTL

```
rtl/eth/rgmii_rx.v
rtl/eth/gmii_rx_mac.v
rtl/eth/udp_rx_parser.v
rtl/eth/frame_reasm.v
rtl/eth/axi_frame_saver.v
rtl/eth/dc_fifo.v
rtl/eth/eth_udp_video_top.v
rtl/process/proc_pipeline.v      # 去 rotate bypass
rtl/video/osd_overlay.v         # 多行状态
rtl/top/pl_video_top.v          # eth 写 + OSD
rtl/top/system_top.v            # RGMII 端口 + eth 例化
constraints/rk_zynq7020.xdc     # PHY2 管脚
sw/ps/main.c                    # 控制面
```

## 3. 优化前后对比

见 `docs/PERF_REPORT.md`。

## 4. 验证

- 仿真：`sim/run_sim.tcl`（含 `tb_udp_parser` / `tb_udp_reasm` / `tb_rotate_window`）
- 上板：PL 网口推流；串口 `00111`；HDMI OSD；KEY 旋转+窗滤

## 5. 复现

```bat
cd /d <repo>
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
%VIVADO% -mode batch -source tcl\build_system_axigpio.tcl
%VIVADO% -mode batch -source sim\run_sim.tcl
```

Vitis：Platform 仍可用 ENET0，但应用**不再依赖 lwIP 收视频**；UART 控制即可。
