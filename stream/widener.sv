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

// Widen up a AXI-Stream channel.
module stream_widener # (
    parameter MASTER_DATA_WIDTH = -1,
    parameter SLAVE_DATA_WIDTH  = -1
) (
    stream_channel.slave  master,
    stream_channel.master slave
);

    localparam MULTIPLE = SLAVE_DATA_WIDTH / MASTER_DATA_WIDTH;
    localparam INDEX_WIDTH = $clog2(MULTIPLE + 1);

    localparam MASTER_STRB_WIDTH = MASTER_DATA_WIDTH / 8;

    // Static checks of parameters
    if (MASTER_DATA_WIDTH != master.DATA_WIDTH || SLAVE_DATA_WIDTH != slave.DATA_WIDTH)
        $fatal(1, "Declared DATA_WIDTH does not match actual DATA_WIDTH");

    if (MULTIPLE * MASTER_DATA_WIDTH != SLAVE_DATA_WIDTH)
        $fatal(1, "SLAVE_DATA_WIDTH is not multiple of MASTER_DATA_WIDTH");

    if (SLAVE_DATA_WIDTH <= MASTER_DATA_WIDTH)
        $fatal(1, "SLAVE_DATA_WIDTH must be greater than MASTER_DATA_WIDTH");

    if (master.ID_WIDTH != slave.ID_WIDTH ||
        master.DEST_WIDTH != slave.DEST_WIDTH ||
        master.USER_WIDTH != slave.USER_WIDTH)
        $fatal(1, "Parameter mismatch");

    // Extract clk and rstn signals from interfaces
    logic clk;
    logic rstn;
    assign clk = master.clk;
    assign rstn = master.rstn;

    // High-level description of how this module works:
    // This module is mostly simply accumulating the words and send out when storage is full, except the handling of
    // ID/DEST/LAST signals.
    // In AXI-Stream, bytes are in the same logical stream if the have same ID/DEST set and there're no LAST asserted
    // in between. In order words, if we encounter a subword with LAST asserted, we need to terminate our accumulation
    // and send whatever we have out. If we are in process of accumulation and we see a different ID/DEST it also mean
    // that we need to flush existing bytes out.
    // The implementation here compares incoming ID/DEST from master with stored ID/DEST value, and set ready low if
    // there's a difference. This however violates AXI-Stream's requirement on no combinatorial path between input and
    // output signals of the same channel. Therefore we break the path by adding a register slice in between.

    //
    // Break combinatorial path between master.t_valid/t_id/t_dest and master.t_ready.
    //

    typedef master.pack_t pack_t;
    logic  master_valid;
    logic  master_ready;
    pack_t master_xact;

    regslice #(
        .TYPE    (pack_t),
        .FORWARD (1'b0)
    ) fifo (
        .clk     (clk),
        .rstn    (rstn),
        .w_valid (master.t_valid),
        .w_ready (master.t_ready),
        .w_data  (pack_t'{master.t_id, master.t_dest, master.t_data, master.t_strb, master.t_keep, master.t_last, master.t_user}),
        .r_valid (master_valid),
        .r_ready (master_ready),
        .r_data  (master_xact)
    );

    //
    // Registers for latching and accumulating bytes.
    //

    // Tracking pointer of next index to write into.
    logic [INDEX_WIDTH-1:0] index;
    // Whether our storage is full. This is used to tell two cases where index = 0.
    logic data_full;

    // Pack data (and strb/keep) of MULTIPLE number of MASTER_DATA_WIDTH to a SLAVE_DATA_WIDTH.
    logic [MULTIPLE-1:0][MASTER_DATA_WIDTH-1:0] data;
    logic [MULTIPLE-1:0][MASTER_STRB_WIDTH-1:0] strb;
    logic [MULTIPLE-1:0][MASTER_STRB_WIDTH-1:0] keep;
    logic                                       last;
    logic [master.ID_WIDTH-1:0]                 id;
    logic [master.DEST_WIDTH-1:0]               dest;
    logic [master.USER_WIDTH-1:0]               user;

    // Wire all slave signals.
    assign slave.t_data  = data;
    assign slave.t_strb  = strb;
    assign slave.t_keep  = keep;
    assign slave.t_last  = last;
    assign slave.t_id    = id;
    assign slave.t_dest  = dest;
    assign slave.t_user  = user;
    // We can transmit to slave when we have accumulated all subwords.
    assign slave.t_valid = data_full;

    //
    // ID/DEST mismatch handling logic.
    // If our stored ID/DEST does not match master's input, then we cannot accumulate these together. In this case
    // we need to pause master's input and wait until the storaged data is cleared.
    //

    logic id_dest_mismatch;
    assign id_dest_mismatch = master_valid && (id != master_xact.id || dest != master_xact.dest);

    // We can accept new data if:
    // * Our data storage is not full, and ID/DEST matches
    // * Our data storage is empty or will be empty
    assign master_ready = (!data_full && !id_dest_mismatch) || slave.t_ready || index == 0;

    //
    // Logic for filling into the accumulator
    //

    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            index     <= 0;
            data_full <= 1'b0;
            data      <= 'x;
            strb      <= 'x;
            keep      <= 'x;
            last      <= 1'b0;
            id        <= 'x;
            dest      <= 'x;
            user      <= 'x;
        end
        else begin
            // Transmitted to slave, then clear the full flag.
            if (slave.t_valid && slave.t_ready) begin
                data_full <= 1'b0;
                last      <= 1'b0;
            end

            if (master_valid && master_ready) begin
                // Latch ID/DEST/USER for first subword
                if (index == 0) begin
                    id   <= master_xact.id;
                    dest <= master_xact.dest;
                    user <= master_xact.user;

                    // When we encounter ID/DEST mismatch or early t_last, we want to make sure the unfilled bytes
                    // are all null bytes.
                    strb <= '0;
                    keep <= '0;
                end

                // Fill into corresponding subword.
                data[index] <= master_xact.data;
                strb[index] <= master_xact.strb;
                keep[index] <= master_xact.keep;

                // Adjust index, wrap around and set data_full accordingly.
                if (index == MULTIPLE - 1) begin
                    index     <= 0;
                    data_full <= 1'b1;
                end
                else
                    index     <= index + 1;

                // If last is set, force this whole word to be transmitted, regardless whether it is filled.
                if (master.t_last) begin
                    last      <= 1'b1;
                    index     <= 0;
                    data_full <= 1'b1;
                end
            end
        end

endmodule
