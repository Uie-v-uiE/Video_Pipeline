# 系统架构与数据通路

## 1. 总体框图

```
┌─────────────┐   UDP 5001    ┌──────────────────┐
│  PC 上位机   │ ────────────► │  PS GEM0 + lwIP  │
│ video_sender │  RGB565      │  192.168.1.10    │
└─────────────┘  512×300      └────────┬─────────┘
                                       │ memcpy + DCacheFlush
                                       ▼
                              ┌──────────────────┐
                              │  DDR @ 0x10000000│
                              │  512×300×2 B     │
                              └────────┬─────────┘
                                       │ AXI HP0 (64-bit, 16-beat)
                                       ▼
┌─────────────┐  AXI GPIO     ┌──────────────────┐
│   UART      │ ────────────► │  PL 视频流水线    │
│  115200     │  en/thr/src   │  pl_video_top    │
└─────────────┘               └────────┬─────────┘
                                       │ TMDS
                                       ▼
                              ┌──────────────────┐
                              │ HDMI 1024×600    │
                              │ 左原图 | 右处理  │
                              └──────────────────┘
```

## 2. PL 内部数据通路

```
video_timing_1024x600
        │ x,y,de,hs,vs,frame_start
        ▼
   left_pane = (x < 512)
   cx = x 或 x-512          ← 每半屏内的 0..511
   cy = y >> 1              ← 垂直 2× 放大
        │
        ├──────────────────────────────┐
        ▼                              ▼
  rotate_mapper                  color_bar
  (angle≠0 时启用)               (SRC0 时用)
        │ sx,sy,oob                    │
        ▼                              │
  frame_buffer 读                      │
  addr = sy*512+sx                     │
        │ fb_rd                        │
        ▼                              ▼
   src_pix = src_sel ? ddr_pix : colorbar
        │
        ├──────────────────────────────┐
        ▼                              │
  proc_pipeline（仅左半屏 de）          │
  gray→binary→blur→sobel→invert       │
        │ pipe_dout                    │
        ▼                              │
  line_cache 一行                      │
        │ proc_rd                      │
        ▼                              ▼
              split_display
         左=orig  右=proc  中间蓝线
                    │
                    ▼
               rgb2dvi → HDMI
```

**同步策略：** rotate_mapper 固定 3 拍；BRAM 读 1 拍；sideband（de/x/y/left）延迟 4 拍对齐。angle=0 时旁路 mapper，对 cx/cy 做同样 3 拍延迟，保证两条路径延迟一致。

## 3. PS 侧软件通路

```
lwIP RAW UDP 收包
    │  包格式: [u32 LE offset][RGB565 数据]
    ▼
memcpy → DDR[FRAME_ADDR + offset]
    │  收满 307200 B 后
    ▼
Xil_DCacheFlushRange(FRAME_ADDR, FRAME_BYTES)
    │
    ▼
ctrl_set_src(1)  ← 自动切到 DDR 显示
```

**为何用 offset 包头：** UDP 不保证顺序；若按到达顺序 memcpy，乱序/丢包会把帧搅成块状错位。带 offset 后即使乱序也写到正确位置。

**为何收满再 flush：** 避免 PL 读到半帧。flush 后 DDR 与 cache 一致，HP0 读到的是完整新帧。

## 4. 时钟

| 时钟 | 频率 | 来源 | 用途 |
|------|------|------|------|
| sys_clk | 50 MHz | 板载 | MMCM 输入 |
| clk_pix | 50 MHz | MMCM OUT0 | 像素、效果、HDMI 并行 |
| clk_pix5x | 250 MHz | MMCM OUT1 | TMDS 5× 串化 |
| axi_clk | 50 MHz | PS FCLK_CLK0 | AXI HP0、frame_writer |

MMCM：VCO=750 MHz，OUT0÷15=50M，OUT1÷3=250M。

1024×600 时序：H=1344（1024+44+88+188），V=625（600+3+6+16），HSYNC+，VSYNC−。规格像素钟 50.25 MHz，用 50 MHz 误差 0.5%，面板可锁。

## 5. 带宽估算

### 5.1 UDP 入口

- 分辨率 512×300×2 B = **307200 B/帧**
- 30 fps → **9.2 MB/s ≈ 74 Mbps**
- 千兆网余量充足；UDP 包 1400 B，约 220 包/帧

### 5.2 AXI HP0 读

