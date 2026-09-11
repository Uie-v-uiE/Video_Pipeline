# DESIGN.md — Zynq7020 视频流水线

## 风格锚点
工程向：清晰模块边界、可分步上板、先 PL 后 PS。视觉上对齐典型 FPGA 竞赛/教学工程文档，不追求 UI 设计。

## 系统选择（已拍板）
| 项 | 选择 | 理由 |
|----|------|------|
| 视频输入 | 上位机 UDP → PS GEM → DDR | 板载 PS 千兆口，不依赖摄像头 |
| 分辨率 | 源 640x360 RGB565，HDMI 1280x720 | 带宽与 BRAM/逻辑平衡 |
| 显示 | 左原图 / 右处理，竖直 2x 放大 | 满足分屏需求 |
| 效果 | gray, binary, box_blur, sobel, invert | 5 级可串使能 |
| 使能 | PS UART 5 位串 `00111` | 用户指定 |
| 旋转 | PL KEY1/2，0/90/180/270 | 板载 2 键 |
| 无 PS 自测 | colorbar 源 | 明天可先验 HDMI |
| 器件 | xc7z020clg484-2 | 板卡手册 |

## 效果位定义
```
串口字符串:  c0 c1 c2 c3 c4
             │  │  │  │  └ invert
             │  │  │  └──── sobel
             │  │  └─────── box_blur
             │  └────────── binary
             └───────────── gray
en[c0]=bit0 ... en[c4]=bit4
"00111" → bit2..bit4 = blur+sobel+invert
```

## 数据通路图
见 `docs/ARCHITECTURE.md`。

## 管脚
见 `docs/BOARD_PINS.md` 与 `constraints/rk_zynq7020.xdc`。

## 上板策略
1. 先 `pl_demo_top` bitstream：验证 HDMI/按键/效果视觉差  
2. 再 `system_top` + PS elf：验证串口使能与 UDP 帧  
