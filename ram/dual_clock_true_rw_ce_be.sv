/*
 * Copyright (c) 2016-2018, Gary Guo
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

// A dual clock, true dual-port RAM with clock-enable and byte-enable.
// Both port A and port B are read-first.
// When port A and port B has address conflict, the behaviour is undefined.
// Compatiblity warning: This synthesises only one Vivado.
module dual_clock_true_rw_ce_be_ram #(
    parameter ADDR_WIDTH      = 16,
    parameter DATA_WIDTH      = 64,
    parameter DEFAULT_CONTENT = ""
) (
    input  logic                    a_clk,
    input  logic                    a_en,
    input  logic [DATA_WIDTH/8-1:0] a_we,
    input  logic [ADDR_WIDTH-1:0]   a_addr,
    input  logic [DATA_WIDTH-1:0]   a_wrdata,
    output logic [DATA_WIDTH-1:0]   a_rddata,

    input  logic                    b_clk,
    input  logic                    b_en,
    input  logic [DATA_WIDTH/8-1:0] b_we,
    input  logic [ADDR_WIDTH-1:0]   b_addr,
    input  logic [DATA_WIDTH-1:0]   b_wrdata,
    output logic [DATA_WIDTH-1:0]   b_rddata
);

    logic [DATA_WIDTH-1:0] mem [0:2**ADDR_WIDTH-1];

    always_ff @(posedge a_clk)
        if (a_en) begin
            a_rddata <= mem[a_addr];
            foreach(a_we[i])
                if(a_we[i]) mem[a_addr][i*8+:8] <= a_wrdata[i*8+:8];
        end

    always_ff @(posedge b_clk)
        if (b_en) begin
            b_rddata <= mem[b_addr];
            foreach(b_we[i])
                if(b_we[i]) mem[b_addr][i*8+:8] <= b_wrdata[i*8+:8];
        end

    generate
        if (DEFAULT_CONTENT) initial $readmemh(DEFAULT_CONTENT, mem);
    endgenerate

endmodule