- 每帧 307200 B，按 60 Hz 刷新（显示帧率）→ **18.4 MB/s**
- 64-bit @ 50 MHz 理论峰值 **400 MB/s**，占用 <5%
- 16-beat burst：16×8=128 B/次；每行 1024 B = 8 burst；300 行 = 2400 burst/帧

### 5.3 BRAM

- frame_buffer：512×300×16b = **2.34 Mbit**
- line_cache：512×16b
- XC7Z020 BRAM 约 4.9 Mbit，占用约一半

### 5.4 为何源选 512×300

| 方案 | 帧字节 | BRAM | 说明 |
|------|--------|------|------|
| 512×300 | 307 KB | 2.3 Mb | 当前，余量充足 |
| 640×360 | 460 KB | 3.5 Mb | 可升级 |
| 1280×720 | 1.8 MB | 13.8 Mb | 超出 7020 BRAM，需外缓存/降色深 |

UDP 30 fps 对 512×300 足够；再高分辨率主要卡在片上 BRAM，不是网口。

## 6. 控制字（AXI GPIO）

基址 **0x41200000**，DATA 寄存器 0x00，TRI 0x04（写 0 全输出）。

```
bit[4:0]   effect_en
             bit0 gray
             bit1 binary
             bit2 blur      ← angle≠0 强制 0
             bit3 sobel     ← angle≠0 强制 0
             bit4 invert
bit[15:8]  threshold（二值化）
bit[16]    src_sel  0=彩条  1=DDR
```

**不要用 EMIO：** 本板 PS EMIO GPIO bank2 读回恒 0，已验证不可用。

## 7. 五效果流水线

级联顺序：**gray → binary → blur → sobel → invert**。

每个模块有 `bypass`：`bypass=1` 时数据直通。

```
by2 = ~en[2] | rotate_active   // blur
by3 = ~en[3] | rotate_active   // sobel
```

**为何旋转关 blur/sobel：**  
3×3 窗口滤波依赖「源图中相邻像素在扫描顺序上连续」。逆映射后，屏幕上相邻两点对应的源坐标可能相距很远，窗口内容错误，表现为花屏/噪点。  
gray/binary/invert 是**点运算**，只与当前像素有关，与邻域无关，故旋转时保留。  
angle 回到 0 后 `rotate_active=0`，blur/sobel 自动恢复，无需重发串口命令。

详见 `ROTATION_AND_EFFECTS.md`。

## 8. 任意角旋转

屏幕坐标 (cx,cy) 反算源坐标：

```
xp = cx - W/2
yp = H/2 - cy          // Y 翻转到数学坐标
xr = ( cos*xp + sin*yp) >> 8
yr = (-sin*xp + cos*yp) >> 8
sx = xr + W/2
sy = H/2 - yr
```

- sin/cos 为 Q8 定点（256=1.0），ROM 0..359°
- **cos(0)=256，绝不能饱和成 255**（否则 0° 不是恒等）
- 越界 `oob` 填黑；反色不能把 OOB 变白
- KEY1/KEY2：±1°，0–359 环绕

angle=0 时旁路整个 mapper，用延迟 3 拍的 cx/cy 直接寻址，避免符号运算带来的翻转风险，并与 sideband 延迟对齐。

## 9. HDMI 输出

- 左窗 x∈[0,511]：原图（src_pix）
- 右窗 x∈[512,1023]：处理图（line_cache 读出）
- x=511,512：蓝色分隔线
- 垂直 2×：同一 cy 显示两行

效果只在左半屏跑一遍写入 line_cache，右半屏读同一行，保证左右同源可对比。

## 10. 模块文件对照

| 模块 | 文件 | 职责 |
|------|------|------|
| 系统顶层 | `rtl/top/system_top.v` | PS BD + pl_video_top |
| 视频顶层 | `rtl/top/pl_video_top.v` | 主数据通路 |
| 时序 | `rtl/video/video_timing_1024x600.v` | 1024×600 |
| 彩条 | `rtl/video/color_bar.v` | SRC0 |
| 分屏 | `rtl/video/split_display.v` | 左右窗 + 分隔线 |
| 帧缓 | `rtl/video/frame_buffer.v` | 512×300 BRAM |
| 行缓 | `rtl/video/line_cache.v` | 处理结果一行 |
| AXI 读 | `rtl/axi/axi_frame_writer.v` | HP0→BRAM |
| 效果链 | `rtl/process/proc_pipeline.v` | 五级级联 |
| 旋转 | `rtl/process/rotate/*` | 映射 + ROM + 按键 |
| HDMI | `rtl/hdmi/*` | TMDS |
