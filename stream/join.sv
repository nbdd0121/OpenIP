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

// Connect two AXI-Stream channels together.
module stream_join (
    stream_channel.slave  master,
    stream_channel.master slave
);

    // Static checks of interface matching
    if (master.ID_WIDTH != slave.ID_WIDTH ||
        master.DATA_WIDTH != slave.DATA_WIDTH ||
        master.DEST_WIDTH != slave.DEST_WIDTH ||
        master.USER_WIDTH != slave.USER_WIDTH)
        $fatal(1, "Interface parameters mismatch");

    assign slave.t_id     = master.t_id;
    assign slave.t_dest   = master.t_dest;
    assign slave.t_data   = master.t_data;
    assign slave.t_strb   = master.t_strb;
    assign slave.t_keep   = master.t_keep;
    assign slave.t_last   = master.t_last;
    assign slave.t_user   = master.t_user;
    assign slave.t_valid  = master.t_valid;
    assign master.t_ready = slave.t_ready;

endmodule
