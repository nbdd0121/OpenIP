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

module axi_mux_raw #(
    parameter MASTER_NUM = 1
) (
    axi_channel.slave  master[MASTER_NUM],
    axi_channel.master slave
);

    localparam MASTER_WIDTH = $clog2(MASTER_NUM);

    // Overall static check. As we don't perform ID translation in this mux, we impose a requirement on ID widths.
    if (master[0].ID_WIDTH + MASTER_WIDTH != slave.ID_WIDTH)
        $fatal(
            1, "slave.ID_WIDTH (%d) must be equal to master.ID_WIDTH (%d) + MASTER_WIDTH (%d)",
            slave.ID_WIDTH, master[0].ID_WIDTH, MASTER_WIDTH
        );

    // Static checks of interface matching
    if (master[0].DATA_WIDTH != slave.DATA_WIDTH ||
        master[0].ADDR_WIDTH != slave.ADDR_WIDTH ||
        master[0].AW_USER_WIDTH != slave.AW_USER_WIDTH ||
        master[0].W_USER_WIDTH != slave.W_USER_WIDTH ||
        master[0].B_USER_WIDTH != slave.B_USER_WIDTH ||
        master[0].AR_USER_WIDTH != slave.AR_USER_WIDTH ||
        master[0].R_USER_WIDTH != slave.R_USER_WIDTH)
        $fatal(1, "Parameter mismatch");

    // Extract clk and rstn signals from interfaces
    logic clk;
    logic rstn;
    assign clk = slave.clk;
    assign rstn = slave.rstn;

    //
    // Rearrange wires that need to be multiplexed to be packed.
    //

