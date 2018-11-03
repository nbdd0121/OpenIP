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

// A general dual-port BRAM utility that is simple enough so that all synthesisers should be able to recognise.
// Both R/W takes a clock cycle and this is read-first.
// WE_UNIT_WIDTH: How many bits should form a single write-enable bit. By default it is byte-enable, but you can e.g.
//     set this to DATA_WIDTH so there is a single write enable.
module dual_port_bram #(
    parameter ADDR_WIDTH      = 16,
    parameter DATA_WIDTH      = 64,
    parameter WE_UNIT_WIDTH   = 8,
    parameter DEFAULT_CONTENT = ""
) (
    input  logic                                a_clk,
    input  logic                                a_en,
    input  logic [DATA_WIDTH/WE_UNIT_WIDTH-1:0] a_we,
    input  logic [ADDR_WIDTH-1:0]               a_addr,
    input  logic [DATA_WIDTH-1:0]               a_wrdata,
    output logic [DATA_WIDTH-1:0]               a_rddata,

    input  logic                                b_clk,
    input  logic                                b_en,
    input  logic [DATA_WIDTH/WE_UNIT_WIDTH-1:0] b_we,
    input  logic [ADDR_WIDTH-1:0]               b_addr,
    input  logic [DATA_WIDTH-1:0]               b_wrdata,
    output logic [DATA_WIDTH-1:0]               b_rddata
);

    logic [DATA_WIDTH-1:0] mem [0:2**ADDR_WIDTH-1];

    always_ff @(posedge a_clk)
        if (a_en) begin
            a_rddata <= mem[a_addr];
            foreach(a_we[i])
                if(a_we[i]) mem[a_addr][i*WE_UNIT_WIDTH+:WE_UNIT_WIDTH] <= a_wrdata[i*WE_UNIT_WIDTH+:WE_UNIT_WIDTH];
        end

    always_ff @(posedge b_clk)
        if (b_en) begin
            b_rddata <= mem[b_addr];
            foreach(b_we[i])
                if(b_we[i]) mem[b_addr][i*WE_UNIT_WIDTH+:WE_UNIT_WIDTH] <= b_wrdata[i*WE_UNIT_WIDTH+:WE_UNIT_WIDTH];
        end

    generate
        if (DEFAULT_CONTENT)
            initial $readmemh(DEFAULT_CONTENT, mem);
        else
            initial foreach(mem[i]) mem[i] <= {DATA_WIDTH{1'b0}};
    endgenerate

endmodule
