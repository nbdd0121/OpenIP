/*
 * Copyright (c) 2018, Gary Guo
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *  * Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 */

// A component that converts an AXI-lite interface to a BRAM interface.
//
// By default this controller will use a fall-through FIFO, which introduces no latency but may cause timing issues.
// It can be tweaked using {R,W}_FALL_THROUGH. You may also increase size of the FIFO by tweaking MAX_{R/W}_XACT.
module axi_lite_bram_ctrl #(
    parameter DATA_WIDTH = 64,
    parameter BRAM_ADDR_WIDTH = 16,
    parameter MAX_R_XACT = 1,
    parameter MAX_W_XACT = 1,
    parameter R_FALL_THROUGH = 1,
    parameter W_FALL_THROUGH = 1
) (
    axi_lite_channel.slave       master,

    output                       bram_en,
    output [DATA_WIDTH/8-1:0]    bram_we,
    output [BRAM_ADDR_WIDTH-1:0] bram_addr,
    output [DATA_WIDTH-1:0]      bram_wrdata,
    input  [DATA_WIDTH-1:0]      bram_rddata
);

    localparam STRB_WIDTH = DATA_WIDTH / 8;
    localparam UNUSED_ADDR_WIDTH = $clog2(STRB_WIDTH);

    // Static checks of interface matching
    // We currently don't strictly enforce UNUSED_ADDR_WIDTH + BRAM_ADDR_WIDTH == master.ADDR_WIDTH and use truncation
    // behaviour instead.
    initial
        assert(DATA_WIDTH == master.DATA_WIDTH &&
               UNUSED_ADDR_WIDTH + BRAM_ADDR_WIDTH <= master.ADDR_WIDTH)
        else $fatal(1, "ADDR_WIDTH and/or DATA_WIDTH mismatch");

    // Extract clk and rstn signals from interfaces
    logic clk;
    logic rstn;
    assign clk = master.clk;
    assign rstn = master.rstn;

    //
    // FIFOs necessary to break combinatorial path between AW, W and B channels.
    //

    logic                       aw_valid;
    logic                       aw_ready;
    logic [BRAM_ADDR_WIDTH-1:0] aw_addr;
    fifo #(
        .TYPE         (logic [BRAM_ADDR_WIDTH-1:0]),
        .CAPACITY     (MAX_W_XACT),
        .FALL_THROUGH (W_FALL_THROUGH)
    ) awfifo (
        .clk     (clk),
        .rstn    (rstn),
        .w_valid (master.aw_valid),
        .w_ready (master.aw_ready),
        .w_data  (master.aw_addr[UNUSED_ADDR_WIDTH +: BRAM_ADDR_WIDTH]),
        .r_valid (aw_valid),
        .r_ready (aw_ready),
        .r_data  (aw_addr)
    );

    logic                  w_valid;
    logic                  w_ready;
    logic [DATA_WIDTH-1:0] w_data;
    logic [STRB_WIDTH-1:0] w_strb;
    fifo #(
        .TYPE         (logic [DATA_WIDTH+STRB_WIDTH-1:0]),
        .CAPACITY     (MAX_W_XACT),
        .FALL_THROUGH (W_FALL_THROUGH)
    ) wfifo (
        .clk     (clk),
        .rstn    (rstn),
        .w_valid (master.w_valid),
        .w_ready (master.w_ready),
        .w_data  ({master.w_data, master.w_strb}),
        .r_valid (w_valid),
        .r_ready (w_ready),
        .r_data  ({w_data, w_strb})
    );

    //
    // FIFO necessary to break combinatorial path between AR and R channels.
    //

    logic                       ar_valid;
    logic                       ar_ready;
    logic [BRAM_ADDR_WIDTH-1:0] ar_addr;
    fifo #(
        .TYPE         (logic [BRAM_ADDR_WIDTH-1:0]),
        .CAPACITY     (MAX_R_XACT),
        .FALL_THROUGH (R_FALL_THROUGH)
    ) arfifo (
        .clk     (clk),
        .rstn    (rstn),
        .w_valid (master.ar_valid),
        .w_ready (master.ar_ready),
        .w_data  (master.ar_addr[UNUSED_ADDR_WIDTH +: BRAM_ADDR_WIDTH]),
        .r_valid (ar_valid),
        .r_ready (ar_ready),
        .r_data  (ar_addr)
    );

    //
    // Logic about whether a transaction happens.
    //

    logic can_write;
    logic do_write;
    logic can_read;

    // We can accept write transaction provided that we can place something into B channel next clock cycle.
    // i.e. b_valid is deasserted (i.e. no data in channel) or b_ready is asserted (i.e. data is going to be consumed).
    assign can_write = !master.b_valid || master.b_ready;
    // A transaction can only take place if both AW and W are ready. This looks scary but is actually allowed since
    // we have placed FIFOs for both AW and W channels.
    assign aw_ready  = w_valid && can_write;
    assign w_ready   = aw_valid && can_write;
    // Write transaction happens if all three conditions are met.
    assign do_write  = w_valid && aw_valid && can_write;
    // We prioritise write to read, so read cannot happen if we are going to do a write. Otherwise we can do a read
    // if R channel is available.
    assign can_read  = !master.r_valid || master.r_ready;
    assign ar_ready  = !do_write && can_read;

    //
    // Connection to BRAM
    //

    assign bram_en = do_write || (can_read && ar_valid);
    assign bram_addr = do_write ? aw_addr : ar_addr;
    assign bram_we = do_write ? w_strb : '0;
    assign bram_wrdata = w_data;

    //
    // Write handling logic
    //
    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            master.b_valid <= 1'b0;
        end
        else begin
            if (master.b_valid && master.b_ready) begin
                master.b_valid <= 1'b0;
            end
            if (do_write) begin
                master.b_valid <= 1'b1;
            end
        end

    //
    // Read handling logic
    //

    // As bram_rddata is only guaranteed to be available for 1 cycle, we need additional buffer.
    logic                  r_latched;
    logic [DATA_WIDTH-1:0] r_latched_data;
    assign master.r_data = r_latched ? r_latched_data : bram_rddata;
    assign master.r_resp = axi_common::RESP_OKAY;

    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            r_latched <= 1'b0;
            r_latched_data <= 'x;
            master.r_valid <= 1'b0;
        end
        else begin
            if (master.r_valid) begin
                if (master.r_ready) begin
                    // Buffered data is consumed.
                    r_latched <= 1'b0;
                    r_latched_data <= 'x;
                    master.r_valid <= 1'b0;
                end
                else if (!r_latched) begin
                    // Buffer bram_rddata
                    r_latched <= 1'b1;
                    r_latched_data <= bram_rddata;
                end
            end
            if (ar_valid && ar_ready) begin
                // This will potentially overwrite the `master.r_valid <= 1'b0` above, and is intended.
                master.r_valid <= 1'b1;
            end
        end

endmodule
