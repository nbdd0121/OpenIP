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
// HIGH_PERFORMANCE: By default this component runs in high performance mode (which means it can respond to one
//     read/write request every cycle). Set this parameter to 0 will turn off high performance mode, reducing a few
//     register usages.
// FALL_THROUGH: By default this controller uses a fall-through FIFO to minimise latency. If this causes you timing
//     issue, it can be turned off by setting it to 0.
module axi_bram_ctrl #(
    parameter ID_WIDTH         = 8,
    parameter ADDR_WIDTH       = 48,
    parameter DATA_WIDTH       = 64,
    parameter BRAM_ADDR_WIDTH  = 16,
    parameter HIGH_PERFORMANCE = 1,
    parameter FALL_THROUGH     = 1
) (
    axi_channel.slave master,

    output                          bram_en,
    output [DATA_WIDTH/8-1:0]       bram_we,
    output [BRAM_ADDR_WIDTH-1:0]    bram_addr,
    output [DATA_WIDTH-1:0]         bram_wrdata,
    input  [DATA_WIDTH-1:0]         bram_rddata
);

    axi_lite_channel #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) channel (
        .clk  (master.clk),
        .rstn (master.rstn)
    );

    axi_to_lite #(
        .ID_WIDTH         (ID_WIDTH),
        .ADDR_WIDTH       (ADDR_WIDTH),
        .HIGH_PERFORMANCE (HIGH_PERFORMANCE)
    ) bridge (
        .master (master),
        .slave  (channel)
    );

    axi_lite_bram_ctrl #(
        .DATA_WIDTH       (DATA_WIDTH),
        .BRAM_ADDR_WIDTH  (BRAM_ADDR_WIDTH),
        .HIGH_PERFORMANCE (HIGH_PERFORMANCE),
        .FALL_THROUGH     (FALL_THROUGH)
    ) controller (
        .master (channel),
        .*
    );

endmodule
