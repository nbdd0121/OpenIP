module axi_lite_dummy_master
(
    axi_lite_channel.master slave
);

    assign slave.aw_addr = 0;
    assign slave.aw_prot = 0;
    assign slave.aw_valid = 0;

    assign slave.ar_addr = 0;
    assign slave.ar_prot = 0;
    assign slave.ar_valid = 0;

    assign slave.w_data = 0;
    assign slave.w_strb = 0;
    assign slave.w_valid = 0;

    assign slave.r_ready = 0;

    assign slave.b_ready = 0;

endmodule
