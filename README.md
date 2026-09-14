# Zynq7020 Ethernet Video Pipeline

UDP video from PC → **PL hardware** (RGMII / ARP / ICMP / UDP / frame reassembly) → image processing → HDMI dual-pane display.  
PS is **control-plane only** (UART + AXI GPIO).

| Item | Value |
|------|--------|
| Board | RK-ZYNQ7020-F (XC7Z020-CLG484-2) |
| Tool | Vivado / Vitis **2025.2.1** |
| Source | **512×300 RGB565** |
| Display | HDMI **1024×600 @ 50 MHz**, left original / right processed, 2× vertical |
| Network | Board **PL ETH** `192.168.1.10:5001`, PC `192.168.1.100` |
| Control | AXI GPIO @ `0x41200000`, UART 115200 |
| License | MIT |

---

## Directory layout

Follows the competition recommended structure (all names English).

```
<project_name>/
├── README.md
├── src/                      # Design sources
│   ├── rtl/                  # Verilog (top / eth / video / process / axi / hdmi)
│   ├── ps/                   # Bare-metal control (UART + GPIO)
│   ├── host/                 # PC UDP sender
│   └── constraints/          # XDC (pins + timing)
├── sim/                      # Testbenches + run_sim.tcl
├── build/                    # Build scripts + reports + bit/xsa
│   ├── tcl/                  # Vivado batch scripts
│   ├── scripts/              # Golden model, ROM generators
│   ├── reports/              # Timing / utilization
│   ├── system.bit
│   └── system.xsa
├── board/                    # Board bring-up notes
├── data/golden/              # Reference images
├── skill/                    # Reusable skills
└── report/                   # Design docs, issues, PS vs PL, competition
```

**Mapping from older layout (if you used it):**

| Old | New |
|-----|-----|
| `rtl/` | `src/rtl/` |
| `sw/ps/` | `src/ps/` |
| `sw/host/` | `src/host/` |
| `constraints/` | `src/constraints/` |
| `tcl/` | `build/tcl/` |
| `output/` | `build/` |
| `docs/` | `report/` |
| `sim_out/` | `data/golden/` |

---

## Quick start

### 1. Build bitstream + XSA

```bat
cd /d <repo_root>
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
%VIVADO% -mode batch -source build\tcl\build_system_axigpio.tcl
```

Outputs: `build/system.bit`, `build/system.xsa`

### 2. Program FPGA

```bat
%VIVADO% -mode batch -source build\tcl\program_system.tcl
```

### 3. PS ELF (needed for UART commands)

1. Open Vitis workspace, create Platform from **latest** `build/system.xsa`
2. Application source: `src/ps/main.c`
3. Build → Run

> After programming the bitstream the PS is reset. You must **Run** the ELF again for UART.

### 4. Stream video

```bat
:: PC NIC 192.168.1.100/24, cable to PL ETH port
src\host\run_sender.bat
:: or
src\host\run_video.bat D:\path\to\video.mp4
```

---

## UART commands (115200 8N1, send CR+LF)

| Command | Action |
|---------|--------|
| `00000` | All effects off |
| `10000` | Grayscale |
| `01000` | Binarize |
| `00111` | Blur+Sobel+Invert |
| `SRC0` / `SRC1` | Colorbar / DDR |
| `TH80` | Threshold |
| `FILL` | Diagnostic pattern |
| `STAT` | Status |

Effect bits: **gray / binary / blur / sobel / invert** (left = bit0)

ETH packets auto-switch the display path (`src_use`); `SRC1` is optional.

---

## UDP protocol (host ↔ board)

```
[u32 LE byte_offset][RGB565 payload]
```

- Frame: 512×300×2 = 307200 bytes  
- Payload per packet ≤ 1396 bytes  
- Host: `src/host/video_sender.py`  
- Board: `src/rtl/eth/frame_reasm.v` writes `BRAM[offset/2]`  
- Bad frames: drop, no retransmit; next frame recovers  

---

## Documentation

| File | Content |
|------|---------|
| [report/ARCHITECTURE.md](report/ARCHITECTURE.md) | Data path, clocks, bandwidth |
| [report/MODULES.md](report/MODULES.md) | Module details |
| [report/ISSUES.md](report/ISSUES.md) | Problems and fixes |
| [report/PS_VS_PL.md](report/PS_VS_PL.md) | PS vs PL, rotate+filter redesign |
| [report/ETH_BRINGUP.md](report/ETH_BRINGUP.md) | Ethernet bring-up |
| [report/ROTATION_AND_EFFECTS.md](report/ROTATION_AND_EFFECTS.md) | Target-domain 3×3 filters |
| [report/PERF_REPORT.md](report/PERF_REPORT.md) | Performance comparison |
| [report/COMPETITION.md](report/COMPETITION.md) | Submission checklist |
| [skill/README.md](skill/README.md) | Skill pack |

---

## Key design notes

- **PL protocol stack**: RGMII → ARP/ICMP/UDP → offset reassembly → BRAM  
- **PS control only**: UART → AXI GPIO → effect enables  
- **Target-domain filters**: blur/sobel work at any rotation angle (no bypass)  
- **OSD**: three lines FPS / ANG / EN on top-left  
- **Host protocol unchanged**; plug the cable into the **PL** Ethernet port  

See `report/ISSUES.md` for the full debug log.
