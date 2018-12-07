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

// Connect two AXI-Lite channels together.
module axi_lite_join (
    axi_lite_channel.slave  master,
    axi_lite_channel.master slave
);

    // Static checks of interface matching
    if (master.ADDR_WIDTH != slave.ADDR_WIDTH ||
        master.DATA_WIDTH != slave.DATA_WIDTH)
        $fatal(1, "Interface parameters mismatch");

    assign slave.aw_addr   = master.aw_addr;
    assign slave.aw_prot   = master.aw_prot;
    assign slave.aw_valid  = master.aw_valid;
    assign master.aw_ready = slave.aw_ready;

    assign slave.w_data    = master.w_data;
    assign slave.w_strb    = master.w_strb;
    assign slave.w_valid   = master.w_valid;
    assign master.w_ready  = slave.w_ready;

    assign master.b_resp   = slave.b_resp;
    assign master.b_valid  = slave.b_valid;
    assign slave.b_ready   = master.b_ready;

    assign slave.ar_addr   = master.ar_addr;
    assign slave.ar_prot   = master.ar_prot;
    assign slave.ar_valid  = master.ar_valid;
    assign master.ar_ready = slave.ar_ready;

    assign master.r_data   = slave.r_data;
    assign master.r_resp   = slave.r_resp;
    assign master.r_valid  = slave.r_valid;
    assign slave.r_ready   = master.r_ready;

endmodule
