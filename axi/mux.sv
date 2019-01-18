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
    parameter MASTER_NUM
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

    // For each master interface perform a static check
    for (genvar i = 0; i < MASTER_NUM; i++)
        if (master[i].ID_WIDTH != master[0].ID_WIDTH ||
            master[i].DATA_WIDTH != slave.DATA_WIDTH ||
            master[i].ADDR_WIDTH != slave.ADDR_WIDTH ||
            master[i].AW_USER_WIDTH != slave.AW_USER_WIDTH ||
            master[i].W_USER_WIDTH != slave.W_USER_WIDTH ||
            master[i].B_USER_WIDTH != slave.B_USER_WIDTH ||
            master[i].AR_USER_WIDTH != slave.AR_USER_WIDTH ||
            master[i].R_USER_WIDTH != slave.R_USER_WIDTH)
            $fatal(1, "Parameter mismatch");

    // Extract clk and rstn signals from interfaces
    logic clk;
    logic rstn;
    assign clk = slave.clk;
    assign rstn = slave.rstn;

    //
    // Rearrange wires that need to be multiplexed to be packed.
    //

    typedef slave.aw_pack_t aw_pack_t;
    typedef slave. w_pack_t  w_pack_t;
    typedef slave.ar_pack_t ar_pack_t;
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

    // Connect AW channle of slave.
    assign slave.aw_id     = master_aw[aw_selected].id    ;
    assign slave.aw_addr   = master_aw[aw_selected].addr  ;
    assign slave.aw_len    = master_aw[aw_selected].len   ;
    assign slave.aw_size   = master_aw[aw_selected].size  ;
    assign slave.aw_burst  = master_aw[aw_selected].burst ;
    assign slave.aw_lock   = master_aw[aw_selected].lock  ;
    assign slave.aw_cache  = master_aw[aw_selected].cache ;
    assign slave.aw_prot   = master_aw[aw_selected].prot  ;
    assign slave.aw_qos    = master_aw[aw_selected].qos   ;
    assign slave.aw_region = master_aw[aw_selected].region;
    assign slave.aw_user   = master_aw[aw_selected].user  ;
    assign slave.aw_valid  = aw_locked && master_aw_valid[aw_selected];

    assign slave.w_data  = master_w[aw_selected].data ;
    assign slave.w_strb  = master_w[aw_selected].strb ;
    assign slave.w_last  = master_w[aw_selected].last ;
    assign slave.w_user  = master_w[aw_selected].user ;
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

    assign slave.ar_id     = master_ar[ar_selected].id    ;
    assign slave.ar_addr   = master_ar[ar_selected].addr  ;
    assign slave.ar_len    = master_ar[ar_selected].len   ;
    assign slave.ar_size   = master_ar[ar_selected].size  ;
    assign slave.ar_burst  = master_ar[ar_selected].burst ;
    assign slave.ar_lock   = master_ar[ar_selected].lock  ;
    assign slave.ar_cache  = master_ar[ar_selected].cache ;
    assign slave.ar_prot   = master_ar[ar_selected].prot  ;
    assign slave.ar_qos    = master_ar[ar_selected].qos   ;
    assign slave.ar_region = master_ar[ar_selected].region;
    assign slave.ar_user   = master_ar[ar_selected].user  ;
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

module axi_mux #(
    parameter MASTER_NUM
) (
    axi_channel.slave  master[MASTER_NUM],
    axi_channel.master slave
);

    axi_channel #(
        .ID_WIDTH   (slave.ID_WIDTH),
        .ADDR_WIDTH (slave.ADDR_WIDTH),
        .DATA_WIDTH (slave.DATA_WIDTH)
    ) slave_buf (
        slave.clk,
        slave.rstn
    );

    axi_mux_raw #(.MASTER_NUM(MASTER_NUM)) mux (master, slave_buf);

    assign slave.aw_id     = slave_buf.aw_id;
    assign slave.aw_addr   = slave_buf.aw_addr;
    assign slave.aw_len    = slave_buf.aw_len;
    assign slave.aw_size   = slave_buf.aw_size;
    assign slave.aw_burst  = slave_buf.aw_burst;
    assign slave.aw_lock   = slave_buf.aw_lock;
    assign slave.aw_cache  = slave_buf.aw_cache;
    assign slave.aw_prot   = slave_buf.aw_prot;
    assign slave.aw_qos    = slave_buf.aw_qos;
    assign slave.aw_region = slave_buf.aw_region;
    assign slave.aw_user   = slave_buf.aw_user;
    assign slave.aw_valid  = slave_buf.aw_valid;
    assign slave_buf.aw_ready = slave.aw_ready;

    assign slave.w_data    = slave_buf.w_data;
    assign slave.w_strb    = slave_buf.w_strb;
    assign slave.w_last    = slave_buf.w_last;
    assign slave.w_user    = slave_buf.w_user;
    assign slave.w_valid   = slave_buf.w_valid;
    assign slave_buf.w_ready  = slave.w_ready;

    assign slave.ar_id     = slave_buf.ar_id;
    assign slave.ar_addr   = slave_buf.ar_addr;
    assign slave.ar_len    = slave_buf.ar_len;
    assign slave.ar_size   = slave_buf.ar_size;
    assign slave.ar_burst  = slave_buf.ar_burst;
    assign slave.ar_lock   = slave_buf.ar_lock;
    assign slave.ar_cache  = slave_buf.ar_cache;
    assign slave.ar_prot   = slave_buf.ar_prot;
    assign slave.ar_qos    = slave_buf.ar_qos;
    assign slave.ar_region = slave_buf.ar_region;
    assign slave.ar_user   = slave_buf.ar_user;
    assign slave.ar_valid  = slave_buf.ar_valid;
    assign slave_buf.ar_ready = slave.ar_ready;

    //
    // B channel
    //

    typedef slave.b_pack_t b_pack_t;
    regslice #(
        .TYPE    (b_pack_t),
        .FORWARD (1'b0)
    ) bfifo (
        .clk     (slave.clk),
        .rstn    (slave.rstn),
        .w_valid (slave.b_valid),
        .w_ready (slave.b_ready),
        .w_data  (b_pack_t'{slave.b_id, slave.b_resp, slave.b_user}),
        .r_valid (slave_buf.b_valid),
        .r_ready (slave_buf.b_ready),
        .r_data  ({slave_buf.b_id, slave_buf.b_resp, slave_buf.b_user})
    );

    //
    // R channel
    //

    typedef slave.r_pack_t r_pack_t;
    regslice #(
        .TYPE    (r_pack_t),
        .FORWARD (1'b0)
    ) rfifo (
        .clk     (slave.clk),
        .rstn    (slave.rstn),
        .w_valid (slave.r_valid),
        .w_ready (slave.r_ready),
        .w_data  (r_pack_t'{slave.r_id, slave.r_data, slave.r_resp, slave.r_last, slave.r_user}),
        .r_valid (slave_buf.r_valid),
        .r_ready (slave_buf.r_ready),
        .r_data  ({slave_buf.r_id, slave_buf.r_data, slave_buf.r_resp, slave_buf.r_last, slave_buf.r_user})
    );

endmodule
