`timescale 1ns/1ps
// Dual-pane video: 1024x600, source 512x300, 2x vertical scale.
// Colorbar path is pure clk_pix (works without PS/FCLK).
// DDR path uses axi_clk + frame_buffer.
module pl_video_top #(
    parameter IMG_W     = 512,
    parameter IMG_H     = 300,
    parameter PANE_W    = 512,
    parameter BASE_ADDR = 32'h1000_0000
)(
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        axi_clk,
    input  wire        axi_rst_n,

    input  wire [4:0]  effect_en,
    input  wire [7:0]  threshold,
    input  wire        src_sel,       // 0=colorbar(on-the-fly) 1=DDR

    input  wire        key1_n,
    input  wire        key2_n,
    output wire [1:0]  led,

    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_data_p,
    output wire [2:0]  tmds_data_n,

    output wire [31:0] m_axi_araddr,
    output wire [5:0]  m_axi_arid,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [63:0] m_axi_rdata,
    input  wire [5:0]  m_axi_rid,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready,

    // PL UDP eth write stream (clk_125 domain from eth_udp_video_top)
    input  wire        eth_wr_clk,
    input  wire        eth_wr_en,
    input  wire [18:0] eth_wr_addr,
    input  wire [15:0] eth_wr_data,
    input  wire        eth_link,
    input  wire        eth_frame,   // pulse: full frame reassembled
    input  wire [15:0] eth_pkts,
    input  wire [15:0] eth_bad,

    output wire [31:0] status
);
    wire clk_pix, clk_pix5x, locked;
    wire clk_200m_unused;
    clk_gen u_clk (
        .clk_in(sys_clk), .rst_n(sys_rst_n),
        .clk_pix(clk_pix), .clk_pix5x(clk_pix5x), .clk_200m(clk_200m_unused), .locked(locked)
    );
    wire rst_pix_n = sys_rst_n & locked;

    // keys / angle
    wire p1, p2;
    key_debounce #(.CNT_MAX(1_000_000)) u_k1 (
        .clk(sys_clk), .rst_n(sys_rst_n), .key_n(key1_n), .pulse(p1), .key_stable()
    );
    key_debounce #(.CNT_MAX(1_000_000)) u_k2 (
        .clk(sys_clk), .rst_n(sys_rst_n), .key_n(key2_n), .pulse(p2), .key_stable()
    );
    wire [8:0] angle;
    wire rotate_active;
    angle_ctrl u_ang (
        .clk(sys_clk), .rst_n(sys_rst_n),
        .key_inc(p1), .key_dec(p2),
        .angle(angle), .rotate_active(rotate_active)
    );

    wire [4:0] en_sync;
    wire [7:0] th_sync;
    effect_ctrl u_eff (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .effect_en_async(effect_en),
        .threshold_async(threshold),
        .effect_en(en_sync), .threshold(th_sync)
    );

    // 1024x600 timing @ 50 MHz
    wire [11:0] x, y;
    wire hs, vs, de, frame_start, frame_done;
    video_timing_1024x600 u_t (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .x(x), .y(y), .hs(hs), .vs(vs), .de(de),
        .frame_start(frame_start), .frame_done(frame_done)
    );

    wire        left_pane = (x < PANE_W);
    wire [11:0] cx = left_pane ? x : (x - PANE_W);
    wire [11:0] cy = (y >> 1) < IMG_H ? (y >> 1) : (IMG_H - 1);

    // rotate mapper (3-stage) only when angle!=0
    wire [11:0] sx_map, sy_map;
    wire        oob_map;
    rotate_mapper #(.IMAGE_W(IMG_W), .IMAGE_H(IMG_H)) u_rmap (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .angle(angle), .enable(1'b1),
        .x_in(cx), .y_in(cy),
        .x_out(sx_map), .y_out(sy_map), .oob(oob_map)
    );

    // angle==0: bypass mapper with matching 3-cycle delay (no Y-flip math)
    reg [11:0] cx_q1, cx_q2, cx_q3;
    reg [11:0] cy_q1, cy_q2, cy_q3;
    reg        oob_q1, oob_q2, oob_q3;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            {cx_q1,cx_q2,cx_q3} <= 36'd0;
            {cy_q1,cy_q2,cy_q3} <= 36'd0;
            {oob_q1,oob_q2,oob_q3} <= 3'd1;
        end else begin
            cx_q1 <= cx; cx_q2 <= cx_q1; cx_q3 <= cx_q2;
            cy_q1 <= cy; cy_q2 <= cy_q1; cy_q3 <= cy_q2;
            oob_q1 <= (cx >= IMG_W) || (cy >= IMG_H);
            oob_q2 <= oob_q1;
            oob_q3 <= oob_q2;
        end
    end

    wire        rot_on = rotate_active;
    wire [11:0] sx = rot_on ? sx_map : cx_q3;
    wire [11:0] sy = rot_on ? sy_map : cy_q3;
    wire        oob = rot_on ? oob_map : oob_q3;

    // Auto-switch only after at least one complete ETH frame
    // eth_frame is in eth_clk domain — toggle + 2FF sync
    reg eth_frame_tog = 1'b0;
    always @(posedge eth_wr_clk) if (eth_frame) eth_frame_tog <= ~eth_frame_tog;
    reg ef0, ef1, ef2;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) {ef2,ef1,ef0} <= 3'b0;
        else {ef2,ef1,ef0} <= {ef1,ef0,eth_frame_tog};
    end
    wire eth_frame_axi = ef1 ^ ef2;
    reg eth_has_frame = 1'b0;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) eth_has_frame <= 1'b0;
        else if (eth_frame_axi) eth_has_frame <= 1'b1;
    end
    wire src_use = src_sel | (eth_link & eth_has_frame);

    // ---- colorbar on the fly (no BRAM, no FCLK) ----
    wire [15:0] bar_at_cxcy;
    color_bar #(.H_ACTIVE(IMG_W), .V_ACTIVE(IMG_H)) u_bar (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .x(cx), .y(cy), .de(de), .rgb565(bar_at_cxcy)
    );

    // ---- DDR path: AXI fill into BRAM, then random read ----
    reg fs_tog;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) fs_tog <= 1'b0;
        else if (frame_start && src_use && !eth_link) fs_tog <= ~fs_tog;
    end
    reg fs0, fs1, fs2;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) {fs0,fs1,fs2} <= 3'b0;
        else {fs0,fs1,fs2} <= {fs_tog, fs0, fs1};
    end
    wire axi_frame_start = fs1 ^ fs2;

    wire        aw_wr_en;
    wire [18:0] aw_wr_addr;
    wire [15:0] aw_wr_data;
    wire        aw_frame_done;
    assign m_axi_arid = 6'd0;

    axi_frame_writer #(.IMG_W(IMG_W), .IMG_H(IMG_H), .BASE_ADDR(BASE_ADDR)) u_aw (
        .clk(axi_clk), .rst_n(axi_rst_n),
        .enable(src_use && !eth_link),
        .frame_start(axi_frame_start),
        .frame_busy(), .frame_done(aw_frame_done),
        .fb_wr_en(aw_wr_en), .fb_wr_addr(aw_wr_addr), .fb_wr_data(aw_wr_data),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready)
    );

    wire [15:0] fb_rd;
    wire [18:0] rd_addr = sy * IMG_W + sx;

    // CDC eth write stream (eth_wr_clk) -> axi_clk
    wire [35:0] eth_fifo_dout;
    wire eth_fifo_empty, eth_fifo_full;
    reg  eth_fifo_rd = 0;
    reg  eth_wr_axi = 0;
    reg [18:0] eth_a_axi;
    reg [15:0] eth_d_axi;
    reg eth_rd_d = 0;

    // Pack: {addr[18:0], data[15:0]} = 35 bits into 36-bit word
    // bit[34:16]=addr, bit[15:0]=data, bit[35]=0
    dc_fifo #(.DATA_W(36), .ADDR_W(6)) u_eth_cdc (
        .wr_clk(eth_wr_clk), .wr_rst_n(sys_rst_n),
        .wr_en(eth_wr_en && !eth_fifo_full),
        .wr_data({1'b0, eth_wr_addr, eth_wr_data}),
        .wr_full(eth_fifo_full),
        .rd_clk(axi_clk), .rd_rst_n(axi_rst_n),
        .rd_en(eth_fifo_rd), .rd_data(eth_fifo_dout), .rd_empty(eth_fifo_empty)
    );

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            eth_fifo_rd <= 0; eth_rd_d <= 0; eth_wr_axi <= 0;
            eth_a_axi <= 0; eth_d_axi <= 0;
        end else begin
            eth_fifo_rd <= !eth_fifo_empty && !eth_fifo_rd && !eth_rd_d;
            eth_rd_d    <= eth_fifo_rd;
            eth_wr_axi  <= eth_rd_d;
            if (eth_rd_d) begin
                eth_a_axi <= eth_fifo_dout[34:16];  // NOT [35:17]
                eth_d_axi <= eth_fifo_dout[15:0];
            end
        end
    end

    // ETH writes BRAM live (proven display path). AXI path for PS FILL/DDR.
    wire        fb_wr_en   = eth_link ? eth_wr_axi  : aw_wr_en;
    wire [18:0] fb_wr_addr = eth_link ? eth_a_axi   : aw_wr_addr;
    wire [15:0] fb_wr_data = eth_link ? eth_d_axi   : aw_wr_data;

    frame_buffer #(.W(IMG_W), .H(IMG_H)) u_fb (
        .wr_clk(axi_clk), .wr_en(fb_wr_en), .wr_addr(fb_wr_addr), .wr_data(fb_wr_data),
        .rd_clk(clk_pix), .rd_addr(rd_addr), .rd_data(fb_rd)
    );

    // source pixel: colorbar needs 1-cycle align with rotate map (3) + bar is registered (1)
    // bar_at_cxcy is registered from (cx,cy) at stage0 of rotate; rotate takes 3.
    // Delay bar by 3 to match sx/sy/fb path... simpler: sample bar with same 4-cycle budget.
    reg [15:0] bar_d1, bar_d2, bar_d3;
    always @(posedge clk_pix) begin
        bar_d1 <= bar_at_cxcy;
        bar_d2 <= bar_d1;
        bar_d3 <= bar_d2;
    end

    reg oob_d1;
    always @(posedge clk_pix) oob_d1 <= oob;
    wire [15:0] ddr_pix = oob_d1 ? 16'h0000 : fb_rd;
    wire [15:0] src_pix = src_use ? ddr_pix : bar_d3;

    // delay sideband by 4 (map3 + BRAM1)
    reg        de_d[0:3], hs_d[0:3], vs_d[0:3], left_d[0:3];
    reg [11:0] x_d[0:3], y_d[0:3], cx_d[0:3], cy_d[0:3];
    reg        oob_d[0:4];
    integer k;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            for (k = 0; k < 4; k = k + 1) begin
                de_d[k] <= 0; hs_d[k] <= 0; vs_d[k] <= 0; left_d[k] <= 1;
                x_d[k] <= 0; y_d[k] <= 0; cx_d[k] <= 0; cy_d[k] <= 0;
                oob_d[k] <= 0;
            end
            oob_d[4] <= 0;
        end else begin
            de_d[0]<=de; hs_d[0]<=hs; vs_d[0]<=vs; left_d[0]<=left_pane;
            x_d[0]<=x; y_d[0]<=y; cx_d[0]<=cx; cy_d[0]<=cy;
            oob_d[0]<=oob;
            for (k = 1; k < 4; k = k + 1) begin
                de_d[k]<=de_d[k-1]; hs_d[k]<=hs_d[k-1]; vs_d[k]<=vs_d[k-1];
                left_d[k]<=left_d[k-1]; x_d[k]<=x_d[k-1]; y_d[k]<=y_d[k-1];
                cx_d[k]<=cx_d[k-1]; cy_d[k]<=cy_d[k-1]; oob_d[k]<=oob_d[k-1];
            end
            oob_d[4] <= oob_d[3];
        end
    end

    wire [15:0] pipe_dout;
    wire        pipe_de;

    proc_pipeline #(.H_ACTIVE(IMG_W)) u_pipe (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .effect_en(en_sync), .threshold(th_sync),
        .rotate_active(rot_on),
        .hs_in(hs_d[3]), .vs_in(vs_d[3]),
        .de_in(de_d[3] && left_d[3]),
        .x_in(cx_d[3]), .y_in(cy_d[3]),
        .din(src_pix),
        .de_out(pipe_de), .dout(pipe_dout)
    );

    reg [11:0] pw;
    wire [15:0] proc_rd;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) pw <= 12'd0;
        else if (de_d[3] && x_d[3] == 12'd0) pw <= 12'd0;
        else if (pipe_de) pw <= pw + 12'd1;
    end
    line_cache #(.W(IMG_W)) u_proc_line (
        .wr_clk(clk_pix), .wr_en(pipe_de), .wr_addr(pw), .wr_data(pipe_dout),
        .rd_clk(clk_pix), .rd_addr(cx_d[3]), .rd_data(proc_rd)
    );

    // force black on OOB after effects (do not invert OOB to white)
    wire oob_out = oob_d[4];
    wire [15:0] proc_out = oob_out ? 16'h0000 : proc_rd;

    reg        de_d4, hs_d4, vs_d4;
    reg [11:0] x_d4, y_d4;
    reg [15:0] orig_disp;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            de_d4<=0; hs_d4<=0; vs_d4<=0; x_d4<=0; y_d4<=0; orig_disp<=0;
        end else begin
            de_d4<=de_d[3]; hs_d4<=hs_d[3]; vs_d4<=vs_d[3];
            x_d4<=x_d[3]; y_d4<=y_d[3];
            orig_disp<=src_pix;
        end
    end

    wire [7:0] r, g, b;
    wire de_o, hs_o, vs_o;
    split_display #(.PANE_W(PANE_W)) u_split (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .x(x_d4), .y(y_d4), .de(de_d4), .hs(hs_d4), .vs(vs_d4),
        .orig_pix(orig_disp), .proc_pix(proc_out),
        .angle_idx(angle[1:0]), .oob(oob_out),
        .r(r), .g(g), .b(b),
        .de_out(de_o), .hs_out(hs_o), .vs_out(vs_o)
    );

    // FPS from vs edges (vs_d4 is pre-split; use pipeline vs)
    reg vs_pix_d0, vs_pix_d1;
    always @(posedge clk_pix) begin
        vs_pix_d0 <= vs_d4;
        vs_pix_d1 <= vs_pix_d0;
    end
    wire vs_tick = vs_pix_d0 & ~vs_pix_d1;

    reg [31:0] fps_acc;
    reg [25:0] sec_div;
    reg [7:0]  fps_q;
    reg vt0, vt1, vt2;
    always @(posedge sys_clk) {vt2, vt1, vt0} <= {vt1, vt0, vs_tick};
    wire vs_sys = vt1 & ~vt2;

    always @(posedge sys_clk or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            sec_div <= 0; fps_acc <= 0; fps_q <= 0;
        end else if (sec_div == 26'd49_999_999) begin
            sec_div <= 0;
            fps_q   <= fps_acc[7:0];
            fps_acc <= 0;
        end else begin
            sec_div <= sec_div + 1'b1;
            if (vs_sys) fps_acc <= fps_acc + 1'b1;
        end
    end

    reg [15:0] pkts_s0, pkts_s1, bad_s0, bad_s1;
    reg        link_s0, link_s1;
    always @(posedge clk_pix) begin
        {pkts_s1, pkts_s0} <= {pkts_s0, eth_pkts};
        {bad_s1, bad_s0}   <= {bad_s0, eth_bad};
        {link_s1, link_s0} <= {link_s0, eth_link};
    end

    wire [7:0] r_osd, g_osd, b_osd;
    wire de_osd, hs_osd, vs_osd;
    osd_overlay u_osd (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .x(x_d4), .y(y_d4), .de(de_o),
        .angle(angle), .effect_en(en_sync), .fps(fps_q),
        .src_sel(src_use), .eth_link(link_s1),
        .net_pkts(pkts_s1), .net_bad(bad_s1),
        .bg_pix(16'h0),
        .r_in(r), .g_in(g), .b_in(b),
        .hs_in(hs_o), .vs_in(vs_o),
        .r(r_osd), .g(g_osd), .b(b_osd),
        .de_out(de_osd), .hs_out(hs_osd), .vs_out(vs_osd)
    );

    rgb2dvi u_dvi (
        .clk_pix(clk_pix), .clk_pix5x(clk_pix5x), .rst_n(rst_pix_n),
        .r(r_osd), .g(g_osd), .b(b_osd),
        .hs(hs_osd), .vs(vs_osd), .de(de_osd),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_data_p(tmds_data_p), .tmds_data_n(tmds_data_n)
    );

    reg [24:0] hb;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) hb <= 25'd0;
        else hb <= hb + 25'd1;
    end
    assign led[0] = hb[24];
    assign led[1] = eth_link | (|en_sync);
    assign status = {3'd0, eth_link, locked, rotate_active, angle, en_sync, src_sel, 10'd0};
endmodule
