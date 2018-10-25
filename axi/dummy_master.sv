module axi_dummy_master (
    axi_channel.master slave
);

    assign slave.aw_id = 0;
    assign slave.aw_addr = 0;
    assign slave.aw_len = 0;
    assign slave.aw_size = 0;
    assign slave.aw_burst = 0;
    assign slave.aw_lock = 0;
    assign slave.aw_cache = 0;
    assign slave.aw_prot = 0;
    assign slave.aw_qos = 0;
    assign slave.aw_region = 0;
    assign slave.aw_user = 0;
    assign slave.aw_valid = 0;

    assign slave.ar_id = 0;
    assign slave.ar_addr = 0;
    assign slave.ar_len = 0;
    assign slave.ar_size = 0;
    assign slave.ar_burst = 0;
    assign slave.ar_lock = 0;
    assign slave.ar_cache = 0;
    assign slave.ar_prot = 0;
    assign slave.ar_qos = 0;
    assign slave.ar_region = 0;
    assign slave.ar_user = 0;
    assign slave.ar_valid = 0;

    assign slave.w_data = 0;
    assign slave.w_strb = 0;
    assign slave.w_last = 0;
    assign slave.w_user = 0;
    assign slave.w_valid = 0;

    assign slave.r_ready = 0;

    assign slave.b_ready = 0;

endmodule
