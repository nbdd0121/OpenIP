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

// A utility to connect a master to a slave with narrower ID width.
//
// ACTIVE_CNT_WIDTH: Decides how many pending transactions can there be with the same ID. Increase
//     the amount will cause wider adders to be used therefore will use more resources.
module axi_id_downsizer_raw #(
    parameter ACTIVE_CNT_WIDTH = 4
) (
    axi_channel.slave  master,
    axi_channel.master slave
);

    // Static checks of interface matching
    if (master.DATA_WIDTH != slave.DATA_WIDTH ||
        master.ADDR_WIDTH != slave.ADDR_WIDTH ||
        master.AW_USER_WIDTH != slave.AW_USER_WIDTH ||
        master.W_USER_WIDTH != slave.W_USER_WIDTH ||
        master.B_USER_WIDTH != slave.B_USER_WIDTH ||
        master.AR_USER_WIDTH != slave.AR_USER_WIDTH ||
        master.R_USER_WIDTH != slave.R_USER_WIDTH)
        $fatal(1, "Parameter mismatch");

    // Extract clk and rstn signals from interfaces
    logic clk;
    logic rstn;
    assign clk = master.clk;
    assign rstn = master.rstn;

    // High-level description of how this module works:
    // As the master ID is wider than the slave ID, what we need to do is to map the master ID to
    // a slave ID and keep the mapping. When we received the reply from slave we will then need to
    // restore the ID from the mapping. AXI allows reordering of transactions of different IDs
    // only. Therefore, we must map the same master ID to the same slave ID, otherwise the later
    // one might overtake the earlier one and causes issue.
    //
    // There are multiple ways to do this, from most generic to least:
    // * Allocate a new slave ID for each master request. Reuse the same ID for the same master
    //   request. Release the slave ID when all requests have been responded.
    // * Instead of doing allocation, hash the master ID to get the slave ID.
    // * Instead of hashing, do simple truncation.
    // The first one is really flexible and can avoid collision at all, but it requires more
    // complex circuitry, and might increase critical path significantly. Later ones are simpler
    // and has short critical path as slave IDs are not allocated but statically determined from
    // master IDs.
    //
    // In the current implementation we will use the third way. We will use a table to store the
    // original ID when we truncate and forward ID in address transactions to slave, and remove
    // the value when a reply is received. As an optimisation, we will not store the lower bits of
    // master ID (since we get them back in slave response as well).
    //
    // As our implementation will stall address channel based on the address supplied, we will
    // need to break combinational path by using a reverse register slice on address channels. We
    // also need a forward register slice on address channels to reduce critical path. This module
    // also adds combinational path levels to RID/BID. If these causes timing issues we may add
    // additional forward register slices.

    //
    // Definition of mapping entry
    //

    typedef struct packed {
        // The higher bits of master ID, necessary to perform reflection.
        logic [master.ID_WIDTH-1:slave.ID_WIDTH] active_id;
        // We can issue at most 2**ACTIVE_CNT_WIDTH transactions for the same ID. We will stall
        // address transaction if this is exceeded.
        logic [ACTIVE_CNT_WIDTH-1:0] active_cnt;
    } mapping_t;

    //
    // Writing part
    //

    // We need to perform a read-check-write on AW channel and a read-and-write write on B channel.
    // So we cannot use BRAMs here.
    mapping_t [2**slave.ID_WIDTH-1:0] write_map;

    //
    // Mapping lookup and update logic
    //
    mapping_t aw_lookup;
    mapping_t b_lookup;
    assign aw_lookup = write_map[slave.aw_id];
    assign b_lookup = write_map[slave.b_id];

    // We can forward the request if the current mapping is not active, or we will use the same
    // mapping and active_cnt hasn't reached the limit.
    logic aw_forward;
    assign aw_forward = master.aw_valid && (aw_lookup.active_cnt == 0 ||
        (aw_lookup.active_id == master.aw_id[master.ID_WIDTH-1:slave.ID_WIDTH] &&
         aw_lookup.active_cnt != 2**ACTIVE_CNT_WIDTH-1));

    // Whether we should increase active_cnt or decrease it.
    logic [2**slave.ID_WIDTH-1:0] w_cnt_incr;
    logic [2**slave.ID_WIDTH-1:0] w_cnt_decr;
    always_comb begin
        for (int i = 0; i < 2**slave.ID_WIDTH; i++) begin
            w_cnt_decr[i] = slave.b_id == i && slave.b_valid && slave.b_ready;
            w_cnt_incr[i] = slave.aw_id == i && slave.aw_valid && slave.aw_ready;
        end
    end

    // Actually update the mappings
    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            for (int i = 0; i < 2**slave.ID_WIDTH; i++)
                write_map[i] <= mapping_t'('0);
        end
        else begin
            for (int i = 0; i < 2**slave.ID_WIDTH; i++) begin
                if (w_cnt_incr[i]) begin
                    write_map[i].active_id <= master.aw_id[master.ID_WIDTH-1:slave.ID_WIDTH];
                    if (!w_cnt_decr) write_map[i].active_cnt <= write_map[i].active_cnt + 1;
                end
                else if (w_cnt_decr[i]) begin
                    write_map[i].active_cnt <= write_map[i].active_cnt - 1;
                end
            end
        end

    //
    // Connect master and slave AW, W and B channels together
    //
    assign slave.aw_id     = master.aw_id[slave.ID_WIDTH-1:0];
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
    // In here technically we can use the similar approach as demux by adding 1 latency cycle and
    // 1 bubble cycle on address channels to remove the need of having register slices. The
    // current approach seems simpler for ID downsizer but if the resource usage becomes a problem
    // it is easy to switch approach.
    assign slave.aw_valid  = aw_forward;
    assign master.aw_ready = aw_forward && slave.aw_ready;

    assign slave.w_data    = master.w_data;
    assign slave.w_strb    = master.w_strb;
    assign slave.w_last    = master.w_last;
    assign slave.w_user    = master.w_user;
    assign slave.w_valid   = master.w_valid;
    assign master.w_ready  = slave.w_ready;

    assign master.b_id     = {b_lookup.active_id, slave.b_id};
    assign master.b_resp   = slave.b_resp;
    assign master.b_user   = slave.b_user;
    assign master.b_valid  = slave.b_valid;
    assign slave.b_ready   = master.b_ready;

    //
    // Reading part. Mostly similar to writing, except that we check the handshake on R channel
    // with last set, instead of checking the B channel.
    //
    mapping_t [2**slave.ID_WIDTH-1:0] read_map;

    mapping_t ar_lookup;
    mapping_t r_lookup;
    assign ar_lookup = read_map[slave.ar_id];
    assign r_lookup = read_map[slave.r_id];

    logic ar_forward;
    assign ar_forward = master.ar_valid && (ar_lookup.active_cnt == 0 ||
        (ar_lookup.active_id == master.ar_id[master.ID_WIDTH-1:slave.ID_WIDTH] &&
         ar_lookup.active_cnt != 2**ACTIVE_CNT_WIDTH-1));

    logic [2**slave.ID_WIDTH-1:0] r_cnt_incr;
    logic [2**slave.ID_WIDTH-1:0] r_cnt_decr;
    always_comb begin
        for (int i = 0; i < 2**slave.ID_WIDTH; i++) begin
            r_cnt_decr[i] = slave.r_id == i && slave.r_valid && slave.r_ready && slave.r_last;
            r_cnt_incr[i] = slave.ar_id == i && slave.ar_valid && slave.ar_ready;
        end
    end

    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            for (int i = 0; i < 2**slave.ID_WIDTH; i++)
                read_map[i] <= mapping_t'('0);
        end
        else begin
            for (int i = 0; i < 2**slave.ID_WIDTH; i++) begin
                if (r_cnt_incr) begin
                    read_map[i].active_id <= master.ar_id[master.ID_WIDTH-1:slave.ID_WIDTH];
                    if (!r_cnt_decr) read_map[i].active_cnt <= read_map[i].active_cnt + 1;
                end
                else if (r_cnt_decr) begin
                    read_map[i].active_cnt <= read_map[i].active_cnt - 1;
                end
            end
        end

    assign slave.ar_id     = master.ar_id[slave.ID_WIDTH-1:0];
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
    assign slave.ar_valid  = ar_forward;
    assign master.ar_ready = ar_forward && slave.ar_ready;

    assign master.r_id     = {r_lookup.active_id, slave.r_id};
    assign master.r_data   = slave.r_data;
    assign master.r_resp   = slave.r_resp;
    assign master.r_last   = slave.r_last;
    assign master.r_user   = slave.r_user;
    assign master.r_valid  = slave.r_valid;
    assign slave.r_ready   = master.r_ready;

