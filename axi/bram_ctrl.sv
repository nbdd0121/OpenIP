module axi_bram_ctrl #(
    parameter ADDR_WIDTH = 48,
    parameter DATA_WIDTH = 64,
    parameter BRAM_ADDR_WIDTH = 16,
    parameter ID_WIDTH = 1
) (
    input  clk,
    input  resetn,

    axi_channel.slave master,

    output                          bram_en,
    output [DATA_WIDTH/8-1:0]       bram_we,
    output [BRAM_ADDR_WIDTH-1:0]    bram_addr,
    output [DATA_WIDTH-1:0]         bram_wrdata,
    input  [DATA_WIDTH-1:0]         bram_rddata
);

    localparam UNUSED_ADDR_WIDTH = $clog2(DATA_WIDTH / 8);

    /* AXI Interfacing */

    // We don't use user signals
    assign master.r_user = 'x;
    assign master.b_user = 'x;

    // Whether we are ready for a new transaction
    logic a_ready;
    assign master.ar_ready = a_ready;
    assign master.aw_ready = a_ready;

    // Read/write response. We always give a success response.
    assign master.r_resp = axi_common::RESP_OKAY;
    assign master.b_resp = axi_common::RESP_OKAY;

    // Reading part
    // The address and remaining length of current read transaction.
    logic [BRAM_ADDR_WIDTH-1:0] read_burst_addr;
    logic [7:0] read_burst_len;
    assign master.r_last = read_burst_len == 0;

    // Whether we acked a read transaction this clock cycle
    logic read_acked;
    assign read_acked = master.ar_ready & master.ar_valid;

    // Whether next data in a read burst can be served
    logic read_data_acked;
    assign read_data_acked = master.r_ready & master.r_valid & !master.r_last;

    // Whether there is an pending read response
    // we can only guarantee that BRAM data is available for one cycle
    // So we need to cache the data
    logic pending_read;
    logic [DATA_WIDTH-1:0] pending_read_data;

    // Writing part
    // The address and remaining length of current write transaction
    logic [BRAM_ADDR_WIDTH-1:0] write_burst_addr;
    logic [7:0] write_burst_len;

    // Whether we acked a write transaction or write data this clock cycle
    logic write_acked;
    logic write_data_acked;
    assign write_acked = master.aw_ready & master.aw_valid;
    assign write_data_acked = master.w_ready & master.w_valid;

    // Whether there is an pending write transaction
    // caused by simultaneous read & write transaction
    logic pending_write;

    /* BRAM control */

    // Activate bram_en when next state is read complete state or write complete state
    assign bram_en = read_acked | read_data_acked | write_data_acked;

    // Choose correct address depending on next state
    assign bram_addr = read_data_acked ? read_burst_addr :
                    read_acked ? master.ar_addr[UNUSED_ADDR_WIDTH +: BRAM_ADDR_WIDTH] :
                    write_data_acked ? write_burst_addr : {BRAM_ADDR_WIDTH{1'bx}};

    // Wire BRAM's R/W ports directly to AXI
    assign master.r_data = pending_read ? pending_read_data : bram_rddata;
    assign bram_we = write_data_acked ? master.w_strb : 0;
    assign bram_wrdata = write_data_acked ? master.w_data : {DATA_WIDTH{1'bx}};

    always_ff @(posedge clk or negedge resetn)
    begin
        if (!resetn) begin
            // Resets these even if we don't care to suppress warnings.
            read_burst_addr   <= 'x;
            read_burst_len    <= 'x;
            pending_read_data <= 'x;
            write_burst_addr  <= 'x;
            write_burst_len   <= 'x;
            master.r_id       <= 'x;
            master.b_id       <= 'x;

            pending_read   <= 0;
            pending_write  <= 0;
            a_ready        <= 1;
            master.r_valid <= 0;
            master.w_ready <= 0;
            master.b_valid <= 0;
        end
        else if (a_ready) begin
            // We are current on idle state. If we acked either read/write, we will be busy.
            if (read_acked || write_acked)
                a_ready <= 0;

            // If we acked a read this clock cycle.
            if (read_acked) begin
                // Make sure our assumptions are held.
                assert ((master.ar_addr & (DATA_WIDTH / 8-1)) == 0) else $error("Unaligned burst not supported: ar_addr = %x", master.ar_addr);
                assert ((8 << master.ar_size) == DATA_WIDTH) else $error("Narrow burst not supported");
                assert (master.ar_burst == axi_common::BURST_INCR) else $error("Only INCR burst mode is supported");

                // If we acked a read, then on this clock posedge the BRAM will see the address and respond with the data.
                // So valid data should be on r_data wire it after this clock posedge. Therefore we can set valid to high.
                master.r_valid <= 1;

                // Set the address to one word past the requested address and length to requested length - 1.
                // As AXI set ar_len as requested length - 1 it is just a simple assign here.
                read_burst_addr <= master.ar_addr[UNUSED_ADDR_WIDTH +: BRAM_ADDR_WIDTH] + 1;
                read_burst_len <= master.ar_len;

                // Set the reply id.
                master.r_id <= master.ar_id;
            end

            if (write_acked) begin
                // Make sure our assumptions are held.
                assert ((master.aw_addr & (DATA_WIDTH / 8-1)) == 0) else $error("Unaligned burst not supported, aw_addr = %x", master.aw_addr);
                assert ((8 << master.aw_size) == DATA_WIDTH) else $error("Narrow burst not supported");
                assert (master.aw_burst == axi_common::BURST_INCR) else $error("Only INCR burst mode is supported");

                // Set the address and length to the requested address and length.
                write_burst_addr <= master.aw_addr[UNUSED_ADDR_WIDTH +: BRAM_ADDR_WIDTH];
                write_burst_len <= master.aw_len + 1;

                // Set the reply id.
                master.b_id <= master.aw_id;

                if (read_acked)
                    // When read and write arrives together
                    // We process read first and pend the write transaction
                    pending_write  <= 1;
                else
                    // Otherwise we will start writing.
                    // Assert w_ready to begin receiving write data.
                    master.w_ready <= 1;
            end
        end
        else if (master.r_valid) begin
            // If r_valid is high, then we are in reading state. We do not need extra state registers as BRAM can
            // serve value in exactly one clock cycle.

            if (master.r_ready) begin
                pending_read <= 0;

                // If we have already send the last word.
                if (master.r_last) begin
                    master.r_valid <= 0;

                    // If we have pending write transaction, begin that.
                    if (pending_write) begin
                        master.w_ready <= 1;
                        pending_write  <= 0;
                    end
                    else
                        // Otherwise transition to idle
                        a_ready <= 1;
                end
                else begin
                    // Advance address and decrease remaining length
                    read_burst_addr <= read_burst_addr + 1;
                    read_burst_len <= read_burst_len - 1;
                end
            end
            else if (!pending_read) begin
                // If the master is not ready to receive data, we need to buffer the data read.
                pending_read <= 1;
                pending_read_data <= bram_rddata;
            end
        end
        else if (master.w_ready) begin
            // If we are receiving write data, then we are in write state. As BRAM can write one word per clock, we
            // do not need extra state registers for the information.

            if (master.w_valid) begin
                // Last word to write. Unassert ready and assert write complete.
                if (master.w_last) begin
                    master.w_ready <= 0;
                    assert (write_burst_len == 1) else $error("WLAST mismatch with tracked length");

                    // Transition to write complete state
                    master.b_valid <= 1;
                end
                else begin
                    // Otherwise advance address and decrease remaining length
                    write_burst_addr <= write_burst_addr + 1;
                    write_burst_len <= write_burst_len - 1;
                end
            end
        end
        else if (master.b_valid) begin
            // We are in the write complete state.

            if (master.b_ready) begin
                master.b_valid <= 0;

                // Transition to idle state
                a_ready <= 1;
            end
        end
        else
            assert (0) else $error("Something has went wrong");
   end

endmodule
