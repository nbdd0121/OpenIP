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

// Narrow down a AXI-Stream channel.
module stream_narrower # (
    MASTER_DATA_WIDTH = -1,
    SLAVE_DATA_WIDTH  = -1
) (
    stream_channel.slave  master,
    stream_channel.master slave
);

    localparam MULTIPLE = MASTER_DATA_WIDTH / SLAVE_DATA_WIDTH;
    localparam INDEX_WIDTH = $clog2(MULTIPLE + 1);

    localparam SLAVE_STRB_WIDTH = SLAVE_DATA_WIDTH / 8;

    // Static checks of parameters
    if (MASTER_DATA_WIDTH != master.DATA_WIDTH || SLAVE_DATA_WIDTH != slave.DATA_WIDTH)
        $fatal(1, "Declared DATA_WIDTH does not match actual DATA_WIDTH");

    if (MULTIPLE * SLAVE_DATA_WIDTH != MASTER_DATA_WIDTH)
        $fatal(1, "MASTER_DATA_WIDTH is not multiple of SLAVE_DATA_WIDTH");

    if (MASTER_DATA_WIDTH <= SLAVE_DATA_WIDTH)
        $fatal(1, "MASTER_DATA_WIDTH must be greater than SLAVE_DATA_WIDTH");

    if (master.ID_WIDTH != slave.ID_WIDTH || master.DEST_WIDTH != slave.DEST_WIDTH ||
        master.USER_WIDTH != slave.USER_WIDTH)
        $fatal(1, "Parameter mismatch");

    // Extract clk and rstn signals from interfaces
    logic clk;
    logic rstn;
    assign clk = master.clk;
    assign rstn = master.rstn;

    // High-level description of how this module works:
    // For simplicity and to minimise resource usage this module makes use of the signal stability guarantee from AXI:
    //     if valid is asserted and ready is not asserted, then all signals should stay stable.
    // Thus we essentially connect subwords of the master together with the slave, and acknowledge the transaction to
    // master only when the last subword is transmitted to the slave.
    //
    // Possible future improvement: This module currently may produce a transaction with only null bytes (if master
    // supplies null bytes). Null bytes is not easy to remove as we need to set t_last accordingly as well. We may:
    // * Improve this module by dealing with null bytes
    // * Use a master device that never produces null bytes
    // * Implement a separate null byte remover

    // Unpack data (and strb/keep) of width MASTER_DATA_WIDTH into MULTIPLE number of SLAVE_DATA_WIDTH.
    logic [MULTIPLE-1:0][SLAVE_DATA_WIDTH-1:0] data;
    logic [MULTIPLE-1:0][SLAVE_STRB_WIDTH-1:0] strb;
    logic [MULTIPLE-1:0][SLAVE_STRB_WIDTH-1:0] keep;
    assign data = master.t_data;
    assign strb = master.t_strb;
    assign keep = master.t_keep;

    // Counter which subword of the word to forward to slave.
    logic [INDEX_WIDTH-1:0] index;
    logic last_subword;
    assign last_subword = index == MULTIPLE - 1;

    // Wire all slave signals.
    assign slave.t_data   = data[index];
    assign slave.t_strb   = strb[index];
    assign slave.t_keep   = keep[index];
    // If last_subword is low, then this is definitely not end of packet. For the last_subword, use master.t_last.
    assign slave.t_last   = last_subword ? master.t_last : 1'b0;
    assign slave.t_id     = master.t_id;
    assign slave.t_dest   = master.t_dest;
    assign slave.t_user   = master.t_user;
    assign slave.t_valid  = master.t_valid;
    // Keep t_ready low until the last word so we get stable value in t_data. For last subword we will let master and
    // slave fire transaction simulatenous to move into next word.
    assign master.t_ready = last_subword ? slave.t_ready : 1'b0;

    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            index <= 0;
        end
        else begin
            if (master.t_valid && slave.t_ready) begin
                // Wrap around
                index <= last_subword ? 0 : index + 1;
            end
         end

endmodule
