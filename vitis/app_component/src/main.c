/**
 * UART -> AXI GPIO @ 0x41200000 (no xgpio driver / XPAR macros)
 * Matches system.xsa: axi_gpio_0 Reg 0x41200000-0x4120FFFF
 *
 * Register map (axi_gpio):
 *   0x00 DATA
 *   0x04 TRI  (0=output)
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "xil_printf.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xuartps.h"
#include "sleep.h"

#define FRAME_W     512
#define FRAME_H     300
#define FRAME_BYTES (FRAME_W * FRAME_H * 2)
#define FRAME_ADDR  0x10000000u

#define AXI_GPIO_BASE 0x41200000u
#define GPIO_DATA     (AXI_GPIO_BASE + 0x00u)
#define GPIO_TRI      (AXI_GPIO_BASE + 0x04u)

static void ctrl_set(u32 en, u8 thr, u8 src_sel)
{
    u32 v = (en & 0x1F) | ((u32)thr << 8) | ((u32)src_sel << 16);
    Xil_Out32(GPIO_DATA, v);
    xil_printf("[CTRL] AXI_GPIO=0x%08x en=%02x thr=%d src=%d read=0x%08x\r\n",
               v, en & 0x1F, thr, src_sel,
               (unsigned)Xil_In32(GPIO_DATA));
}

static int parse_bits(const char *s, u32 *out)
{
    u32 en = 0;
    int n = 0;
    for (; *s; ++s) {
        if (*s == '\r' || *s == '\n' || *s == ' ') break;
        if (*s != '0' && *s != '1') return -1;
        if (n >= 5) return -1;
        en |= ((u32)(*s - '0')) << n;
        ++n;
    }
    if (n == 0) return -1;
    *out = en;
    return n;
}

static void uart_poll(void)
{
    static char buf[32];
    static int idx = 0;
    while (XUartPs_IsReceiveData(STDIN_BASEADDRESS)) {
        u8 ch = XUartPs_RecvByte(STDIN_BASEADDRESS);
        if (ch == '\n' || ch == '\r') {
            buf[idx] = 0;
            if (idx > 0) {
                u32 en;
                if (parse_bits(buf, &en) > 0) {
                    ctrl_set(en, 80, 0);
                } else if (!strncmp(buf, "SRC0", 4)) {
                    ctrl_set(0, 80, 0);
                } else if (!strncmp(buf, "SRC1", 4)) {
                    ctrl_set(0, 80, 1);
                } else if (!strncmp(buf, "TH", 2) && idx > 2) {
                    int th = atoi(buf + 2);
                    if (th < 0) th = 0;
                    if (th > 255) th = 255;
                    ctrl_set(0, (u8)th, 0);
                } else if (!strncmp(buf, "FILL", 4)) {
                    volatile u16 *p = (volatile u16 *)FRAME_ADDR;
                    int i;
                    for (i = 0; i < FRAME_W * FRAME_H; i++) {
                        int x = i % FRAME_W, y = i / FRAME_W;
                        p[i] = (u16)(((x >> 3) << 11) | ((y >> 2) << 5) | ((x + y) >> 3));
                    }
                    Xil_DCacheFlushRange(FRAME_ADDR, FRAME_BYTES);
                    ctrl_set(0, 80, 1);
                    xil_printf("[CMD] DDR filled\r\n");
                } else {
                    xil_printf("[CMD] %s\r\n  00111 SRC0 SRC1 TH80 FILL\r\n", buf);
                }
            }
            idx = 0;
        } else if (idx < (int)sizeof(buf) - 1) {
            buf[idx++] = (char)ch;
        }
    }
}

int main(void)
{
    xil_printf("\r\n[BOOT] video_pipeline raw AXI GPIO @0x41200000\r\n");
    Xil_Out32(GPIO_TRI, 0x00000000u); /* all outputs */
    xil_printf("[BOOT] TRI=0x%08x\r\n", (unsigned)Xil_In32(GPIO_TRI));
    ctrl_set(0, 80, 0);
    xil_printf("[BOOT] uart115200: 00111 SRC0 SRC1 TH80 FILL\r\n");

    while (1) {
        uart_poll();
        usleep(1000);
    }
    return 0;
}
