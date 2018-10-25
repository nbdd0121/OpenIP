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

// A general FIFO utility that accepts arbitary types and capacity. PASS_THROUGH can be set to 1 to allow zero cycle
// latency between push and pop when FIFO is empty.
module fifo #(
    parameter type TYPE = logic,
    parameter CAPACITY = 1,
    parameter PASS_THROUGH = 0
) (
    input logic clk,
    input logic rstn,

    input  logic w_valid,
    output logic w_ready,
    input  TYPE  w_data,

    output logic r_valid,
    input  logic r_ready,
    output TYPE  r_data
);

    localparam DEPTH = $clog2(CAPACITY);

    // Static checks of paramters
    initial assert (CAPACITY >= 1) else $fatal(1, "FIFO should have capacity of at least 1");

    generate
        // General case, if CAPACITY is not 1.
        if (DEPTH != 0) begin

            // Ring buffer constructs
            TYPE buffer [0:CAPACITY];
            logic [DEPTH-1:0] readptr, readptr_next;
            logic [DEPTH-1:0] writeptr, writeptr_next;
            logic empty, empty_next;
            logic full, full_next;

            // We cannot accept more writes when full. When empty, we can still accept read if there is a valid write.
            assign w_ready = !full || (PASS_THROUGH && r_ready);
            assign r_valid = !empty || (PASS_THROUGH && w_valid);

            // Function to calculate the next locaiton of a ring buffer pointer
            function automatic logic [DEPTH-1:0] incr(input logic [DEPTH-1:0] ptr);
                incr = ptr == CAPACITY - 1 ? '0 : ptr + 1;
            endfunction

            // Compute next state
            always_comb begin
                // Default assignments
                readptr_next = readptr;
                writeptr_next = writeptr;
                empty_next = empty;
                full_next = full;
                r_data = buffer[readptr];

                // Special cases when FIFO is empty and both sides are reading/writing data. In this case the data is
                // passed through from write to read channel and read/write to buffer does not happen, provided that
                // PASS_THROUGH parameter is enabled.
                if (PASS_THROUGH && empty && r_ready && w_valid) begin
                    r_data = w_data;
                end
                else begin
                    // Adjust pointers according to handshake signals.
                    if (r_valid && r_ready) readptr_next = incr(readptr);
                    if (w_valid && w_ready) writeptr_next = incr(writeptr);

                    // If pointers coincide, then determine the full/empty status by the firing transaction. Note that
                    // these checks can be disjoint as we can never read/write simulatenously when the buffer is full.
                    if (readptr_next == writeptr_next) begin
                        if (r_valid && r_ready) empty_next = 1'b1;
                        if (w_valid && w_ready) full_next = 1'b1;
                    end
                end
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

                    if (w_valid && w_ready) buffer[writeptr] <= w_data;
                end

        end
        // This is a specialised version targeting buffer of size 1. The general one does not work as pointers do not
        // exist in this special case.
        else begin

            TYPE buffer;
            // In this special case full and empty are always complements.
            logic full, full_next;
            assign w_ready = !full || (PASS_THROUGH && r_ready);
            assign r_valid = full || (PASS_THROUGH && w_valid);

            // Compute next state
            always_comb begin
                full_next = full;
                r_data = buffer;
                if (PASS_THROUGH && !full && r_ready && w_valid) begin
                    r_data = w_data;
                end
                else begin
                    if (r_valid && r_ready) full_next = 1'b0;
                    if (w_valid && w_ready) full_next = 1'b1;
                end
            end

            always_ff @(posedge clk or negedge rstn)
                if (!rstn) begin
                    full <= 1'b0;
                end
                else begin
                    full <= full_next;
                    if (w_valid && w_ready) buffer <= w_data;
                end

        end
    endgenerate

endmodule
