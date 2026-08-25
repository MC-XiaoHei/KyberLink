module lan_rx_mux (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] s_tdata,
    input  wire       s_tvalid,
    input  wire       s_tlast,
    output wire       s_tready,

    input  wire [15:0] hs_dport,

    output wire [7:0] m_enc_data,
    output wire       m_enc_valid,
    output wire       m_enc_last,
    input  wire       m_enc_ready,

    output wire [7:0] m_mgmt_data,
    output wire       m_mgmt_valid,
    output wire       m_mgmt_last,
    input  wire       m_mgmt_ready,

    output wire [7:0] m_hs_data,
    output wire       m_hs_valid,
    output wire       m_hs_last,
    input  wire       m_hs_ready
);

    localparam R_ENC  = 2'd0;
    localparam R_MGMT = 2'd1;
    localparam R_HS   = 2'd2;

    reg [10:0] wptr;
    reg [10:0] rcnt;
    reg [10:0] rlen;
    reg [1:0]  route;
    reg        frame_vld;
    reg        rx_busy;
    reg [10:0] rx_cnt;
    reg        r_tcp;
    reg        r_ip;
    reg [7:0]  dport_hi;

    wire [15:0] dport_w = {dport_hi, s_tdata};
    wire sel_mgmt = r_ip && r_tcp && dport_w == 16'd80;
    wire sel_hs = r_ip && !r_tcp && dport_w == hs_dport;

    wire wr_en = s_tvalid && (rx_busy || !frame_vld);
    (* syn_ramstyle = "block" *) reg [7:0] fbuf [0:2047];
    reg [7:0] rd_data;

    always @(posedge clk) begin
        rd_data <= fbuf[rcnt];
    end

    assign s_tready = !frame_vld;

    reg m_enc_valid_r;
    reg m_enc_last_r;
    reg m_mgmt_valid_r;
    reg m_mgmt_last_r;
    reg m_hs_valid_r;
    reg m_hs_last_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr <= 11'd0;
            rcnt <= 11'd0;
            rlen <= 11'd0;
            route <= R_ENC;
            frame_vld <= 1'b0;
            rx_busy <= 1'b0;
            rx_cnt <= 11'd0;
            r_tcp <= 1'b0;
            r_ip <= 1'b0;
            dport_hi <= 8'd0;
            m_enc_valid_r <= 1'b0;
            m_enc_last_r <= 1'b0;
            m_mgmt_valid_r <= 1'b0;
            m_mgmt_last_r <= 1'b0;
            m_hs_valid_r <= 1'b0;
            m_hs_last_r <= 1'b0;
        end else begin
            if (wr_en) begin
                fbuf[wptr] <= s_tdata;
            end
            if (rx_busy && s_tvalid) begin
                wptr <= wptr + 11'd1;
                case (rx_cnt)
                    11'd12: r_ip <= (s_tdata == 8'h08);
                    11'd13: r_ip <= r_ip && (s_tdata == 8'h00);
                    11'd14: r_ip <= r_ip && (s_tdata == 8'h45);
                    11'd23: r_tcp <= (s_tdata == 8'h06);
                    11'd36: dport_hi <= s_tdata;
                    11'd37: route <= sel_mgmt ? R_MGMT : (sel_hs ? R_HS : R_ENC);
                    default: ;
                endcase
                if (s_tlast) begin
                    rlen <= rx_cnt + 11'd1;
                    rcnt <= 11'd0;
                    frame_vld <= 1'b1;
                    rx_busy <= 1'b0;
                end else begin
                    rx_cnt <= rx_cnt + 11'd1;
                end
            end else if (s_tvalid) begin
                wptr <= 11'd1;
                rx_cnt <= 11'd1;
                r_ip <= (s_tdata == 8'h08);
                rx_busy <= 1'b1;
            end
            if (frame_vld && (rcnt < rlen)) begin
                case (route)
                    R_HS: begin
                        if ((rcnt >= 11'd42) && m_hs_ready) begin
                            rcnt <= rcnt + 11'd1;
                            if (rcnt == rlen - 11'd1)
                                frame_vld <= 1'b0;
                        end else if (rcnt < 11'd42) begin
                            rcnt <= rcnt + 11'd1;
                            if (rcnt == rlen - 11'd1)
                                frame_vld <= 1'b0;
                        end
                    end
                    R_ENC: begin
                        if (m_enc_ready) begin
                            rcnt <= rcnt + 11'd1;
                            if (rcnt == rlen - 11'd1)
                                frame_vld <= 1'b0;
                        end
                    end
                    default: begin
                        if (m_mgmt_ready) begin
                            rcnt <= rcnt + 11'd1;
                            if (rcnt == rlen - 11'd1)
                                frame_vld <= 1'b0;
                        end
                    end
                endcase
            end
            m_enc_valid_r <= frame_vld && (route == R_ENC) && (rcnt < rlen);
            m_enc_last_r  <= frame_vld && (route == R_ENC) && (rcnt == rlen - 11'd1);
            m_mgmt_valid_r <= frame_vld && (route == R_MGMT) && (rcnt < rlen);
            m_mgmt_last_r  <= frame_vld && (route == R_MGMT) && (rcnt == rlen - 11'd1);
            m_hs_valid_r   <= frame_vld && (route == R_HS) && (rcnt >= 11'd42) && (rcnt < rlen);
            m_hs_last_r    <= frame_vld && (route == R_HS) && (rcnt >= 11'd42) && (rcnt == rlen - 11'd1);
        end
    end

    assign m_enc_data = rd_data;
    assign m_enc_valid = m_enc_valid_r;
    assign m_enc_last = m_enc_last_r;
    assign m_mgmt_data = rd_data;
    assign m_mgmt_valid = m_mgmt_valid_r;
    assign m_mgmt_last = m_mgmt_last_r;
    assign m_hs_data = rd_data;
    assign m_hs_valid = m_hs_valid_r;
    assign m_hs_last = m_hs_last_r;

endmodule