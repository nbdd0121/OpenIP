    //
    // Useful packed structs for IPs to use
    //
    typedef struct packed {
        logic [`ID_WIDTH-1:0]      id;
        logic [`ADDR_WIDTH-1:0]    addr;
        logic [7:0]               len;
        logic [2:0]               size;
        burst_t                   burst;
        logic                     lock;
        cache_t                   cache;
        prot_t                    prot;
        logic [3:0]               qos;
        logic [3:0]               region;
        logic [`AW_USER_WIDTH-1:0] user;
    } aw_pack_t;

    typedef struct packed {
        logic [`DATA_WIDTH-1:0]    data;
        logic [`DATA_WIDTH/8-1:0]    strb;
        logic                     last;
        logic [`W_USER_WIDTH-1:0]  user;
    } w_pack_t;

    typedef struct packed {
        logic [`ID_WIDTH-1:0]      id;
        resp_t                    resp;
        logic [`B_USER_WIDTH-1:0]      user;
    } b_pack_t;

    typedef struct packed {
        logic [`ID_WIDTH-1:0]      id;
        logic [`ADDR_WIDTH-1:0]    addr;
        logic [7:0]               len;
        logic [2:0]               size;
        burst_t                   burst;
        logic                     lock;
        cache_t                   cache;
        prot_t                    prot;
        logic [3:0]               qos;
        logic [3:0]               region;
        logic [`AR_USER_WIDTH-1:0] user;
    } ar_pack_t;

    typedef struct packed {
        logic [`ID_WIDTH-1:0]     id;
        logic [`DATA_WIDTH-1:0]   data;
        resp_t                   resp;
        logic                    last;
        logic [`R_USER_WIDTH-1:0] user;
    } r_pack_t;

    //
    // Useful packed structs for IPs to use
    //
    typedef struct packed {
        logic [`ADDR_WIDTH-1:0]    addr;
        prot_t                    prot;
    } ax_pack_t;

    typedef struct packed {
        logic [`DATA_WIDTH-1:0]    data;
        logic [`DATA_WIDTH/8-1:0]    strb;
    } lw_pack_t;

    typedef struct packed {
        logic [`DATA_WIDTH-1:0]   data;
        resp_t                   resp;
    } lr_pack_t;

`undef ID_WIDTH
`undef ADDR_WIDTH
`undef DATA_WIDTH
`undef AW_USER_WIDTH
`undef W_USER_WIDTH
`undef B_USER_WIDTH
`undef AR_USER_WIDTH
`undef R_USER_WIDTH

