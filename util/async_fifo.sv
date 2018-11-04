/*
 * Copyright (c) 2016-2018, Gary Guo
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

// A general FIFO utility that works on two independent clock domains.
module async_fifo #(
    parameter DATA_WIDTH   = 1,
    parameter type TYPE    = logic [DATA_WIDTH-1:0],
    parameter DEPTH        = 1
) (
    input  logic w_clk,
    input  logic w_rstn,
    input  logic w_valid,
    output logic w_ready,
    input  TYPE  w_data,

    input  logic r_clk,
    input  logic r_rstn,
    output logic r_valid,
    input  logic r_ready,
    output TYPE  r_data
);

    localparam ADDR_WIDTH = $clog2(DEPTH);

    // Static checks of paramters
    initial begin
        assert (2 ** ADDR_WIDTH == DEPTH) else $fatal(1, "FIFO depth should be power of 2");
        assert (DEPTH >= 2) else $fatal(1, "FIFO should have depth of at least 2");
    end

    // High-level description of how this module works:
    // This is an asynchronous FIFO design. It implements paper "Simulation and Synthesis Techniques for Asynchronous
    // FIFO Design (Cumming 2002)".
    // It is pretty a conventional FIFO, except that:
    // * It uses two synchronisers to send pointer to another clock doman.
    // * It utilises gray code for pointers to avoid issues caused by metastablility and multiple bit changes.

    //
    // Gray-code pointers and synchronisers for passing them across clock domain. There width must be ADDR_WIDTH+1 to
    // differentiate full/empty.
    //
    // These signals are synchronised to r_clk
    logic [ADDR_WIDTH:0] readgray, writegray_sync;
    // These signals are synchronised to w_clk
    logic [ADDR_WIDTH:0] writegray, readgray_sync;
    synchronizer #(.DATA_WIDTH(ADDR_WIDTH + 1)) read2write (
        .clk      (w_clk),
        .rstn     (w_rstn),
        .in_async (readgray),
        .out      (readgray_sync)
    );
    synchronizer #(.DATA_WIDTH(ADDR_WIDTH + 1)) write2read (
        .clk      (r_clk),
        .rstn     (r_rstn),
        .in_async (writegray),
        .out      (writegray_sync)
    );

    //
    // Read side
    //
    logic [ADDR_WIDTH:0] readptr;
    logic [ADDR_WIDTH:0] readptr_next, readgray_next;
    logic empty, empty_next;

    // We cannot accept more read when empty.
    assign r_valid = !empty;
    // Adjust pointer according to handshake signals.
    assign readptr_next = r_valid && r_ready ? readptr + 1 : readptr;
    // Gray code conversion.
    binary_to_gray #(.WIDTH(ADDR_WIDTH+1)) readptr_conv (.binary(readptr_next), .gray(readgray_next));
    // Set empty if read/write pointers coincides.
    assign empty_next = readgray_next == writegray_sync;

    always_ff @(posedge r_clk or negedge r_rstn)
        if (!r_rstn) begin
            readptr  <= 0;
            readgray <= 0;
            empty    <= 1'b1;
        end
        else begin
            readptr  <= readptr_next;
            readgray <= readgray_next;
            empty    <= empty_next;
        end

    //
    // Write side
    //
    logic [ADDR_WIDTH:0] writeptr;
    logic [ADDR_WIDTH:0] writeptr_next, writegray_next;
    logic full, full_next;

    // We cannot accept write when full.
    assign w_ready = !full;
    // Adjust pointer according to handshake signals.
    assign writeptr_next = w_valid && w_ready ? writeptr + 1 : writeptr;
    // Gray code conversion.
    binary_to_gray #(.WIDTH(ADDR_WIDTH+1)) writeptr_conv (.binary(writeptr_next), .gray(writegray_next));
    // If writeptr_next - gray_to_binary(readgray_sync) == DEPTH, then we should set it to full.
    // So in binary, the MSB should be different and LSBs should be all equal.
    // So in gray code, the MSB and second MSB should be different, with other bits equal.
    assign full_next = writegray_next[ADDR_WIDTH:ADDR_WIDTH-1] != readgray_sync[ADDR_WIDTH:ADDR_WIDTH-1] &&
        writegray_next[ADDR_WIDTH-2:0] == readgray_sync[ADDR_WIDTH-2:0];

    always_ff @(posedge w_clk or negedge w_rstn)
        if (!w_rstn) begin
            writeptr  <= 0;
            writegray <= 0;
            full      <= 1'b0;
        end
        else begin
            writeptr  <= writeptr_next;
            writegray <= writegray_next;
            full      <= full_next;
        end

    //
    // BRAM instantiation for actually storing the data.
    //
    dual_clock_simple_ram #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    ($bits(TYPE))
    ) bram (
        .a_clk    (r_clk),
        .a_addr   (readptr_next[ADDR_WIDTH-1:0]),
        .a_rddata (r_data),
        .b_clk    (w_clk),
        .b_we     (w_valid && w_ready),
        .b_addr   (writeptr[ADDR_WIDTH-1:0]),
        .b_wrdata (w_data)
    );

endmodule
