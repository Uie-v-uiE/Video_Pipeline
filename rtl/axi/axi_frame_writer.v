`timescale 1ns/1ps
// AXI3-compatible frame fetcher (HP0): max 16 beats/burst, 64-bit data.
// Fills frame_buffer row by row with RGB565 pixels.
module axi_frame_writer #(
    parameter IMG_W     = 640,
    parameter IMG_H     = 360,
    parameter BASE_ADDR = 32'h1000_0000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        frame_start,
    output reg         frame_busy,
    output reg         frame_done,
    output reg         fb_wr_en,
    output reg  [18:0] fb_wr_addr,
    output reg  [15:0] fb_wr_data,
    output reg  [31:0] m_axi_araddr,
    output reg  [7:0]  m_axi_arlen,   // drive [3:0] for AXI3 (0..15 => 1..16 beats)
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [63:0] m_axi_rdata,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output reg         m_axi_rready
);
    assign m_axi_arsize  = 3'b011; // 8 bytes
    assign m_axi_arburst = 2'b01;  // INCR

    // 16 beats * 4 pixels = 64 pixels per burst
    localparam BEATS      = 16;
    localparam PIX_PER_B  = 4;
    localparam BURSTS_ROW = IMG_W / (BEATS * PIX_PER_B); // 10 for 640

    localparam S_IDLE = 3'd0;
    localparam S_AR   = 3'd1;
    localparam S_R    = 3'd2;
    localparam S_ROW  = 3'd3;
    localparam S_DONE = 3'd4;

    reg [2:0]  state;
    reg [11:0] row;
    reg [4:0]  burst_idx;
    reg [5:0]  beat;
    reg [1:0]  sub;
    reg [11:0] xw;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            frame_busy <= 1'b0;
            frame_done <= 1'b0;
            fb_wr_en <= 1'b0;
            fb_wr_addr <= 19'd0;
            fb_wr_data <= 16'd0;
            m_axi_arvalid <= 1'b0;
            m_axi_araddr <= BASE_ADDR;
            m_axi_arlen  <= 8'd15; // 16 beats
            m_axi_rready <= 1'b0;
            row <= 12'd0;
            burst_idx <= 5'd0;
            beat <= 6'd0;
            sub <= 2'd0;
            xw <= 12'd0;
        end else begin
            fb_wr_en <= 1'b0;
            frame_done <= 1'b0;
            case (state)
                S_IDLE: begin
                    frame_busy <= 1'b0;
                    if (enable && frame_start) begin
                        row <= 12'd0;
                        burst_idx <= 5'd0;
                        frame_busy <= 1'b1;
                        m_axi_araddr <= BASE_ADDR;
                        m_axi_arlen  <= 8'd15;
                        m_axi_arvalid<= 1'b1;
                        beat <= 6'd0;
                        sub <= 2'd0;
                        xw <= 12'd0;
                        state <= S_AR;
                    end
                end
                S_AR: begin
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        beat <= 6'd0;
                        sub <= 2'd0;
                        state <= S_R;
                    end
                end
                S_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        fb_wr_en   <= 1'b1;
                        fb_wr_addr <= row * IMG_W + xw;
                        case (sub)
                            2'd0: fb_wr_data <= m_axi_rdata[15:0];
                            2'd1: fb_wr_data <= m_axi_rdata[31:16];
                            2'd2: fb_wr_data <= m_axi_rdata[47:32];
                            default: fb_wr_data <= m_axi_rdata[63:48];
                        endcase
                        if (sub == 2'd3) begin
                            sub <= 2'd0;
                            xw  <= xw + 12'd4;
                        end else
                            sub <= sub + 2'd1;

                        beat <= beat + 6'd1;
                        if (m_axi_rlast) begin
                            m_axi_rready <= 1'b0;
                            state <= S_ROW;
                        end
                    end
                end
                S_ROW: begin
                    if (burst_idx == BURSTS_ROW - 1) begin
                        // row done
                        burst_idx <= 5'd0;
                        if (row == IMG_H - 1)
                            state <= S_DONE;
                        else begin
                            row <= row + 12'd1;
                            xw <= 12'd0;
                            m_axi_araddr <= BASE_ADDR + ((row + 12'd1) * IMG_W * 2);
                            m_axi_arlen  <= 8'd15;
                            m_axi_arvalid<= 1'b1;
                            state <= S_AR;
                        end
                    end else begin
                        burst_idx <= burst_idx + 5'd1;
                        m_axi_araddr <= m_axi_araddr + (BEATS * 8);
                        m_axi_arlen  <= 8'd15;
                        m_axi_arvalid<= 1'b1;
                        state <= S_AR;
                    end
                end
                S_DONE: begin
                    frame_done <= 1'b1;
                    frame_busy <= 1'b0;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
