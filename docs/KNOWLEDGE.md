# 关键知识点（吃透项目用）

按「必须搞懂」排序。每条都对应工程里可点开的文件。

---

## A. 视频时序

**1024×600@50 MHz** 不是标准 CEA 时序，是面板常用时：

- 有效：1024×600  
- 消隐：H 同步 44、后沿 88、前沿 188 → 行总 1344  
- V：同步 3、后沿 6、前沿 16 → 场总 625  
- 极性：HSYNC 高有效，VSYNC 低有效  

代码：`rtl/video/video_timing_1024x600.v`  
约束：`constraints/rk_zynq7020.xdc` 里 MMCM：VCO=750，OUT0÷15=50M，OUT1÷3=250M。

**考点**：为什么像素钟 50 MHz 而不是 50.25 MHz？差 0.5% 在显示器锁相范围内。

---

## B. 左右分屏与流水线对齐

- 显示 1024 宽，每 pane 512。源 512×300，**垂直 2× 放大**（同一 sy 用两行）。  
- 效果只对 **左半屏** `de && left` 跑一遍，结果写入 `line_cache`。  
- 右半屏用同一行地址从 `line_cache` 读出，与延迟后的原图对齐。  
- 蓝分隔线：`x==511` 或 `x==512`。

**考点**：若 pipeline 延迟与 `x_d/cx_d` 对不齐，右屏会错位或花屏。当前按 map 3 拍 + BRAM 1 拍对齐。

---

## C. 五效果位定义

串口字符串 **左起 = bit0**：

| 位 | 效果 | 模块 |
|----|------|------|
| 0 | 灰度 | `proc_gray.v` |
| 1 | 二值 | `proc_binary.v`（阈值 thr） |
| 2 | 3×3 模糊 | `proc_box_blur.v` |
| 3 | Sobel 边缘 | `proc_sobel.v` |
| 4 | 反色 | `proc_invert.v` |

`00111` → bit2/3/4 = blur+sobel+invert。

**软件坑（已修）**：以前发效果位会误清 `src_sel`；现在 `en/thr/src` 三个状态独立保存。

---

## D. 任意角度旋转

参考工程思路：屏幕中心反算源坐标（Q8 定点）：

```
xp = x - W/2;  yp = H/2 - y
xr = ( cos*xp + sin*yp) >> 8
yr = (-sin*xp + cos*yp) >> 8
sx = xr + W/2;  sy = H/2 - yr
```

- `sin_rom` / `cos_rom`：0–359°，**cos(0)=256，不能饱和成 255**  
- `oob`：源坐标越界填黑，且 **反色不能把 OOB 变白**  
- KEY1/KEY2：±1°，0–359 循环；当前边沿触发，无连发  

**为何旋转关 blur/sobel**：见 `docs/ARCHITECTURE.md` §5。窗口滤波需要扫描连续邻域，逆映射破坏了这一点。gray/binary/invert 是点运算，与邻域无关，故可保留。

---

## E. AXI HP0 读 DDR

- PS7 `M_AXI_HP0` → PL `axi_frame_writer`  
- AXI3，`ARLEN` 4 bit，**最多 16 beat**  
- 源宽 32 bit，每 beat 2 个 RGB565 像素  
- 一帧 512×300×2 = 307200 B  

**考点**：ARID 在 HP 口是 6 bit；burst 长度用 `arlen=15`（16 beat）。

---

## F. PS 网络栈

- BSP：`lwip220` RAW 模式，静态 IP  
- 本板 RTL8211：`CONFIG_LINKSPEED1000`（写死 1000M），自协商失败时强制 1000  
- PHY 地址 1；`BMSR` bit2 = link up  
- 收包回调拷贝到 DDR，满帧 `Xil_DCacheFlushRange` 再给 PL 读  

**考点**：cache 不 flush，PL 会读到旧数据；flush 后还要保证地址非 cacheable 或一致性策略正确（当前 flush 策略已实测可用）。

---

## G. AXI GPIO 控制（不要用 EMIO）

本板 **EMIO bank2 读回恒 0**，不可用。控制走 GP0：

- 基址 **0x41200000**（以 XSA / `xparameters.h` 为准）  
- 寄存器：0x00 DATA，0x04 TRI（写 0 全输出）

---

## H. 上位机

- 协议：UDP，每包 ≤1400 B，一帧 220 包量级  
- 多网卡时 **bind 源 IP 192.168.1.100**，否则可能走 WLAN  
- FFmpeg：需带 **H.264 decoder** 的完整版（scoop `ffmpeg` 可用；精简版不行）

---

## I. 串口助手「能收不能发」

板端用 `XUartPs_RecvByte` 轮询，**收到 `\r` 或 `\n` 才解析**。

第三方助手请设：

| 项 | 值 |
|----|-----|
| 波特率 | 115200 8N1 |
| 流控 | 无 |
| 发送行尾 | **CR+LF**（`\\r\\n`） |
| 勾选「发送新行」 | 是 |

Vitis 自带终端默认会加换行，所以好使。部分助手默认 LF-only 或「无行尾」，命令会一直堆在 `buf` 里不执行。

---

## J. 仿真与金标

- `sim/run_sim.tcl`：四套单元 TB  
- `scripts/golden_model.py`：与 RTL 同序的 Python 金标图 → `sim_out/`  
- 对比：`rot_*.png`、`proc_*.png`、`dual_preview.png`
