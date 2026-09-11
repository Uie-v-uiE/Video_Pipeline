# Skill Pack

从本项目开发过程中提炼的可复用经验，面向其他 Zynq / 视频类 FPGA 题目。

## 1. PS 网口 + PL 视频最小闭环

**适用：** Zynq-7000，PS lwIP 收 UDP 写 DDR，PL 经 HP0 读出显示。

**步骤：**
1. BD：PS7 使能 ENET0、M_AXI_GP0、M_AXI_HP0、FCLK0  
2. AXI GPIO 挂 GP0 做效果/源选择寄存器（**不要用 EMIO，部分板卡 bank 读回异常**）  
3. 裸机：`lwip220` RAW + 静态 IP；收满一帧 `Xil_DCacheFlushRange` 后再给 PL 读  
4. PL：`axi_frame_writer` 16-beat（AXI3）顺序填 BRAM，像素钟域随机读  

**失效条件：** PHY 为非标准时序；HP 口位宽/ID 宽度与脚本不一致；未开 cache flush。

## 2. RTL8211 强制 1000M

**适用：** 自协商报 `link_speed invalid` 的 Realtek RGMII 板。

**做法：** BSP `lwipopts.h` 设 `CONFIG_LINKSPEED1000`；或在 `phy_setup_emacps` 失败路径强制 1000 并 `SetUpSLCRDivisors`。

**失效条件：** 交换机/网卡不支持 1000；线序/变压器问题（MDIO 能读但链路灯灭）。

## 3. 旋转时关闭窗口滤波

**适用：** 逆映射任意角旋转 + 3×3 模糊/Sobel。

**做法：** `bypass = ~en | rotate_active`；点运算（灰度/二值/反色）保留。

**失效条件：** 若先旋转到帧缓再滤波，可恢复窗滤，但需额外带宽与一帧延迟。

## 4. 串口命令行尾

**适用：** 第三方串口助手「能收不能发」。

**做法：** 固定 **115200 8N1、无流控、发送 CR+LF**；固件在 `\r`/`\n` 处解析。

## 5. 双网卡 UDP 发送

**适用：** PC 同时有 WLAN + 以太网，ping 通但 UDP 不到板。

**做法：** `socket.bind(("192.168.1.100", 0))` 强制从以太网源地址发出。

## 6. 金标对照

**适用：** 旋转/效果 RTL 与软件模型一致性。

**做法：** `scripts/golden_model.py` 与 RTL 同序输出 PNG；仿真 TB 只测关键算子，整图靠金标。

## 验证记录

- 上板：UDP 动画/视频、串口五效果、KEY 旋转、`FILL`  
- 仿真：`sim/run_sim.tcl`  
- 详细设计见 `docs/KNOWLEDGE.md`、`docs/ARCHITECTURE.md`
