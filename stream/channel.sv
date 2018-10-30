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

// Interface that defines an AXI-Stream channel.
interface stream_channel #(
    parameter ID_WIDTH   = 1,
    parameter DATA_WIDTH = 64,
    parameter DEST_WIDTH = 1,
    parameter USER_WIDTH = 1
) (
    // Shared clock and reset signals.
    input logic clk,
    input logic rstn
);

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // Static checks of paramters
    initial assert (STRB_WIDTH * 8 == DATA_WIDTH) else $fatal(1, "DATA_WIDTH must be a multiple of 8");

    logic [ID_WIDTH-1:0]   t_id;
    logic [DEST_WIDTH-1:0] t_dest;
    logic [DATA_WIDTH-1:0] t_data;
    logic [STRB_WIDTH-1:0] t_strb;
    logic [STRB_WIDTH-1:0] t_keep;
    logic                  t_last;
    logic [USER_WIDTH-1:0] t_user;
    logic                  t_valid;
    logic                  t_ready;

    modport master (
        input  clk,
        input  rstn,

        output t_id,
        output t_dest,
        output t_data,
        output t_strb,
        output t_keep,
        output t_last,
        output t_user,
        output t_valid,
        input  t_ready
    );

    modport slave (
        input  clk,
        input  rstn,

        input  t_id,
        input  t_dest,
        input  t_data,
        input  t_strb,
        input  t_keep,
        input  t_last,
        input  t_user,
        input  t_valid,
        output t_ready
    );

endinterface
