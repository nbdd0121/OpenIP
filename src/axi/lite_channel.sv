interface axi_lite_channel #(
    ADDR_WIDTH = 48,
    DATA_WIDTH = 64
);

    logic [ADDR_WIDTH-1:0]      aw_addr;
    logic [2:0]                 aw_prot;
    logic                       aw_valid;
    logic                       aw_ready;

    logic [ADDR_WIDTH-1:0]      ar_addr;
    logic [2:0]                 ar_prot;
    logic                       ar_valid;
    logic                       ar_ready;

    logic [DATA_WIDTH-1:0]      w_data;
    logic [DATA_WIDTH/8-1:0]    w_strb;
    logic                       w_valid;
    logic                       w_ready;

    logic [DATA_WIDTH-1:0]      r_data;
    logic [1:0]                 r_resp;
    logic                       r_valid;
    logic                       r_ready;

    logic [1:0]                 b_resp;
    logic                       b_valid;
    logic                       b_ready;

    modport master (
        output aw_addr,
        output aw_prot,
        output aw_valid,
        input  aw_ready,

        output ar_addr,
        output ar_prot,
        output ar_valid,
        input  ar_ready,

        output w_data,
        output w_strb,
        output w_valid,
        input  w_ready,

        input  r_data,
        input  r_resp,
        input  r_valid,
        output r_ready,

        input  b_resp,
        input  b_valid,
        output b_ready
    );

    modport slave (
        input  aw_addr,
        input  aw_prot,
        input  aw_valid,
        output aw_ready,

        input  ar_addr,
        input  ar_prot,
        input  ar_valid,
        output ar_ready,

        input  w_data,
        input  w_strb,
        input  w_valid,
        output w_ready,

        output r_data,
        output r_resp,
        output r_valid,
        input  r_ready,

        output b_resp,
        output b_valid,
        input  b_ready
    );

endinterface

