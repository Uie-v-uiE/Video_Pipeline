# 系统架构

## 1. 总体数据流

```
PC 上位机
   │  UDP 5001 / RGB565 512×300
   ▼
PS GEM0 (lwIP)  ──memcpy──►  DDR @ 0x10000000
   │                              │
   │ AXI GPIO 0x41200000          │ HP0 AXI 读
   │ en[4:0] thr[7:0] src_sel     ▼
   └────────────────────►  PL 视频流水线
                              │
                              ▼
                           HDMI 1024×600 @ 50 MHz
```

上位机把一帧 RGB565 拆成 UDP 包发到板卡；PS 收满一帧后写 DDR，并置 `src_sel=1`。  
PL 侧 `axi_frame_writer` 每帧从 DDR 读入片上 `frame_buffer`，再与彩条源二选一进入效果流水线，最后左右分屏输出 HDMI。

## 2. PL 顶层框图（pl_video_top）

```
                    ┌─────────────────────────────────────────┐
 colorbar ─────────►│  src_pix = src_sel ? ddr : colorbar      │
 axi_frame_writer ─►│         (旋转映射后的坐标)                │
   DDR → frame_buf  └───────────────┬─────────────────────────┘
                                    │
          rotate_mapper (0..359°) ──┤  sx,sy / oob
                                    ▼
                         ┌──────────────────┐
                         │  proc_pipeline   │  en[4:0], thr
                         │  gray → binary   │
                         │  → blur → sobel  │  ◄── rotate≠0 时
                         │  → invert        │      bypass blur/sobel
                         └────────┬─────────┘
                                  │ 只对左半屏 de
                                  ▼
                           line_cache 一行
                                  │
          src_pix 延迟对齐 ────────┤
                                  ▼
                         ┌──────────────────┐
                         │  split_display   │
                         │ 左=原图 右=处理  │
                         │ 中间蓝分隔线     │
                         └────────┬─────────┘
                                  ▼
                              rgb2dvi → HDMI
```

### 时钟

| 时钟 | 频率 | 用途 |
|------|------|------|
| sys_clk | 50 MHz | MMCM 输入 |
| clk_pix | 50 MHz | 像素/行场/效果流水线 |
| clk_pix5x | 250 MHz | TMDS 5× 串化 |
| axi_clk | FCLK_CLK0 50 MHz | AXI HP0 读 DDR |

1024×600 时序：H=1344（1024+44+88+188），V=625（600+3+6+16），HSYNC+，VSYNC−。

## 3. PS 侧

| 模块 | 说明 |
|------|------|
| lwIP RAW + UDP | 端口 5001，IP 192.168.1.10 |
| `on_udp_frame` | 拷到 0x10000000，满帧 flush cache 并 `src_sel=1` |
| UART 115200 | 命令：5 位效果、SRC0/1、TH、FILL、STAT |
| AXI GPIO | 基址 **0x41200000**，DATA 写控制字 |

控制字布局：

```
bit[4:0]   effect_en   bit0=gray … bit4=invert
bit[15:8]  threshold   二值化阈值
bit[16]    src_sel     0=彩条  1=DDR 视频
```

## 4. 关键 RTL 文件

| 文件 | 职责 |
|------|------|
| `rtl/top/system_top.v` | PS BD 封装 + pl_video_top |
| `rtl/top/pl_video_top.v` | 视频主路径 |
| `rtl/axi/axi_frame_writer.v` | AXI3 16-beat 读 DDR |
| `rtl/video/frame_buffer.v` | 512×300×16b BRAM |
| `rtl/process/proc_pipeline.v` | 五级效果级联 |
| `rtl/process/rotate/*` | 0–359° 逆映射 + sin/cos Q8 |
| `rtl/hdmi/*` | TMDS 编码与串化 |

## 5. 旋转与效果的交互（必读）

`rotate_mapper` 把屏幕坐标 `(cx,cy)` 反算到源坐标 `(sx,sy)`。  
**blur / sobel 是 3×3 窗口滤波**，依赖源图邻域像素在扫描顺序上连续。旋转后邻域不再落在同一行连续地址上，窗口内容错误。

因此：

```verilog
// proc_pipeline.v
wire by2 = ~effect_en[2] | rotate_active;  // blur
wire by3 = ~effect_en[3] | rotate_active;  // sobel
```

| 角度 | gray | binary | blur | sobel | invert |
|------|------|--------|------|-------|--------|
| 0° | 可 | 可 | 可 | 可 | 可 |
| ≠0° | 可 | 可 | **强制关** | **强制关** | 可 |

转回 0° 后 blur/sobel 自动恢复（`rotate_active` 拉低）。
