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

// Interface that defines an AXI-Lite channel.
interface axi_lite_channel #(
    ADDR_WIDTH = 48,
    DATA_WIDTH = 64
);

    // Static checks of paramters
    initial assert(DATA_WIDTH == 32 || DATA_WIDTH == 64) else $fatal("DATA_WIDTH must be either 32 or 64");

    logic [ADDR_WIDTH-1:0]   aw_addr;
    logic [2:0]              aw_prot;
    logic                    aw_valid;
    logic                    aw_ready;

    logic [ADDR_WIDTH-1:0]   ar_addr;
    logic [2:0]              ar_prot;
    logic                    ar_valid;
    logic                    ar_ready;

    logic [DATA_WIDTH-1:0]   w_data;
    logic [DATA_WIDTH/8-1:0] w_strb;
    logic                    w_valid;
    logic                    w_ready;

    logic [DATA_WIDTH-1:0]   r_data;
    logic [1:0]              r_resp;
    logic                    r_valid;
    logic                    r_ready;

    logic [1:0]              b_resp;
    logic                    b_valid;
    logic                    b_ready;

    modport master (
        output aw_addr,
        output aw_prot,
        output aw_valid,
        input  aw_ready,

        output ar_addr,
        output ar_prot,
        output ar_valid,
        input  ar_ready,

        output w_data,
        output w_strb,
        output w_valid,
        input  w_ready,

        input  r_data,
        input  r_resp,
        input  r_valid,
        output r_ready,

        input  b_resp,
        input  b_valid,
        output b_ready
    );

    modport slave (
        input  aw_addr,
        input  aw_prot,
        input  aw_valid,
        output aw_ready,

        input  ar_addr,
        input  ar_prot,
        input  ar_valid,
        output ar_ready,

        input  w_data,
        input  w_strb,
        input  w_valid,
        output w_ready,

        output r_data,
        output r_resp,
        output r_valid,
        input  r_ready,

        output b_resp,
        output b_valid,
        input  b_ready
    );

endinterface
