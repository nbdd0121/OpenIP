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

module axi_demux #(
    parameter SLAVE_NUM,
    // Ideally we would like to remove this but it is required by type of BASE and MASK
    parameter ID_WIDTH,
    parameter SLAVE_ID_WIDTH,
    parameter ADDR_WIDTH,
    parameter DATA_WIDTH,
    parameter ACTIVE_CNT_WIDTH = 4
) (
    axi_channel.slave  master,
    axi_channel.master slave [SLAVE_NUM],
    logic [SLAVE_NUM-1:0][ADDR_WIDTH-1:0] BASE,
    logic [SLAVE_NUM-1:0][ADDR_WIDTH-1:0] MASK
);

    axi_channel #(
        .ID_WIDTH   (ID_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) master_buf (
        master.clk,
        master.rstn
    ), slave_buf [SLAVE_NUM] (
        master.clk,
        master.rstn
    );

    axi_demux_raw #(
        .SLAVE_NUM        (SLAVE_NUM),
        .ADDR_WIDTH       (ADDR_WIDTH),
        .ACTIVE_CNT_WIDTH (ACTIVE_CNT_WIDTH)
    ) mux (.master(master_buf), .slave(slave_buf), .BASE, .MASK);

    axi_regslice #(
        .AW_MODE (0),
        . W_MODE (0),
        . B_MODE (0),
        .AR_MODE (0),
        . R_MODE (1)
    ) master_slice (master, master_buf);

    for (genvar i = 0; i < SLAVE_NUM; i++) begin: slave_slice
        axi_regslice #(
            .AW_MODE (0),
            . W_MODE (0),
            . B_MODE (0),
            .AR_MODE (0),
            . R_MODE (2)
        ) slice (slave_buf[i], slave[i]);
    end

endmodule
