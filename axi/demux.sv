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

// A demultiplexer that connects a single master with multiple slaves.
//
// Performance and combinational path:
// * There is 1 latency cycle with 1 bubble cycle on AW/W/B/AR channels
// * It inserts 1 multiplexer between master and slave's AW, W, B and AR channels' READY signals.
// * It creates combinational path from master.r_ready to master.r_valid and from slave[i].r_valid
//   to slave[i].r_ready which needs to be broken.
//
// ACTIVE_CNT_WIDTH: Decides how many pending transactions can there be with the same ID. Increase the amount will
//     cause wider adders to be used therefore will use more resources.
module axi_demux_raw #(
    parameter SLAVE_NUM,
    // Ideally we would like to remove this but it is required by type of BASE and MASK
    parameter ADDR_WIDTH,
    parameter ACTIVE_CNT_WIDTH = 4,
    parameter [SLAVE_NUM-1:0][ADDR_WIDTH-1:0] BASE = '0,
    parameter [SLAVE_NUM-1:0][ADDR_WIDTH-1:0] MASK = '0
) (
    axi_channel.slave  master,
    axi_channel.master slave [SLAVE_NUM]
);

    localparam SLAVE_WIDTH = $clog2(SLAVE_NUM);

    // Static checks of interface matching
    if (master.ADDR_WIDTH != ADDR_WIDTH ||
        master.ID_WIDTH != slave[0].ID_WIDTH ||
        master.DATA_WIDTH != slave[0].DATA_WIDTH ||
        master.ADDR_WIDTH != slave[0].ADDR_WIDTH ||
        master.AW_USER_WIDTH != slave[0].AW_USER_WIDTH ||
        master.W_USER_WIDTH != slave[0].W_USER_WIDTH ||
        master.B_USER_WIDTH != slave[0].B_USER_WIDTH ||
        master.AR_USER_WIDTH != slave[0].AR_USER_WIDTH ||
        master.R_USER_WIDTH != slave[0].R_USER_WIDTH)
        $fatal(1, "Parameter mismatch");

    // Extract clk and rstn signals from interfaces
    logic clk;
    logic rstn;
    assign clk = master.clk;
    assign rstn = master.rstn;

    //
    // Rearrange wires that need to be multiplexed to be packed.
    //

    typedef master.b_pack_t b_pack_t;
    typedef master.r_pack_t r_pack_t;
    logic     [SLAVE_NUM-1:0] slave_aw_ready;
    logic     [SLAVE_NUM-1:0] slave_w_ready;
    b_pack_t  [SLAVE_NUM-1:0] slave_b;
    logic     [SLAVE_NUM-1:0] slave_b_valid;
    logic     [SLAVE_NUM-1:0] slave_ar_ready;
    r_pack_t  [SLAVE_NUM-1:0] slave_r;
    logic     [SLAVE_NUM-1:0] slave_r_valid;

    for (genvar i = 0; i < SLAVE_NUM; i++) begin: pack
        assign slave_aw_ready[i] = slave[i].aw_ready;
        assign slave_w_ready[i] = slave[i].w_ready;
        assign slave_b[i] = b_pack_t'{slave[i].b_id, slave[i].b_resp, slave[i].b_user};
        assign slave_b_valid[i] = slave[i].b_valid;
        assign slave_ar_ready[i] = slave[i].ar_ready;
        assign slave_r[i] = r_pack_t'{
            slave[i].r_id, slave[i].r_data, slave[i].r_resp, slave[i].r_last, slave[i].r_user
        };
        assign slave_r_valid[i] = slave[i].r_valid;
    end

    // High-level description of how this module works:
    // We will determine which slave the address request get send to by checking again BASE and MASK. For responses, we
    // will perform arbitration and forward them to master.
    //
    // As AXI disallows reordering of transactions of the same ID, we must not send transasctions of the same ID to
    // different slaves - otherwise we cannot guarantee the ordering.
    //
    // We achieve this ordering guarantee by storing a table of IDs and the slave that the transaction sends to. Each
    // mapping will also have a counter of how many transactions are pending. If the value reaches zero then we will
    // disable the mapping. It is very similar to the ID remapper.

    //
    // Address BASE & MASK matching
    //
    // These values indicate whether the address matches BASE & MASK of a specific slave. This value should only be
    // used when corresponding valid signal is asserted. If nothing matches, aw_match and ar_match will be all-zero but
    // aw_match_bin and ar_match_bin will give 0, corresponding to the first slave.
    logic [SLAVE_NUM-1:0] aw_match;
    logic [SLAVE_NUM-1:0] ar_match;
    logic [SLAVE_WIDTH-1:0] aw_match_bin;
    logic [SLAVE_WIDTH-1:0] ar_match_bin;

    for (genvar i = 0; i < SLAVE_NUM; i++) begin
        assign aw_match[i] = MASK[i] != 0 && (master.aw_addr &~ MASK[i]) == BASE[i];
        assign ar_match[i] = MASK[i] != 0 && (master.ar_addr &~ MASK[i]) == BASE[i];
    end

    onehot_to_binary #(.ONEHOT_WIDTH(SLAVE_NUM)) aw_one2bin (aw_match, aw_match_bin);
    onehot_to_binary #(.ONEHOT_WIDTH(SLAVE_NUM)) ar_one2bin (ar_match, ar_match_bin);

    //
    // Arbitration of B and R channels.
    //
    logic                   b_arb_enable;
    logic [SLAVE_NUM-1:0]   b_arb_grant;
    logic [SLAVE_WIDTH-1:0] b_arb_grant_bin;
    logic                   r_arb_enable;
    logic [SLAVE_NUM-1:0]   r_arb_grant;
    logic [SLAVE_WIDTH-1:0] r_arb_grant_bin;

    round_robin_arbiter #(.WIDTH(SLAVE_NUM)) b_arb (
        .clk     (clk),
        .rstn    (rstn),
        .enable  (b_arb_enable),
        .request (slave_b_valid),
        .grant   (b_arb_grant)
    );
    round_robin_arbiter #(.WIDTH(SLAVE_NUM)) r_arb (
        .clk     (clk),
        .rstn    (rstn),
        .enable  (r_arb_enable),
        .request (slave_r_valid),
        .grant   (r_arb_grant)
    );

    onehot_to_binary #(.ONEHOT_WIDTH(SLAVE_NUM)) b_one2bin (b_arb_grant, b_arb_grant_bin);
    onehot_to_binary #(.ONEHOT_WIDTH(SLAVE_NUM)) r_one2bin (r_arb_grant, r_arb_grant_bin);

    //
    // Definition of mapping entry
    //

    typedef struct packed {
        logic [SLAVE_WIDTH-1:0] active_slave;
        // We can issue at most 2**ACTIVE_CNT_WIDTH transactions for the same ID. We will stall if this is exceeded.
        logic [ACTIVE_CNT_WIDTH-1:0] active_cnt;
    } mapping_t;

    //
    // Writing part
    //

    mapping_t [2**master.ID_WIDTH-1:0] write_map;

    //
    // Mapping lookup and update logic
    //
    mapping_t aw_lookup;
    assign aw_lookup = write_map[master.aw_id];

    // We can forward the request if the current mapping is not active, or we will use the same mapping and active_cnt
    // hasn't reached the limit.
    logic aw_forward;
    assign aw_forward = master.aw_valid && (aw_lookup.active_cnt == 0 ||
        (aw_lookup.active_slave == aw_match_bin &&
         aw_lookup.active_cnt != 2**ACTIVE_CNT_WIDTH-1));

    // Whether we should increase active_cnt or decrease it.
    logic [2**master.ID_WIDTH-1:0] w_cnt_incr;
    logic [2**master.ID_WIDTH-1:0] w_cnt_decr;

    // A note on this coding pattern:
    // Orginally the code here uses always_comb with a for loop here.
    // However QuestaSim will handle signals within interfaces incorrectly if they're placed in
    // always_comb block, possibly causing glitches in simulation. We need to avoid reading
    // interface signals from always_comb code until the issue is resolved.
    for (genvar i = 0; i < 2**master.ID_WIDTH; i++) begin
        assign w_cnt_decr[i] = master.b_id == i && master.b_valid && master.b_ready;
        assign w_cnt_incr[i] = master.aw_id == i && master.aw_valid && master.aw_ready;
    end

    // Actually update the mappings
    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            for (int i = 0; i < 2**master.ID_WIDTH; i++)
                write_map[i] <= mapping_t'('0);
        end
        else begin
            for (int i = 0; i < 2**master.ID_WIDTH; i++) begin
                if (w_cnt_incr[i]) begin
                    write_map[i].active_slave <= aw_match_bin;
                    if (!w_cnt_decr[i]) write_map[i].active_cnt <= write_map[i].active_cnt + 1;
                end
                else if (w_cnt_decr[i]) begin
                    write_map[i].active_cnt <= write_map[i].active_cnt - 1;
                end
            end
        end

    // When we have decided a slave we need to make sure we keep AW connected until the handshake
    // happens, and W connected to the slave until we see w_last. They need separate lock signals
    // because we AXI does not enforce an ordering between these two channels.
    logic aw_locked;
    logic w_locked;
    logic [SLAVE_WIDTH-1:0] aw_selected;

    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            aw_locked   <= 1'b0;
            w_locked    <= 1'b0;
            aw_selected <= '0;
        end
        else begin
            if (aw_locked || w_locked) begin
                // We don't need to check master.aw_valid, as it is always 1 when aw_locked is 1.
                if (/* master.aw_valid && */ master.aw_ready) begin
                    aw_locked <= 1'b0;
                end
                if (master.w_last && master.w_valid && master.w_ready) begin
                    w_locked <= 1'b0;
                end
            end
            else if (aw_forward) begin
                aw_locked   <= 1'b1;
                w_locked    <= 1'b1;
                aw_selected <= aw_match_bin;
            end
        end

    // Demux AW/W channel
    for (genvar i = 0; i < SLAVE_NUM; i++) begin
        assign slave[i].aw_id     = master.aw_id;
        assign slave[i].aw_addr   = master.aw_addr;
        assign slave[i].aw_len    = master.aw_len;
        assign slave[i].aw_size   = master.aw_size;
        assign slave[i].aw_burst  = master.aw_burst;
        assign slave[i].aw_lock   = master.aw_lock;
        assign slave[i].aw_cache  = master.aw_cache;
        assign slave[i].aw_prot   = master.aw_prot;
        assign slave[i].aw_qos    = master.aw_qos;
        assign slave[i].aw_region = master.aw_region;
        assign slave[i].aw_user   = master.aw_user;
        assign slave[i].aw_valid  = aw_locked && aw_selected == i;
        assign slave[i].w_data    = master.w_data;
        assign slave[i].w_strb    = master.w_strb;
        assign slave[i].w_last    = master.w_last;
        assign slave[i].w_user    = master.w_user;
        assign slave[i].w_valid   = w_locked && aw_selected == i && master.w_valid;
    end

    assign master.aw_ready = aw_locked && slave_aw_ready[aw_selected];
    assign master.w_ready  = w_locked  && slave_w_ready [aw_selected];

    //
    // Write response: For response, we will use round robin arbiter to determine which one is processed first.
    //

    // Whenever an arbitration happens, we need to lock it until the handshake happens.
    logic                   b_locked;
    logic [SLAVE_WIDTH-1:0] b_selected;

    // We only perform arbitration if we haven't locked any slaves yet, or when it will be unlocked.
    // Note that when b_locked is asserted, corresponding slave's b_valid is definitely high (as it's why it
    // is granted by arbiter), so master.b_valid is definitely high, so
    //     master.b_valid && master.b_ready
    // can be simplified to master.b_ready.
    assign b_arb_enable = !b_locked;

    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            b_locked <= 1'b0;
            b_selected <= '0;
        end
        else begin
            if (b_locked) begin
                // We don't need to check master.b_valid, as it is always 1 when b_locked is 1.
                if (/* master.b_valid && */ master.b_ready) begin
                    b_locked <= 1'b0;
                end
            end
            if (b_arb_enable && b_arb_grant) begin
                b_locked   <= 1'b1;
                b_selected <= b_arb_grant_bin;
            end
        end

    b_pack_t master_b;
    assign master_b = slave_b[b_selected];
    assign master.b_id     = master_b.id;
    assign master.b_resp   = master_b.resp;
    assign master.b_user   = master_b.user;
    assign master.b_valid  = b_locked;

    for (genvar i = 0; i < SLAVE_NUM; i++) begin: b
        assign slave[i].b_ready = b_locked && b_selected == i && master.b_ready;
    end

    //
    // Reading part. Mostly similar to writing, except that we check the handshake on R channel with last set, instead
    // of checking the B channel.
    //
    mapping_t [2**master.ID_WIDTH-1:0] read_map;

    mapping_t ar_lookup;
    assign ar_lookup = read_map[master.ar_id];

    logic ar_forward;
    assign ar_forward = master.ar_valid && (ar_lookup.active_cnt == 0 ||
        (ar_lookup.active_slave == ar_match_bin &&
         ar_lookup.active_cnt != 2**ACTIVE_CNT_WIDTH-1));

    logic [2**master.ID_WIDTH-1:0] r_cnt_incr;
    logic [2**master.ID_WIDTH-1:0] r_cnt_decr;
    for (genvar i = 0; i < 2**master.ID_WIDTH; i++) begin
        assign r_cnt_decr[i] = master.r_id == i && master.r_valid && master.r_ready && master.r_last;
        assign r_cnt_incr[i] = master.ar_id == i && master.ar_valid && master.ar_ready;
    end

    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            for (int i = 0; i < 2**master.ID_WIDTH; i++)
                read_map[i] <= mapping_t'('0);
        end
        else begin
            for (int i = 0; i < 2**master.ID_WIDTH; i++) begin
                if (r_cnt_incr[i]) begin
                    read_map[i].active_slave <= ar_match_bin;
                    if (!r_cnt_decr[i]) read_map[i].active_cnt <= read_map[i].active_cnt + 1;
                end
                else if (r_cnt_decr[i]) begin
                    read_map[i].active_cnt <= read_map[i].active_cnt - 1;
                end
            end
        end

    // When we have decided a slave we need to make sure we keep AR connected until the handshake
    // happens.
    logic ar_locked;
    logic [SLAVE_WIDTH-1:0] ar_selected;

    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            ar_locked   <= 1'b0;
            ar_selected <= '0;
        end
        else begin
            if (ar_locked) begin
                // We don't need to check master.ar_valid, as it is always 1 when ar_locked is 1.
                if (/* master.ar_valid && */ master.ar_ready) begin
                    ar_locked <= 1'b0;
                end
            end
            else if (ar_forward) begin
                ar_locked   <= 1'b1;
                ar_selected <= ar_match_bin;
            end
        end

    // Demux AR channel
    for (genvar i = 0; i < SLAVE_NUM; i++) begin
        assign slave[i].ar_id     = master.ar_id;
        assign slave[i].ar_addr   = master.ar_addr;
        assign slave[i].ar_len    = master.ar_len;
        assign slave[i].ar_size   = master.ar_size;
        assign slave[i].ar_burst  = master.ar_burst;
        assign slave[i].ar_lock   = master.ar_lock;
        assign slave[i].ar_cache  = master.ar_cache;
        assign slave[i].ar_prot   = master.ar_prot;
        assign slave[i].ar_qos    = master.ar_qos;
        assign slave[i].ar_region = master.ar_region;
        assign slave[i].ar_user   = master.ar_user;
        assign slave[i].ar_valid  = ar_locked && ar_match_bin == i;
    end

    assign master.ar_ready = ar_locked && slave_ar_ready[ar_match_bin];

    //
    // Read response. We need high performance on read response channel, so we have used combinational logic here to
    // ensure there're no bubble cycles, and we can use register slice later to break combinational loop and critical
    // path introduced here.
    //
    // Once arbitration happens, we will need to hold all signals stable until the transmission happens, as this is
    // required by AXI specification. We cannot simply make arbiter stable unless the granted request is clear, as it
    // will have a chance starving other slaves.
    // We either need to latch r_arb_grant_bin until the transmission, or we should only perform arbitration when
    // r_ready is high, which means the handshake will happen on the same cycle. We chose the second strategy. By doing
    // so we have introduced combinational path from master.r_ready to master.r_valid and from slave[i].r_valid to
    // slave[i].r_ready here which need to be broken in order to connect to generic AXI components.
    //
    assign r_arb_enable = master.r_ready;

    r_pack_t master_r;
    assign master_r = slave_r[r_arb_grant_bin];
    assign master.r_id     = master_r.id;
    assign master.r_data   = master_r.data;
    assign master.r_resp   = master_r.resp;
    assign master.r_last   = master_r.last;
    assign master.r_user   = master_r.user;
    assign master.r_valid  = r_arb_enable && r_arb_grant != 0;

    for (genvar i = 0; i < SLAVE_NUM; i++) begin: r
        assign slave[i].r_ready = r_arb_enable && r_arb_grant[i];
    end

