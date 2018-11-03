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

// A general FIFO utility that accepts arbitary types and depth.
// The interface is defined with handshaking signals instead of traditional empty and full, but you can still use
// !w_ready as full and !r_valid as empty.
//
// FALL_THROUGH: set to 1 for first-word fall-through.
// USE_BRAM: set to 1 to instruct the FIFO to use BRAM. Set to 0 will let synthesiser determine whether to use
//     distributed RAM or registers. Even though synthesiser will usually convert small BRAM into DRAMs, by disable
//     USE_BRAM you can save the forwarding logic required to achieve write-first. USE_BRAM is by default on if
//     DEPTH > 16.
module fifo #(
    parameter DATA_WIDTH   = 1,
    parameter type TYPE    = logic [DATA_WIDTH-1:0],
    parameter DEPTH        = 1,
    parameter FALL_THROUGH = 0,
    parameter USE_BRAM     = DEPTH > 16
) (
    input  logic clk,
    input  logic rstn,

    input  logic w_valid,
    output logic w_ready,
    input  TYPE  w_data,

    output logic r_valid,
    input  logic r_ready,
    output TYPE  r_data
);

    localparam ADDR_WIDTH = $clog2(DEPTH);

    // Static checks of paramters
    initial begin
        assert (2 ** ADDR_WIDTH == DEPTH) else $fatal(1, "FIFO depth should be power of 2");
        assert (DEPTH >= 1) else $fatal(1, "FIFO should have depth of at least 1");
    end

    generate
        // General case, if DEPTH is not 1.
        if (ADDR_WIDTH != 0) begin: mult

            logic [ADDR_WIDTH:0] readptr, readptr_next;
            logic [ADDR_WIDTH:0] writeptr, writeptr_next;
            logic empty, empty_next;
            logic full, full_next;

            // We cannot accept more writes when full. When empty, we can still accept read if there is a valid write.
            assign w_ready = !full;
            assign r_valid = !empty || (FALL_THROUGH && w_valid);

            // Compute next state
            always_comb begin
                // Adjust pointers according to handshake signals.
                readptr_next = r_valid && r_ready ? readptr + 1 : readptr;
                writeptr_next = w_valid && w_ready ? writeptr + 1 : writeptr;
                // FIFO is empty if both pointers coincide.
                empty_next = writeptr_next == readptr_next;
                // FIFO is full if they are DEPTH distance apart.
                full_next = writeptr_next[ADDR_WIDTH] != readptr_next[ADDR_WIDTH] &&
                    writeptr[ADDR_WIDTH-1:0] == readptr_next[ADDR_WIDTH-1:0];
            end

            always_ff @(posedge clk or negedge rstn)
                if (!rstn) begin
                    readptr  <= 0;
                    writeptr <= 0;
                    full     <= 1'b0;
                    empty    <= 1'b1;
                end
                else begin
                    readptr  <= readptr_next;
                    writeptr <= writeptr_next;
                    empty    <= empty_next;
                    full     <= full_next;
                end

            TYPE r_data_read;
            // Special cases when FIFO is empty and FALL_THROUGH is enabled. In this case we simply connect two
            // sides together. If we need data forwarding do it, otherwise read from BRAM.
            assign r_data = (FALL_THROUGH && empty) ? w_data : r_data_read;

            if (USE_BRAM) begin: bram

                TYPE  r_data_bram;
                TYPE  r_data_forwarded;
                logic r_should_forward;

                // If we need data forwarding do it, otherwise read from BRAM.
                assign r_data_read = r_should_forward ? r_data_forwarded : r_data_bram;

                // Data-forwarding when read and write conflicts.
                always_ff @(posedge clk or negedge rstn)
                    if (!rstn) begin
                        r_should_forward <= 1'b0;
                        r_data_forwarded <= TYPE'('x);
                    end
                    else begin
                        // If readptr_next == writeptr, then the data read out next cycle will be invalid (as the BRAM is
                        // write-first), so we need to forward w_data.
                        if (w_valid && w_ready && writeptr == readptr_next) begin
                            r_should_forward <= 1'b1;
                            r_data_forwarded <= w_data;
                        end
                        else begin
                            r_should_forward <= 1'b0;
                            r_data_forwarded <= TYPE'('x);
                        end
                    end

                // BRAM instantiation for actually storing the data.
                dual_port_bram #(
                    .ADDR_WIDTH    (ADDR_WIDTH),
                    .DATA_WIDTH    ($bits(TYPE)),
                    .WE_UNIT_WIDTH ($bits(TYPE))
                ) bram (
                    .a_clk    (clk),
                    .a_en     (1'b1),
                    .a_we     (1'b0),
                    .a_addr   (readptr_next[ADDR_WIDTH-1:0]),
                    .a_wrdata ('x),
                    .a_rddata (r_data_bram),
                    .b_clk    (clk),
                    .b_en     (w_valid && w_ready),
                    .b_addr   (writeptr[ADDR_WIDTH-1:0]),
                    .b_we     (1'b1),
                    .b_wrdata (w_data),
                    .b_rddata ()
                );

            end else begin: buffer

                TYPE buffer[0:DEPTH];
                assign r_data_read = buffer[readptr[ADDR_WIDTH-1:0]];
                always_ff @(posedge clk)
                    if (w_valid && w_ready) buffer[writeptr[ADDR_WIDTH-1:0]] <= w_data;

            end

        end
        // This is a specialised version targeting buffer of size 1. The general one does not work as pointers do not
        // exist in this special case.
        else begin: one

            TYPE buffer;
            // In this special case full and empty are always complements.
            logic empty, empty_next;
            assign w_ready = empty;
            assign r_valid = !empty || (FALL_THROUGH && w_valid);

            // Buffer will be empty if: it's empty and both r/w happens, or it's full and the value is read out.
            assign empty_next = empty ? (w_valid && w_ready == r_valid && r_ready) : r_valid && r_ready;

            always_ff @(posedge clk or negedge rstn)
                if (!rstn) begin
                    empty <= 1'b1;
                end
                else begin
                    empty <= empty_next;
                end

            // In this simple case we don't need forwarding logic any more, we just use registers instead.
            assign r_data = (FALL_THROUGH && empty) ? w_data : buffer;
            always_ff @(posedge clk)
                if (w_valid && w_ready) buffer <= w_data;

        end
    endgenerate

endmodule
