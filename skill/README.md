# Skill Pack

从本项目开发过程中提炼的可复用经验，面向其他 Zynq / 视频类 FPGA 题目。  
竞赛要求：一支陌生队伍拿到本目录，能否直接用在自己的题目上。

---

## 1. PS 网口 + PL 视频最小闭环

**适用：** Zynq-7000，PS lwIP 收 UDP 写 DDR，PL 经 HP0 读出显示。

**步骤：**
1. BD：PS7 使能 ENET0、M_AXI_GP0、M_AXI_HP0、FCLK0  
2. AXI GPIO 挂 GP0 做控制寄存器（**不要默认用 EMIO**）  
3. 裸机：`lwip220` RAW + 静态 IP；收满一帧 `Xil_DCacheFlushRange` 后再给 PL 读  
4. PL：`axi_frame_writer` 16-beat（AXI3）顺序填 BRAM，像素钟域随机读  

**失效条件：** PHY 非标准时序；HP 位宽/ID 与脚本不一致；未 flush cache。

---

## 2. RTL8211 强制 1000M

**适用：** 自协商报 `link_speed invalid` 的 Realtek RGMII 板。

**做法：** BSP `lwipopts.h` 设 `CONFIG_LINKSPEED1000`；或在 `phy_setup_emacps` 失败路径强制 1000。

**失效条件：** 对端不支持 1000；线材/变压器问题（MDIO 可读但灯不亮）。

---

## 3. 旋转时关闭窗口滤波

**适用：** 逆映射任意角旋转 + 3×3 模糊/Sobel。

**做法：** `bypass = ~en | rotate_active`；点运算（灰度/二值/反色）保留。

**失效条件：** 若先旋转到帧缓再滤波，可恢复窗滤，但需额外带宽与一帧延迟。

---

## 4. AXI 64-bit 像素拆包

**适用：** HP 口读 RGB565/RGB888 帧进 BRAM。

**做法：**  
- 每 beat 锁存，再拆成 N 拍写 BRAM（不要每 rvalid 只写 1 像素）  
- 行地址用 **32 位** 乘法，禁止 12 位左移  
- 诊断用细线/棋盘，不要只用大色块  

**失效条件：** 数据宽度与 arsize 不一致；burst 长度超过 AXI3 的 16。

---

## 5. UDP 帧协议带 offset

**适用：** PC→板卡原始帧推送。

**包格式：** `[u32 LE offset][payload]`  
板端写 `BASE+offset`，收满一帧再 flush。

**失效条件：** 无 offset 时乱序/丢包会搅乱整帧；需应用层计数或简单重传。

---

## 6. 串口命令行尾

**适用：** 第三方串口助手「能收不能发」。

**做法：** 固定 **115200 8N1、无流控、发送 CR+LF**；固件在 `\r`/`\n` 处解析。

---

## 7. 双网卡 UDP 发送

**适用：** PC 同时有 WLAN + 以太网，ping 通但 UDP 不到板。

**做法：** `socket.bind(("192.168.1.100", 0))` 强制以太网源地址。

---

## 8. Vitis 下载与 ps7_init

**适用：** xsdb 下载后 UART 无输出。

**做法：** 使用 Vitis Run，或脚本中先 `loadhw` + `source ps7_init.tcl` + `ps7_init`/`ps7_post_config`，再 `dow`。

---

## 验证记录

- 上板：UDP 动画/真实视频、串口五效果、KEY 旋转、`FILL` 诊断图  
- 仿真：`sim/run_sim.tcl`  
- 详细设计见 `docs/ARCHITECTURE.md`、`docs/KNOWLEDGE.md`  
- 问题清单见 `docs/ISSUES.md`
