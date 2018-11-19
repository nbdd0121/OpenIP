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

// Helper modules to convert one-hot code to binary representation.
// Ideally they should be functions but due to SystemVerilog restrictions we cannot parameterise functions.
module onehot_to_binary #(
    parameter ONEHOT_WIDTH = 2,
    parameter BINARY_WIDTH = $clog2(ONEHOT_WIDTH)
) (
    input  logic [ONEHOT_WIDTH-1:0] onehot,
    output logic [BINARY_WIDTH-1:0] binary
);

    for (genvar i = 0; i < BINARY_WIDTH; i++) begin: bin
        logic [ONEHOT_WIDTH-1:0] bitmask;
        for (genvar j = 0; j < ONEHOT_WIDTH; j++) begin: one
            logic [BINARY_WIDTH-1:0] logic_j;
            assign logic_j = j;
            assign bitmask[j] = logic_j[i] & onehot[j];
        end
        assign binary[i] = |bitmask;
    end

endmodule