endmodule

module axi_demux #(
    parameter SLAVE_NUM,
    // Ideally we would like to remove this but it is required by type of BASE and MASK
    parameter ADDR_WIDTH       = -1,
    parameter ACTIVE_CNT_WIDTH = 4,
    parameter [SLAVE_NUM-1:0][ADDR_WIDTH-1:0] BASE = '0,
    parameter [SLAVE_NUM-1:0][ADDR_WIDTH-1:0] MASK = '0
) (
    axi_channel.slave  master,
    axi_channel.master slave [SLAVE_NUM]
);

    axi_channel #(
        .ID_WIDTH   (master.ID_WIDTH),
        .ADDR_WIDTH (master.ADDR_WIDTH),
        .DATA_WIDTH (master.DATA_WIDTH)
    ) master_buf (
        master.clk,
        master.rstn
    ), slave_buf [SLAVE_NUM] (
        master.clk,
        master.rstn
    );

    axi_demux_raw #(
        .SLAVE_NUM        (SLAVE_NUM),
        .ADDR_WIDTH       (ADDR_WIDTH),
        .ACTIVE_CNT_WIDTH (ACTIVE_CNT_WIDTH),
        .BASE             (BASE),
        .MASK             (MASK)
    ) mux (master_buf, slave_buf);

    axi_regslice #(
        .AW_MODE (0),
        . W_MODE (0),
        . B_MODE (0),
        .AR_MODE (0),
        . R_MODE (1)
    ) master_slice (master, master_buf);

    for (genvar i = 0; i < SLAVE_NUM; i++) begin: slave_slice
        axi_regslice #(
            .AW_MODE (0),
            . W_MODE (0),
            . B_MODE (0),
            .AR_MODE (0),
            . R_MODE (2)
        ) slice (slave_buf[i], slave[i]);
    end

endmodule
