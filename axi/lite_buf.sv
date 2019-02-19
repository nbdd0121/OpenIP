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

import axi_common::*;

// A buffer for AXI-Lite interface.
module axi_lite_buf #(
    parameter DEPTH         = 1
) (
    axi_lite_channel.slave  master,
    axi_lite_channel.master slave
);

    // Static checks of interface matching
    if (master.ADDR_WIDTH != slave.ADDR_WIDTH || master.DATA_WIDTH != slave.DATA_WIDTH)
        $fatal(1, "Parameter mismatch");

    //
    // AW channel
    //

`define ID_WIDTH (master.ID_WIDTH)
`define ADDR_WIDTH (master.ADDR_WIDTH)
`define DATA_WIDTH (master.DATA_WIDTH)
`define AW_USER_WIDTH (master.AW_USER_WIDTH)
`define W_USER_WIDTH (master.W_USER_WIDTH)
`define B_USER_WIDTH (master.B_USER_WIDTH)
`define AR_USER_WIDTH (master.AR_USER_WIDTH)
`define R_USER_WIDTH (master.R_USER_WIDTH)
`include "typedef.vh"
//    typedef master.ax_pack_t ax_pack_t;
    general_fifo #(
        .TYPE  (ax_pack_t),
        .DEPTH (DEPTH)
    ) awfifo (
        .clk     (master.clk),
        .rstn    (master.rstn),
        .w_valid (master.aw_valid),
        .w_ready (master.aw_ready),
        .w_data  (ax_pack_t'{master.aw_addr, master.aw_prot}),
        .r_valid (slave.aw_valid),
        .r_ready (slave.aw_ready),
        .r_data  ({slave.aw_addr, slave.aw_prot})
    );

    //
    // W channel
    //

//    typedef master.w_pack_t w_pack_t;
    general_fifo #(
        .TYPE  (w_pack_t),
        .DEPTH (DEPTH)
    ) wfifo (
        .clk     (master.clk),
        .rstn    (master.rstn),
        .w_valid (master.w_valid),
        .w_ready (master.w_ready),
        .w_data  (lw_pack_t'{master.w_data, master.w_strb}),
        .r_valid (slave.w_valid),
        .r_ready (slave.w_ready),
        .r_data  ({slave.w_data, slave.w_strb})
    );

    //
    // B channel
    //

    general_fifo #(
        .TYPE  (resp_t),
        .DEPTH (DEPTH)
    ) bfifo (
        .clk     (master.clk),
        .rstn    (master.rstn),
        .w_valid (slave.b_valid),
        .w_ready (slave.b_ready),
        .w_data  (slave.b_resp),
        .r_valid (master.b_valid),
        .r_ready (master.b_ready),
        .r_data  (master.b_resp)
    );

    //
    // AR channel
    //

    general_fifo #(
        .TYPE  (ax_pack_t),
        .DEPTH (DEPTH)
    ) arfifo (
        .clk     (master.clk),
        .rstn    (master.rstn),
        .w_valid (master.ar_valid),
        .w_ready (master.ar_ready),
        .w_data  (ax_pack_t'{master.ar_addr, master.ar_prot}),
        .r_valid (slave.ar_valid),
        .r_ready (slave.ar_ready),
        .r_data  ({slave.ar_addr, slave.ar_prot})
    );

    //
    // R channel
    //

//    typedef master.r_pack_t r_pack_t;
    general_fifo #(
        .TYPE  (r_pack_t),
        .DEPTH (DEPTH)
    ) rfifo (
        .clk     (master.clk),
        .rstn    (master.rstn),
        .w_valid (slave.r_valid),
        .w_ready (slave.r_ready),
        .w_data  (lr_pack_t'{slave.r_data, slave.r_resp}),
        .r_valid (master.r_valid),
        .r_ready (master.r_ready),
        .r_data  ({master.r_data, master.r_resp})
    );

endmodule
