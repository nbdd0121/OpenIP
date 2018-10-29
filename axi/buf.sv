
module axi_buf #(
    parameter DEPTH         = 1,
    parameter ID_WIDTH      = 8,
    parameter ADDR_WIDTH    = 48,
    parameter DATA_WIDTH    = 64,
    parameter AW_USER_WIDTH = 1,
    parameter AR_USER_WIDTH = 1,
    parameter W_USER_WIDTH  = 1,
    parameter R_USER_WIDTH  = 1,
    parameter B_USER_WIDTH  = 1
) (
    axi_channel.slave  master,
    axi_channel.master slave
);

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // Static checks of interface matching
    initial
        assert (ID_WIDTH == master.ID_WIDTH && ID_WIDTH == slave.ID_WIDTH &&
                ADDR_WIDTH == master.ADDR_WIDTH && ADDR_WIDTH == slave.ADDR_WIDTH &&
                DATA_WIDTH == master.DATA_WIDTH && DATA_WIDTH == slave.DATA_WIDTH &&
                AW_USER_WIDTH == master.AW_USER_WIDTH && AW_USER_WIDTH == slave.AW_USER_WIDTH &&
                AR_USER_WIDTH == master.AR_USER_WIDTH && AR_USER_WIDTH == slave.AR_USER_WIDTH &&
                W_USER_WIDTH == master.W_USER_WIDTH && W_USER_WIDTH == slave.W_USER_WIDTH &&
                R_USER_WIDTH == master.R_USER_WIDTH && R_USER_WIDTH == slave.R_USER_WIDTH &&
                B_USER_WIDTH == master.B_USER_WIDTH && B_USER_WIDTH == slave.B_USER_WIDTH)
        else $fatal(1, "Parameter mismatch");

    //
    // AW channel
    //

    typedef struct packed {
        logic [ID_WIDTH-1:0]      id;
        logic [ADDR_WIDTH-1:0]    addr;
        logic [7:0]               len;
        logic [2:0]               size;
        burst_t                   burst;
        logic                     lock;
        cache_t                   cache;
        prot_t                    prot;
        logic [3:0]               qos;
        logic [3:0]               region;
        logic [AW_USER_WIDTH-1:0] user;
    } aw_pack_t;

    fifo #(
        .TYPE  (aw_pack_t),
        .DEPTH (DEPTH)
    ) awfifo (
        .clk     (master.clk),
        .rstn    (master.rstn),
        .w_valid (master.aw_valid),
        .w_ready (master.aw_ready),
        .w_data  (aw_pack_t'{
            master.aw_id, master.aw_addr, master.aw_len, master.aw_size, master.aw_burst, master.aw_lock,
            master.aw_cache, master.aw_prot, master.aw_qos, master.aw_region, master.aw_user
        }),
        .r_valid (slave.aw_valid),
        .r_ready (slave.aw_ready),
        .r_data  ({
            slave.aw_id, slave.aw_addr, slave.aw_len, slave.aw_size, slave.aw_burst, slave.aw_lock,
            slave.aw_cache, slave.aw_prot, slave.aw_qos, slave.aw_region, slave.aw_user
        })
    );

    //
    // W channel
    //

    typedef struct packed {
        logic [DATA_WIDTH-1:0]    data;
        logic [STRB_WIDTH-1:0]    strb;
        logic                     last;
        logic [W_USER_WIDTH-1:0]  user;
    } w_pack_t;

    fifo #(
        .TYPE  (w_pack_t),
        .DEPTH (DEPTH)
    ) wfifo (
        .clk     (master.clk),
        .rstn    (master.rstn),
        .w_valid (master.w_valid),
        .w_ready (master.w_ready),
        .w_data  (w_pack_t'{master.w_data, master.w_strb, master.w_last, master.w_user}),
        .r_valid (slave.w_valid),
        .r_ready (slave.w_ready),
        .r_data  ({slave.w_data, slave.w_strb, slave.w_last, slave.w_user})
    );

    //
    // B channel
    //

    typedef struct packed {
        logic [ID_WIDTH-1:0]      user;
    } b_pack_t;

    fifo #(
        .TYPE  (b_pack_t),
        .DEPTH (DEPTH)
    ) bfifo (
        .clk     (master.clk),
        .rstn    (master.rstn),
        .w_valid (slave.b_valid),
        .w_ready (slave.b_ready),
        .w_data  (b_pack_t'{slave.b_id, slave.b_resp}),
        .r_valid (master.b_valid),
        .r_ready (master.b_ready),
        .r_data  ({master.b_id, master.b_resp})
    );

    //
    // AR channel
    //

    typedef struct packed {
        logic [ID_WIDTH-1:0]      id;
        logic [ADDR_WIDTH-1:0]    addr;
        logic [7:0]               len;
        logic [2:0]               size;
        burst_t                   burst;
        logic                     lock;
        cache_t                   cache;
        prot_t                    prot;
        logic [3:0]               qos;
        logic [3:0]               region;
        logic [AR_USER_WIDTH-1:0] user;
    } ar_pack_t;

    fifo #(
        .TYPE  (ar_pack_t),
        .DEPTH (DEPTH)
    ) arfifo (
        .clk     (master.clk),
        .rstn    (master.rstn),
        .w_valid (master.ar_valid),
        .w_ready (master.ar_ready),
        .w_data  (ar_pack_t'{
            master.ar_id, master.ar_addr, master.ar_len, master.ar_size, master.ar_burst, master.ar_lock,
            master.ar_cache, master.ar_prot, master.ar_qos, master.ar_region, master.ar_user
        }),
        .r_valid (slave.ar_valid),
        .r_ready (slave.ar_ready),
        .r_data  ({
            slave.ar_id, slave.ar_addr, slave.ar_len, slave.ar_size, slave.ar_burst, slave.ar_lock,
            slave.ar_cache, slave.ar_prot, slave.ar_qos, slave.ar_region, slave.ar_user
        })
    );

    //
    // R channel
    //

    typedef struct packed {
        logic [ID_WIDTH-1:0]     id;
        logic [DATA_WIDTH-1:0]   data;
        resp_t                   resp;
        logic                    last;
        logic [R_USER_WIDTH-1:0] user;
    } r_pack_t;

    fifo #(
        .TYPE  (r_pack_t),
        .DEPTH (DEPTH)
    ) rfifo (
        .clk     (master.clk),
        .rstn    (master.rstn),
        .w_valid (slave.r_valid),
        .w_ready (slave.r_ready),
        .w_data  (r_pack_t'{slave.r_id, slave.r_data, slave.r_resp, slave.r_last, slave.r_user}),
        .r_valid (master.r_valid),
        .r_ready (master.r_ready),
        .r_data  ({master.r_id, master.r_data, master.r_resp, master.r_last, master.r_user})
    );

endmodule
