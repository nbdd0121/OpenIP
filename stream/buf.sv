
module stream_buf #(
    parameter DEPTH      = 1,
    parameter ID_WIDTH   = 1,
    parameter DATA_WIDTH = 64,
    parameter DEST_WIDTH = 1,
    parameter USER_WIDTH = 1
) (
    stream_channel.slave  master,
    stream_channel.master slave
);

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // Static checks of interface matching
    initial
        assert (ID_WIDTH == master.ID_WIDTH && ID_WIDTH == slave.ID_WIDTH &&
                DATA_WIDTH == master.DATA_WIDTH && DATA_WIDTH == slave.DATA_WIDTH &&
                DEST_WIDTH == master.DEST_WIDTH && DEST_WIDTH == slave.DEST_WIDTH &&
                USER_WIDTH == master.USER_WIDTH && USER_WIDTH == slave.USER_WIDTH)
        else $fatal(1, "Parameter mismatch");

    typedef struct packed {
        logic [ID_WIDTH-1:0]   id;
        logic [DEST_WIDTH-1:0] dest;
        logic [DATA_WIDTH-1:0] data;
        logic [STRB_WIDTH-1:0] strb;
        logic [STRB_WIDTH-1:0] keep;
        logic                  last;
        logic [USER_WIDTH-1:0] user;
    } pack_t;

    fifo #(
        .TYPE  (pack_t),
        .DEPTH (DEPTH)
    ) fifo (
        .clk     (master.clk),
        .rstn    (master.rstn),
        .w_valid (master.t_valid),
        .w_ready (master.t_ready),
        .w_data  (pack_t'{master.t_id, master.t_dest, master.t_data, master.t_strb, master.t_keep, master.t_last, master.t_user}),
        .r_valid (slave.t_valid),
        .r_ready (slave.t_ready),
        .r_data  ({slave.t_id, slave.t_dest, slave.t_data, slave.t_strb, slave.t_keep, slave.t_last, slave.t_user})
    );

endmodule
