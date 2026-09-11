# 赛事整理清单（FPGA 创新设计赛道 · AMD/Xilinx 自命题）

> 依据公开赛道惯例整理。**最终以当年官方规程 PDF 为准**，提交前务必对照官网通知核对页数/格式/截止时间。

官网入口：http://www.fpgachina.cn/

---

## 1. 本工程已具备（可直接进报告素材）

| 能力 | 工程位置 | 演示方式 |
|------|----------|----------|
| 以太网 UDP 送视频 | `sw/host` + PS lwIP | `run_sender.bat` / `run_video.bat` |
| HDMI 双窗显示 | `rtl/video/split_display.v` | 左原图 / 右处理 |
| 5 种图像处理 | `rtl/process/*` | 串口 `00111` 等 |
| 0–359° 旋转 | `rtl/process/rotate/*` | KEY1/KEY2 |
| PS 串口控制 | `sw/ps/main.c` | 115200 |
| 单元仿真 + 金标 | `sim/`、`scripts/golden_model.py` | 仿真 PASS + PNG |

板卡：RK-ZYNQ7020-F，XC7Z020-CLG484-2  
工具：Vivado / Vitis **2025.2.1**

---

## 2. 建议提交物结构（与本仓库对应）

```
zynq_video_pipeline/
├── README.md                 ← 一页读懂项目
├── docs/                     ← 设计报告可直接引用
│   ├── PROJECT.md
│   ├── ARCHITECTURE.md
│   ├── KNOWLEDGE.md
│   ├── ROTATION_AND_EFFECTS.md
│   ├── ETH_BRINGUP.md
│   ├── SYSTEM_BRINGUP.md
│   ├── TIMING_REPORT.md      ← 【你补】时序优化分析
│   └── LLM_ASSIST_LOG.md     ← 【你补】LLM 辅助记录
├── rtl/                      ← PL 源码
├── constraints/
├── tcl/                      ← 一键重建工程
├── sim/
├── sw/ps/                    ← 裸机源码（与 Vitis 同步）
├── sw/host/                  ← 上位机
└── scripts/
```

**不要提交**：Vivado 运行目录、Vitis `build/`、超大原始视频（见 `.gitignore`）。  
**可选提交**：`output/system.bit`（演示方便，注意体积）。

---

## 3. 【必须你本人完成】材料

### 3.1 时序优化分析（`docs/TIMING_REPORT.md`）

从 Vivado 导出并写清：

1. **Clock Summary**（各时钟 WNS/TNS）  
2. **关键路径**：截图 `report_timing` 最差 10 条，说明在 rotate_mapper / 效果流水线 / HDMI 哪一段  
3. **优化过程**（本工程已有记录可写）：  
   - 早期 720p@75 MHz 曾 WNS≈−1.3 ns  
   - 对 `rotate_mapper` 插拍流水  
   - 改为 1024×600@50 MHz 后 WNS≥0  
4. **资源**：LUT/FF/BRAM/DSP 占用表  
5. **约束策略**：主时钟 50 MHz、TMDS 250 MHz、异步 FIFO/跨时钟（axi_clk ↔ clk_pix）

命令参考：

```tcl
# Vivado Tcl
report_clocks
report_timing_summary -file output/timing_summary.rpt
report_utilization -file output/util.rpt
```

### 3.2 LLM 辅助记录（`docs/LLM_ASSIST_LOG.md`）

按赛规若要求披露 AI 使用，至少写：

- 使用场景：架构讨论、RTL 骨架、TCL 脚本、调试 PHY/串口  
- 人工完成：板级验证、时序闭合、接口定义、验收判据  
- 修改与验证：哪些生成代码被改过、如何仿真/上板确认  
- 边界：不代替写设计报告中的个人创新论述

### 3.3 演示视频

建议 3–5 分钟：

1. 上电 HDMI 双窗  
2. PC 发动画/真实视频  
3. 串口改效果位，右窗变化  
4. KEY 旋转，说明 blur/sobel 自动关闭  
5. 读一句 `STAT` / ping  

### 3.4 设计报告章节建议

1. 赛题理解与方案对比  
2. 系统架构（引用 `docs/ARCHITECTURE.md`）  
3. PL 关键设计（时序、旋转、效果、AXI）  
4. PS 软件与协议  
5. 测试与结果（仿真金标 + 上板）  
6. 问题与解决（EMIO 不可用、PHY 强制 1000M、串口行尾等）  
7. 总结与展望  
8. 参考资料与 AI 使用说明  

---

## 4. 自命题赛道常见关注点（答辩备问）

| 问题 | 可答要点 |
|------|----------|
| 为何不用 HDMI 输入？ | 赛题为网口送视频，PS 做协议、PL 做像素，分工清晰 |
| 为何源 512×300？ | UDP 带宽与 BRAM/HP0 压力；显示 2× 垂直放大 |
| 旋转精度？ | Q8 定点 + 0–359 查表；OOB 黑边 |
| 旋转为何少两个效果？ | 窗口滤波邻域在旋转坐标系下不成立，见 KNOWLEDGE D |
| 时序如何过？ | 50 MHz 像素钟 + mapper 插拍 |
| 能否 720p？ | 可改时序与 BRAM，需重做时序收敛 |

---

## 5. 提交前检查

- [ ] `tcl/create_project.tcl` + `build_system_axigpio.tcl` 可复现工程  
- [ ] `sim/run_sim.tcl` 四项 PASS  
- [ ] 上板：UDP 视频 + 五效果 + 旋转  
- [ ] README 与报告参数一致（IP、端口、分辨率、基址）  
- [ ] 无密钥、无绝对个人路径（或在 README 注明环境）  
- [ ] `.gitignore` 生效，仓库体积合理  
- [ ] LLM 与引用符合当年赛规  

---

## 6. 仍需你确认的官方信息

请在官网/通知里核对并填入下表：

| 项 | 官方要求 | 你的填写 |
|----|----------|----------|
| 参赛组别/队伍人数 | | |
| 报告页数与模板 | | |
| 是否强制开源仓库 | | |
| 截止时间 | | |
| 演示视频时长/平台 | | |
| AI 使用披露格式 | | |
