/*
 * Copyright (c) 2018-2019, Gary Guo
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

import axi_common::*;

// A multiplexer that connects multiple masters with a single slave.
//
// This module does not perform ID translation. Therefore it is required that
//     slave.ID_WIDTH == master.ID_WIDTH + log2(MASTER_NUM)
// so we can forward result back to the correct master.
//
// Performance and combinational path:
// * There is 1 latency cycle with 1 bubble cycle on both address channels (best-case 50%
//   channel bandwidth).
// * It inserts 1 multiplexer between master and slave's AW, W and AR channels.
// * It creates a combinatorial path from RID to RREADY and BID to BREADY. It can be addressed by
//   adding register slices for R and B channels on the slave side.

module axi_mux #(
    parameter ID_WIDTH,
    parameter SLAVE_ID_WIDTH,
    parameter ADDR_WIDTH,
    parameter DATA_WIDTH,
    parameter MASTER_NUM
) (
    axi_channel.slave  master[MASTER_NUM],
    axi_channel.master slave
);

    axi_channel #(
        .ID_WIDTH   (SLAVE_ID_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) slave_buf (
        slave.clk,
        slave.rstn
    );

    axi_mux_raw #(.MASTER_NUM(MASTER_NUM)) mux (master, slave_buf);

    axi_regslice #(
        .AW_MODE (0),
        . W_MODE (0),
        . B_MODE (2),
        .AR_MODE (0),
        . R_MODE (2)
    ) slice (slave_buf, slave);

endmodule
