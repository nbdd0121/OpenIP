module axi_from_lite #(
    ADDR_WIDTH = 48,
    DATA_WIDTH = 64
) (
    axi_lite_channel.slave master,
    axi_channel.master slave
);

    assign slave.aw_id = 0;
    assign slave.aw_addr = master.aw_addr;
    assign slave.aw_len = 0;
    assign slave.aw_size = $clog2(DATA_WIDTH / 8);
    assign slave.aw_burst = 1;
    assign slave.aw_lock = 0;
    assign slave.aw_cache = 0;
    assign slave.aw_prot = master.aw_prot;
    assign slave.aw_qos = 0;
    assign slave.aw_region = 0;
    assign slave.aw_user = 0;
    assign slave.aw_valid = master.aw_valid;
    assign master.aw_ready = slave.aw_ready;  

    assign slave.ar_id = 0;
    assign slave.ar_addr = master.ar_addr;
    assign slave.ar_len = 0;
    assign slave.ar_size = $clog2(DATA_WIDTH / 8);
    assign slave.ar_burst = 0;
    assign slave.ar_lock = 0;
    assign slave.ar_cache = 0;
    assign slave.ar_prot = master.ar_prot;
    assign slave.ar_qos = 0;
    assign slave.ar_region = 0;
    assign slave.ar_user = 0;
    assign slave.ar_valid = master.ar_valid;
    assign master.ar_ready = slave.ar_ready;

    assign slave.w_data = master.w_data;
    assign slave.w_strb = master.w_strb;
    assign slave.w_last = 1;
    assign slave.w_user = 0;
    assign slave.w_valid = master.w_valid;
    assign master.w_ready = slave.w_ready;

    assign master.r_data = slave.r_data;
    // r_last is discarded
    // r_id is discarded
    assign master.r_resp = slave.r_resp;
    // r_user is discarded
    assign master.r_valid = slave.r_valid;
    assign slave.r_ready = master.r_ready;

    // b_id is discarded
    assign master.b_resp = slave.b_resp;
    // b_user is discarded
    assign master.b_valid = slave.b_valid;
    assign slave.b_ready = master.b_ready;

endmodule
