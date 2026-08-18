module dual_mac_top #(
    parameter MAC_TARGET = "GOWIN"
) (
    input  wire clk,
    input  wire rst_n,
    input  wire gtx_clk,
    input  wire gtx_clk90,

    input  wire          wan_rgmii_rx_clk,
    input  wire [3:0]    wan_rgmii_rxd,
    input  wire          wan_rgmii_rx_ctl,
    output wire          wan_rgmii_tx_clk,
    output wire [3:0]    wan_rgmii_txd,
    output wire          wan_rgmii_tx_ctl,

    input  wire          lan_rgmii_rx_clk,
    input  wire [3:0]    lan_rgmii_rxd,
    input  wire          lan_rgmii_rx_ctl,
    output wire          lan_rgmii_tx_clk,
    output wire [3:0]    lan_rgmii_txd,
    output wire          lan_rgmii_tx_ctl
);

    wire logic_rst = ~rst_n;
    wire [7:0] wan_tx_data, wan_rx_data;
    wire       wan_tx_valid, wan_tx_ready, wan_tx_last;
    wire       wan_rx_valid, wan_rx_ready, wan_rx_last, wan_rx_user;
    wire [7:0] lan_tx_data, lan_rx_data;
    wire       lan_tx_valid, lan_tx_ready, lan_tx_last;
    wire       lan_rx_valid, lan_rx_ready, lan_rx_last, lan_rx_user;

    eth_mac_1g_rgmii_fifo #(
        .TARGET(MAC_TARGET),
        .IODDR_STYLE("IODDR"),
        .CLOCK_INPUT_STYLE("BUFG"),
        .USE_CLK90("TRUE"),
        .AXIS_DATA_WIDTH(8),
        .TX_FIFO_DEPTH(4096),
        .RX_FIFO_DEPTH(4096),
        .ENABLE_PADDING(1),
        .MIN_FRAME_LENGTH(64)
    ) u_wan_mac (
        .gtx_clk(gtx_clk), .gtx_clk90(gtx_clk90), .gtx_rst(logic_rst),
        .logic_clk(clk), .logic_rst(logic_rst),
        .tx_axis_tdata(wan_tx_data), .tx_axis_tkeep(1'b1),
        .tx_axis_tvalid(wan_tx_valid), .tx_axis_tready(wan_tx_ready),
        .tx_axis_tlast(wan_tx_last), .tx_axis_tuser(1'b0),
        .rx_axis_tdata(wan_rx_data), .rx_axis_tkeep(),
        .rx_axis_tvalid(wan_rx_valid), .rx_axis_tready(wan_rx_ready),
        .rx_axis_tlast(wan_rx_last), .rx_axis_tuser(wan_rx_user),
        .rgmii_rx_clk(wan_rgmii_rx_clk), .rgmii_rxd(wan_rgmii_rxd),
        .rgmii_rx_ctl(wan_rgmii_rx_ctl),
        .rgmii_tx_clk(wan_rgmii_tx_clk), .rgmii_txd(wan_rgmii_txd),
        .rgmii_tx_ctl(wan_rgmii_tx_ctl),
        .tx_error_underflow(), .tx_fifo_overflow(), .tx_fifo_bad_frame(),
        .tx_fifo_good_frame(), .rx_error_bad_frame(), .rx_error_bad_fcs(),
        .rx_fifo_overflow(), .rx_fifo_bad_frame(), .rx_fifo_good_frame(),
        .speed(), .cfg_ifg(8'h0c), .cfg_tx_enable(1'b1), .cfg_rx_enable(1'b1)
    );

    eth_mac_1g_rgmii_fifo #(
        .TARGET(MAC_TARGET),
        .IODDR_STYLE("IODDR"),
        .CLOCK_INPUT_STYLE("BUFG"),
        .USE_CLK90("TRUE"),
        .AXIS_DATA_WIDTH(8),
        .TX_FIFO_DEPTH(4096),
        .RX_FIFO_DEPTH(4096),
        .ENABLE_PADDING(1),
        .MIN_FRAME_LENGTH(64)
    ) u_lan_mac (
        .gtx_clk(gtx_clk), .gtx_clk90(gtx_clk90), .gtx_rst(logic_rst),
        .logic_clk(clk), .logic_rst(logic_rst),
        .tx_axis_tdata(lan_tx_data), .tx_axis_tkeep(1'b1),
        .tx_axis_tvalid(lan_tx_valid), .tx_axis_tready(lan_tx_ready),
        .tx_axis_tlast(lan_tx_last), .tx_axis_tuser(1'b0),
        .rx_axis_tdata(lan_rx_data), .rx_axis_tkeep(),
        .rx_axis_tvalid(lan_rx_valid), .rx_axis_tready(lan_rx_ready),
        .rx_axis_tlast(lan_rx_last), .rx_axis_tuser(lan_rx_user),
        .rgmii_rx_clk(lan_rgmii_rx_clk), .rgmii_rxd(lan_rgmii_rxd),
        .rgmii_rx_ctl(lan_rgmii_rx_ctl),
        .rgmii_tx_clk(lan_rgmii_tx_clk), .rgmii_txd(lan_rgmii_txd),
        .rgmii_tx_ctl(lan_rgmii_tx_ctl),
        .tx_error_underflow(), .tx_fifo_overflow(), .tx_fifo_bad_frame(),
        .tx_fifo_good_frame(), .rx_error_bad_frame(), .rx_error_bad_fcs(),
        .rx_fifo_overflow(), .rx_fifo_bad_frame(), .rx_fifo_good_frame(),
        .speed(), .cfg_ifg(8'h0c), .cfg_tx_enable(1'b1), .cfg_rx_enable(1'b1)
    );

    assign wan_tx_data  = lan_rx_data;
    assign wan_tx_valid = lan_rx_valid;
    assign wan_tx_last  = lan_rx_last;
    assign lan_rx_ready = wan_tx_ready;
    assign lan_tx_data  = wan_rx_data;
    assign lan_tx_valid = wan_rx_valid;
    assign lan_tx_last  = wan_rx_last;
    assign wan_rx_ready = lan_tx_ready;

endmodule
