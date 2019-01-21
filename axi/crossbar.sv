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

// A crossbar for connecting multiple masters with multiple single slaves.
//
// This module does not perform ID translation. Therefore it is required that
//     slave.ID_WIDTH == master.ID_WIDTH + log2(MASTER_NUM)
// so we can forward result back to the correct master.
//
// ACTIVE_CNT_WIDTH: Decides how many pending transactions can there be with the same ID. Increase the amount will
//     cause wider adders to be used therefore will use more resources.
module axi_crossbar #(
    parameter MASTER_NUM,
    parameter SLAVE_NUM ,
    parameter ADDR_WIDTH,
    parameter [SLAVE_NUM-1:0][ADDR_WIDTH-1:0] BASE = '0,
    parameter [SLAVE_NUM-1:0][ADDR_WIDTH-1:0] MASK = '0
) (
    axi_channel.slave  master[MASTER_NUM],
    axi_channel.master slave [SLAVE_NUM]
);

    for (genvar i = 0; i < MASTER_NUM; i++) begin: demux
        axi_channel #(
            .ID_WIDTH   (master[i].ID_WIDTH),
            .ADDR_WIDTH (ADDR_WIDTH),
            .DATA_WIDTH (master[i].DATA_WIDTH)
        ) master_buf (
            master[i].clk, master[i].rstn
        ), channels[SLAVE_NUM] (
            master[i].clk, master[i].rstn
        );

        axi_demux_raw #(
            .SLAVE_NUM  (SLAVE_NUM),
            .ADDR_WIDTH (ADDR_WIDTH),
            .BASE       (BASE),
            .MASK       (MASK)
        ) demux (master_buf, channels);

        axi_regslice #(
            .AW_MODE (0),
            . W_MODE (0),
            . B_MODE (0),
            .AR_MODE (0),
            . R_MODE (1)
        ) master_slice (master[i], master_buf);
    end

    for (genvar i = 0; i < SLAVE_NUM; i++) begin: mux
        axi_channel #(
            .ID_WIDTH   (master[0].ID_WIDTH),
            .ADDR_WIDTH (ADDR_WIDTH),
            .DATA_WIDTH (slave[i].DATA_WIDTH)
        ) channels[MASTER_NUM] (
            slave[i].clk, slave[i].rstn
        );

        axi_channel #(
            .ID_WIDTH   (slave[i].ID_WIDTH),
            .ADDR_WIDTH (ADDR_WIDTH),
            .DATA_WIDTH (slave[i].DATA_WIDTH)
        ) slave_buf(
            slave[i].clk, slave[i].rstn
        );

        axi_mux_raw #(.MASTER_NUM (MASTER_NUM)) mux (channels, slave_buf);

        axi_regslice #(
            .AW_MODE (0),
            . W_MODE (0),
            . B_MODE (2),
            .AR_MODE (0),
            . R_MODE (2)
        ) slice (slave_buf, slave[i]);

        for (genvar j = 0; j < MASTER_NUM; j++) begin
            axi_join joiner(demux[j].channels[i], channels[j]);
        end
    end

endmodule