`define ID_WIDTH (slave.ID_WIDTH)
`define ADDR_WIDTH (slave.ADDR_WIDTH)
`define DATA_WIDTH (slave.DATA_WIDTH)
`define AW_USER_WIDTH (slave.AW_USER_WIDTH)
`define W_USER_WIDTH (slave.W_USER_WIDTH)
`define B_USER_WIDTH (slave.B_USER_WIDTH)
`define AR_USER_WIDTH (slave.AR_USER_WIDTH)
`define R_USER_WIDTH (slave.R_USER_WIDTH)
`include "typedef.vh"
   
/*
    typedef slave.aw_pack_t aw_pack_t;
    typedef slave. w_pack_t  w_pack_t;
    typedef slave.ar_pack_t ar_pack_t;
*/ 
    aw_pack_t [MASTER_NUM-1:0] master_aw;
    logic     [MASTER_NUM-1:0] master_aw_valid;
    w_pack_t  [MASTER_NUM-1:0] master_w;
    logic     [MASTER_NUM-1:0] master_w_valid;
    logic     [MASTER_NUM-1:0] master_b_ready;
    ar_pack_t [MASTER_NUM-1:0] master_ar;
    logic     [MASTER_NUM-1:0] master_ar_valid;
    logic     [MASTER_NUM-1:0] master_r_ready;

    for (genvar i = 0; i < MASTER_NUM; i++) begin: pack
        assign master_aw[i] = aw_pack_t'{
            {i, master[i].aw_id}, master[i].aw_addr, master[i].aw_len, master[i].aw_size, master[i].aw_burst,
            master[i].aw_lock, master[i].aw_cache, master[i].aw_prot, master[i].aw_qos, master[i].aw_region,
            master[i].aw_user
        };
        assign master_aw_valid[i] = master[i].aw_valid;
        assign master_w[i] = w_pack_t'{master[i].w_data, master[i].w_strb, master[i].w_last, master[i].w_user};
        assign master_w_valid[i] = master[i].w_valid;
        assign master_b_ready[i] = master[i].b_ready;
        assign master_ar[i] = ar_pack_t'{
            {i, master[i].ar_id}, master[i].ar_addr, master[i].ar_len, master[i].ar_size, master[i].ar_burst,
            master[i].ar_lock, master[i].ar_cache, master[i].ar_prot, master[i].ar_qos, master[i].ar_region,
            master[i].ar_user
        };
        assign master_ar_valid[i] = master[i].ar_valid;
        assign master_r_ready[i] = master[i].r_ready;
    end

    //
    // Multiplex AW channel using round-robin arbiter. After arbitration, keep both AW and W channel connected to slave
    // until w_last is transmitted to slave. This is a requirement of AXI as write request interleaving is not allowed.
    //

    logic [MASTER_NUM-1:0]   aw_arb_grant;
    logic [MASTER_WIDTH-1:0] aw_arb_grant_bin;
    logic                    aw_locked;
    logic                    w_locked;
    logic [MASTER_WIDTH-1:0] aw_selected;

    round_robin_arbiter #(.WIDTH(MASTER_NUM)) aw_arb (
        .clk     (clk),
        .rstn    (rstn),
        .enable  (!aw_locked && !w_locked),
        .request (master_aw_valid),
        .grant   (aw_arb_grant)
    );

    onehot_to_binary #(.ONEHOT_WIDTH(MASTER_NUM)) aw_one2bin (aw_arb_grant, aw_arb_grant_bin);

    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            aw_locked   <= 1'b0;
            w_locked    <= 1'b0;
            aw_selected <= '0;
        end
        else begin
            if (aw_locked || w_locked) begin
                // We don't need to check slave.aw_valid, as it is always 1 when aw_locked is 1.
                if (/* slave.aw_valid && */ slave.aw_ready) begin
                    aw_locked <= 1'b0;
                end
                if (slave.w_last && slave.w_valid && slave.w_ready) begin
                    w_locked <= 1'b0;
                end
            end
            else if (aw_arb_grant) begin
                aw_locked   <= 1'b1;
                w_locked    <= 1'b1;
                aw_selected <= aw_arb_grant_bin;
            end
        end

    // Connect AW channel of slave.
    // A note on this coding pattern:
    // Orginally the code here writes:
    //   assign slave.aw_id     = master_aw[aw_selected].id    ;
    // However QuestaSim incorrectly assumes that this means slave.aw_id is only sensitive to
    // aw_selected but not sensitive to master_aw which causes issues in simulation. Separating
    // this out to two assignments however corrected this issue. Until the bug is fixed we will
    // need to stick to this pattern.
    aw_pack_t master_aw_selected;
    assign master_aw_selected = master_aw[aw_selected];
    assign slave.aw_id     = master_aw_selected.id    ;
    assign slave.aw_addr   = master_aw_selected.addr  ;
    assign slave.aw_len    = master_aw_selected.len   ;
    assign slave.aw_size   = master_aw_selected.size  ;
    assign slave.aw_burst  = master_aw_selected.burst ;
    assign slave.aw_lock   = master_aw_selected.lock  ;
    assign slave.aw_cache  = master_aw_selected.cache ;
    assign slave.aw_prot   = master_aw_selected.prot  ;
    assign slave.aw_qos    = master_aw_selected.qos   ;
    assign slave.aw_region = master_aw_selected.region;
    assign slave.aw_user   = master_aw_selected.user  ;
    assign slave.aw_valid  = aw_locked && master_aw_valid[aw_selected];

    w_pack_t master_w_selected;
    assign master_w_selected = master_w[aw_selected];
    assign slave.w_data  = master_w_selected.data ;
    assign slave.w_strb  = master_w_selected.strb ;
    assign slave.w_last  = master_w_selected.last ;
    assign slave.w_user  = master_w_selected.user ;
    assign slave.w_valid = w_locked && master_w_valid[aw_selected];

    for (genvar i = 0; i < MASTER_NUM; i++) begin: aw
        assign master[i].aw_ready = aw_locked && aw_selected == i && slave.aw_ready;
        assign master[i].w_ready  = w_locked  && aw_selected == i && slave.w_ready;
    end

    //
    // Demux B channel
    //
    for (genvar i = 0; i < MASTER_NUM; i++) begin: b
        assign master[i].b_id    = slave.b_id  ;
        assign master[i].b_resp  = slave.b_resp;
        assign master[i].b_user  = slave.b_user;
        assign master[i].b_valid = slave.b_valid && slave.b_id[slave.ID_WIDTH-1 -: MASTER_WIDTH] == i;
    end

    // This creates a combinatorial path between slave.b_id to slave.b_ready
    assign slave.b_ready = master_b_ready[slave.b_id[slave.ID_WIDTH-1 -: MASTER_WIDTH]];

    //
    // Mux AR channel
    //
    logic [MASTER_NUM-1:0]   ar_arb_grant;
    logic [MASTER_WIDTH-1:0] ar_arb_grant_bin;
    logic                    ar_locked;
    logic [MASTER_WIDTH-1:0] ar_selected;

    round_robin_arbiter #(.WIDTH(MASTER_NUM)) ar_arb (
        .clk     (clk),
        .rstn    (rstn),
        .enable  (!ar_locked),
        .request (master_ar_valid),
        .grant   (ar_arb_grant)
    );

    onehot_to_binary #(.ONEHOT_WIDTH(MASTER_NUM)) ar_one2bin (ar_arb_grant, ar_arb_grant_bin);

    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            ar_locked <= 1'b0;
            ar_selected <= '0;
        end
        else begin
            if (ar_locked) begin
                if (/* slave.ar_valid && */ slave.ar_ready) begin
                    ar_locked <= 1'b0;
                end
            end
            else if (ar_arb_grant) begin
                ar_locked   <= 1'b1;
                ar_selected <= ar_arb_grant_bin;
            end
        end

    ar_pack_t master_ar_selected;
    assign master_ar_selected = master_ar[ar_selected];
    assign slave.ar_id     = master_ar_selected.id    ;
    assign slave.ar_addr   = master_ar_selected.addr  ;
    assign slave.ar_len    = master_ar_selected.len   ;
    assign slave.ar_size   = master_ar_selected.size  ;
    assign slave.ar_burst  = master_ar_selected.burst ;
    assign slave.ar_lock   = master_ar_selected.lock  ;
    assign slave.ar_cache  = master_ar_selected.cache ;
    assign slave.ar_prot   = master_ar_selected.prot  ;
    assign slave.ar_qos    = master_ar_selected.qos   ;
    assign slave.ar_region = master_ar_selected.region;
    assign slave.ar_user   = master_ar_selected.user  ;
    assign slave.ar_valid  = ar_locked && master_ar_valid[ar_selected];

    for (genvar i = 0; i < MASTER_NUM; i++) begin: ar
        assign master[i].ar_ready = ar_locked && ar_selected == i && slave.ar_ready;
    end

    //
    // Demux R channel
    //

    for (genvar i = 0; i < MASTER_NUM; i++) begin: r
        assign master[i].r_id    = slave.r_id  ;
        assign master[i].r_data  = slave.r_data;
        assign master[i].r_resp  = slave.r_resp;
        assign master[i].r_last  = slave.r_last;
        assign master[i].r_user  = slave.r_user;
        assign master[i].r_valid = slave.r_valid && slave.r_id[slave.ID_WIDTH-1 -: MASTER_WIDTH] == i;
    end

    // This creates a combinatorial path between slave.r_id to slave.r_ready
    assign slave.r_ready = master_r_ready[slave.r_id[slave.ID_WIDTH-1 -: MASTER_WIDTH]];

endmodule