endmodule

module axi_id_downsizer #(
    parameter ACTIVE_CNT_WIDTH = 4
) (
    axi_channel.slave  master,
    axi_channel.master slave
);

    axi_channel #(
        .ID_WIDTH   (master.ID_WIDTH),
        .ADDR_WIDTH (master.ADDR_WIDTH),
        .DATA_WIDTH (master.DATA_WIDTH)
    ) master_buf (
        master.clk,
        master.rstn
    );

    axi_channel #(
        .ID_WIDTH   (slave.ID_WIDTH),
        .ADDR_WIDTH (slave.ADDR_WIDTH),
        .DATA_WIDTH (slave.DATA_WIDTH)
    ) slave_buf (
        slave.clk,
        slave.rstn
    );

    axi_id_downsizer_raw #(
        .ACTIVE_CNT_WIDTH(ACTIVE_CNT_WIDTH)
    ) downsizer (
        .master (master_buf),
        .slave  (slave_buf)
    );

    // This register slice is required to break combinational loops.
    axi_regslice #(
        .AW_MODE (2),
        . W_MODE (0),
        . B_MODE (0),
        .AR_MODE (2),
        . R_MODE (0)
    ) master_slice (master, master_buf);

    // This register slice is for reducing critical path.
    axi_regslice #(
        .AW_MODE (1),
        . W_MODE (0),
        . B_MODE (0),
        .AR_MODE (1),
        . R_MODE (0)
    ) slave_slice (slave_buf, slave);

endmodule
