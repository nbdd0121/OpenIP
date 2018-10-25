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

// A bridge that connects an AXI-Lite master with an AXI slave. It requires address and data width to match and does
// not perform width conversion.
module axi_from_lite #(
    ADDR_WIDTH = 48,
    DATA_WIDTH = 64
) (
    axi_lite_channel.slave master,
    axi_channel.master     slave
);

    // Static checks of interface matching
    initial
        assert(master.ADDR_WIDTH == slave.ADDR_WIDTH && master.DATA_WIDTH == slave.DATA_WIDTH)
        else $fatal("ADDR_WIDTH and/or DATA_WIDTH of AXI and AXI-Lite port mismatch");

    // AXI-Lite does not support AXI IDs, so all accesses use a single fixed ID value.
    assign slave.aw_id     = '0;
    assign slave.aw_addr   = master.aw_addr;
    // AXI-Lite has burst length defined to be 1.
    assign slave.aw_len    = 8'h0;
    // All accesses are defined to be of full width.
    assign slave.aw_size   = $clog2(DATA_WIDTH / 8);
    // This burst type has no meaning because burst length is 1, but we still prefer to fix it at INCR.
    assign slave.aw_burst  = axi_common::BURST_INCR;
    // All accesses are defined as normal access.
    assign slave.aw_lock   = 1'b0;
    // All accesses are defined to be non-modifiable, non-bufferable.
    assign slave.aw_cache  = 4'h0;
    assign slave.aw_prot   = master.aw_prot;
    // QoS, Region and User signals do not exist in AXI-Lite and they are hardwired to zero.
    assign slave.aw_qos    = 4'h0;
    assign slave.aw_region = 4'h0;
    assign slave.aw_user   = '0;
    assign slave.aw_valid  = master.aw_valid;
    assign master.aw_ready = slave.aw_ready;  

    assign slave.ar_id     = '0;
    assign slave.ar_addr   = master.ar_addr;
    assign slave.ar_len    = 8'h0;
    assign slave.ar_size   = $clog2(DATA_WIDTH / 8);
    assign slave.ar_burst  = axi_common::BURST_INCR;
    assign slave.ar_lock   = 1'b0;
    assign slave.ar_cache  = 4'h0;
    assign slave.ar_prot   = master.ar_prot;
    assign slave.ar_qos    = 4'h0;
    assign slave.ar_region = 4'h0;
    assign slave.ar_user   = '0;
    assign slave.ar_valid  = master.ar_valid;
    assign master.ar_ready = slave.ar_ready;

    assign slave.w_data    = master.w_data;
    assign slave.w_strb    = master.w_strb;
    // All bursts are defined to be of length 1, so last signal is always asserted.
    assign slave.w_last    = 1'b1;
    assign slave.w_user    = '0;
    assign slave.w_valid   = master.w_valid;
    assign master.w_ready  = slave.w_ready;

    assign master.r_data = slave.r_data;
    // r_last is discarded
    // r_id is discarded
    assign master.r_resp = slave.r_resp;
    // r_user is discarded
    assign master.r_valid = slave.r_valid;
    assign slave.r_ready = master.r_ready;

    // b_id is discarded
    assign master.b_resp = slave.b_resp;
    // b_user is discarded
    assign master.b_valid = slave.b_valid;
    assign slave.b_ready = master.b_ready;

endmodule
