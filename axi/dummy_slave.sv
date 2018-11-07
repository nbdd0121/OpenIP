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

// A simple dummy AXI slave, for prototyping or building interconnects.
module axi_dummy_slave #(
    parameter DATA_WIDTH                    = 64,
    parameter logic [DATA_WIDTH-1:0] R_DATA = 0,
    parameter axi_common::resp_t R_RESP     = axi_common::RESP_OKAY,
    parameter axi_common::resp_t B_RESP     = axi_common::RESP_OKAY
) (
    axi_channel.slave master
);

    // Static checks of parameters.
    initial assert(DATA_WIDTH == master.DATA_WIDTH) else $fatal(1, "DATA_WIDTH mismatch");

    // Extract clk and rstn signals from interfaces
    logic clk;
    logic rstn;
    assign clk = master.clk;
    assign rstn = master.rstn;

    //
    // Write handling logic
    //

    assign master.b_resp = B_RESP;

    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            master.aw_ready <= 1'b1;
            master.w_ready  <= 1'b0;
            master.b_valid  <= 1'b0;
            master.b_id     <= 'x;
        end
        else begin
            if (master.b_valid) begin
                if (master.b_ready) begin
                    master.b_valid  <= 1'b0;
                    master.aw_ready <= 1'b1;
                    master.b_id     <= 'x;
                end
            end
            else if (master.w_ready) begin
                if (master.w_valid && master.w_last) begin
                    master.w_ready <= 1'b0;
                    master.b_valid <= 1'b1;
                end
            end
            else if (master.aw_valid) begin
                master.b_id     <= master.aw_id;
                master.aw_ready <= 1'b0;
                master.w_ready  <= 1'b1;
            end
        end

    //
    // Read handling logic
    //

    // Number of words remaining to transfer.
    logic [7:0] r_len;

    assign master.r_data = R_DATA;
    assign master.r_resp = R_RESP;
    assign master.r_last = r_len == 0;

    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            r_len <= 1'b0;
            master.ar_ready <= 1'b1;
            master.r_valid  <= 1'b0;
            master.r_id     <= 'x;
        end
        else begin
            if (master.r_valid) begin
                if (master.r_ready) begin
                    if (master.r_last) begin
                        master.r_valid  <= 1'b0;
                        master.ar_ready <= 1'b1;
                        master.r_id     <= 'x;
                    end
                    else begin
                        r_len <= r_len - 1;
                    end
                end
            end
            else if (master.ar_valid) begin
                r_len           <= master.ar_len;
                master.r_id     <= master.ar_id;
                master.ar_ready <= 1'b0;
                master.r_valid  <= 1'b1;
            end
        end

endmodule
