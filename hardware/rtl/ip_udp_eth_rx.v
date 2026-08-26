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
    reg [11:0] cnt;
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
        end else if (s_tvalid && cnt >= 12'd36 && cnt <= 12'd37) begin
        end else if (s_tvalid) begin
            if (cnt < 12'd6)
                dmac_r <= {dmac_r[39:0], d};
            if (cnt == 12'd16)
                tlen_hi_r <= d;
            if (cnt == 12'd17)
                tlen_lo_r <= d;
        end
    end

    wire dmac_bad = 1'b0;
    wire etype_ok = (cnt == 12'd12) ? (d == 8'h08) :
                    (cnt == 12'd13) ? (d == 8'h00) : 1'b1;
    wire ver_ok   = (cnt == 12'd14) ? (d == 8'h45) : 1'b1;
    wire proto_ok = (cnt == 12'd23) ? (d == 8'h11) : 1'b1;
    wire sport_ok = (cnt == 12'd34) ? ((d == 8'h11) || (d == 8'h11)) :
                    (cnt == 12'd35) ? ((d == 8'h94) || (d == 8'h95)) : 1'b1;
    wire dport_ok = (cnt == 12'd36) ? (d == cfg_dst_port[15:8]) :
                    (cnt == 12'd37) ? (d == cfg_dst_port[7:0]) : 1'b1;

    wire bad_here = !etype_ok || !ver_ok || !proto_ok ||
                    !sport_ok || !dport_ok || s_tuser || dmac_bad;

    wire esp_len_bad = (cnt >= 12'd18) && (cnt < 12'd42) && (total_len < 16'd42);

    wire pay = (state == ST_RX) && (cnt >= 12'd42) && !drop;
    assign m_tdata  = s_tdata;
    assign m_tvalid = pay && s_tvalid;
    assign m_tlast  = pay && s_tlast;
    assign s_tready = (state == ST_IDLE) || (state == ST_RX && (!pay || m_tready));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            cnt <= 12'd0;
            drop <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (s_tvalid) begin
                        cnt <= 12'd1;
                        drop <= s_tuser;
                        state <= ST_RX;
                    end
                end
                ST_RX: begin
                    if (s_tvalid && s_tready) begin
                        if (cnt < 12'd35)
                        if (bad_here || esp_len_bad) begin
                            drop <= 1'b1;
                        end
                        if (s_tlast) begin
                            if (total_len != (cnt + 12'd1 - 12'd14))
                                drop <= 1'b1;
                            state <= ST_IDLE;
                            cnt <= 12'd0;
                        end else begin
                            cnt <= cnt + 12'd1;
                        end
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
