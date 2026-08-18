module ip_udp_eth_rx (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [7:0]    s_tdata,
    input  wire          s_tvalid,
    input  wire          s_tlast,
    output wire          s_tready,
    input  wire          s_tuser,

    input  wire [47:0]   cfg_dst_mac,
    input  wire [15:0]   cfg_dst_port,

    output wire [7:0]    m_tdata,
    output wire          m_tvalid,
    output wire          m_tlast,
    input  wire          m_tready
);

    localparam ST_IDLE = 1'b0;
    localparam ST_RX   = 1'b1;

    reg       state;
    reg [8:0] cnt;
    reg       drop;
    reg [47:0] dmac_r;
    reg [7:0]  tlen_hi_r;
    reg [7:0]  tlen_lo_r;

    wire [7:0] d = s_tdata;
    wire [15:0] total_len = {tlen_hi_r, tlen_lo_r};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmac_r <= 48'd0;
            tlen_hi_r <= 8'd0;
            tlen_lo_r <= 8'd0;
        end else if (s_tvalid) begin
            if (cnt < 9'd6)
                dmac_r <= {dmac_r[39:0], d};
            if (cnt == 9'd16)
                tlen_hi_r <= d;
            if (cnt == 9'd17)
                tlen_lo_r <= d;
        end
    end

    wire dmac_bad = (cnt == 9'd6) &&
                    (dmac_r != cfg_dst_mac) &&
                    (dmac_r != 48'hFFFFFFFFFFFF);
    wire etype_ok = (cnt == 9'd12) ? (d == 8'h08) :
                    (cnt == 9'd13) ? (d == 8'h00) : 1'b1;
    wire ver_ok   = (cnt == 9'd14) ? (d == 8'h45) : 1'b1;
    wire proto_ok = (cnt == 9'd23) ? (d == 8'h11) : 1'b1;
    wire sport_ok = (cnt == 9'd34) ? (d == 8'h11) :
                    (cnt == 9'd35) ? (d == 8'h94) : 1'b1;
    wire dport_ok = (cnt == 9'd36) ? (d == cfg_dst_port[15:8]) :
                    (cnt == 9'd37) ? (d == cfg_dst_port[7:0]) : 1'b1;

    wire bad_here = !etype_ok || !ver_ok || !proto_ok ||
                    !sport_ok || !dport_ok || s_tuser || dmac_bad;

    wire esp_len_bad = (cnt >= 9'd18) && (cnt < 9'd42) &&
                       ((total_len < 16'd42) || ((total_len - 16'd42) > 16'd255));

    wire pay = (state == ST_RX) && (cnt >= 9'd42) && !drop;
    assign m_tdata  = s_tdata;
    assign m_tvalid = pay && s_tvalid;
    assign m_tlast  = pay && s_tlast;
    assign s_tready = (state == ST_IDLE) || (state == ST_RX && (!pay || m_tready));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            cnt <= 9'd0;
            drop <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (s_tvalid) begin
                        cnt <= 9'd1;
                        drop <= s_tuser;
                        state <= ST_RX;
                    end
                end
                ST_RX: begin
                    if (s_tvalid) begin
                        if (bad_here || esp_len_bad)
                            drop <= 1'b1;
                        if (s_tlast) begin
                            if (total_len != (cnt + 9'd1 - 9'd14))
                                drop <= 1'b1;
                            state <= ST_IDLE;
                            cnt <= 9'd0;
                        end else begin
                            cnt <= cnt + 9'd1;
                        end
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
