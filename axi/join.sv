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

// Connect two AXI channels together.
module axi_join (
    axi_channel.slave  master,
    axi_channel.master slave
);

    // Static checks of interface matching.
    // Normally parameters should match exactly, but the following operations are legal:
    // * Widen ID_WIDTH
    // * Widen or narrow ADDR_WIDTH (this would be useful for connecting componenets after demux)
    // * Widen DATA_WIDTH
    if (master.ID_WIDTH > slave.ID_WIDTH ||
        master.DATA_WIDTH > slave.DATA_WIDTH ||
        master.AW_USER_WIDTH != slave.AW_USER_WIDTH ||
        master.W_USER_WIDTH != slave.W_USER_WIDTH ||
        master.B_USER_WIDTH != slave.B_USER_WIDTH ||
        master.AR_USER_WIDTH != slave.AR_USER_WIDTH ||
        master.R_USER_WIDTH != slave.R_USER_WIDTH)
        $fatal(1, "Interface parameters mismatch");

    assign slave.aw_id     = master.aw_id;
    assign slave.aw_addr   = master.aw_addr;
    assign slave.aw_len    = master.aw_len;
    assign slave.aw_size   = master.aw_size;
    assign slave.aw_burst  = master.aw_burst;
    assign slave.aw_lock   = master.aw_lock;
    assign slave.aw_cache  = master.aw_cache;
    assign slave.aw_prot   = master.aw_prot;
    assign slave.aw_qos    = master.aw_qos;
    assign slave.aw_region = master.aw_region;
    assign slave.aw_user   = master.aw_user;
    assign slave.aw_valid  = master.aw_valid;
    assign master.aw_ready = slave.aw_ready;

    assign slave.w_data    = master.w_data;
    assign slave.w_strb    = master.w_strb;
    assign slave.w_last    = master.w_last;
    assign slave.w_user    = master.w_user;
    assign slave.w_valid   = master.w_valid;
    assign master.w_ready  = slave.w_ready;

    assign master.b_id     = slave.b_id;
    assign master.b_resp   = slave.b_resp;
    assign master.b_user   = slave.b_user;
    assign master.b_valid  = slave.b_valid;
    assign slave.b_ready   = master.b_ready;

    assign slave.ar_id     = master.ar_id;
    assign slave.ar_addr   = master.ar_addr;
    assign slave.ar_len    = master.ar_len;
    assign slave.ar_size   = master.ar_size;
    assign slave.ar_burst  = master.ar_burst;
    assign slave.ar_lock   = master.ar_lock;
    assign slave.ar_cache  = master.ar_cache;
    assign slave.ar_prot   = master.ar_prot;
    assign slave.ar_qos    = master.ar_qos;
    assign slave.ar_region = master.ar_region;
    assign slave.ar_user   = master.ar_user;
    assign slave.ar_valid  = master.ar_valid;
    assign master.ar_ready = slave.ar_ready;

    assign master.r_id     = slave.r_id;
    assign master.r_data   = slave.r_data;
    assign master.r_resp   = slave.r_resp;
    assign master.r_last   = slave.r_last;
    assign master.r_user   = slave.r_user;
    assign master.r_valid  = slave.r_valid;
    assign slave.r_ready   = master.r_ready;

endmodule
