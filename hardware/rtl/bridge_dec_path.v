module bridge_dec_path (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [7:0]    s_tdata,
    input  wire          s_tvalid,
    input  wire          s_tlast,
    output wire          s_tready,

    input  wire [255:0]  key,

    input  wire          gcm_grant,
    output reg           gcm_req,
    output reg           gcm_start,
    output reg  [11:0]   gcm_pt_len,
    output reg  [95:0]   gcm_nonce,
    output reg  [127:0]  gcm_aad,
    output wire          gcm_pt_valid,
    input  wire          gcm_pt_ready,
    output wire [127:0]  gcm_pt_data,
    input  wire          gcm_ct_valid,
    output wire          gcm_ct_ready,
    input  wire [127:0]  gcm_ct_data,
    input  wire          gcm_tag_valid,
    input  wire [127:0]  gcm_tag,
    input  wire          gcm_tag_ok,
    input  wire          gcm_busy,
    input  wire          gcm_done,

    output wire [7:0]    m_tdata,
    output wire          m_tvalid,
    output wire          m_tlast,
    input  wire          m_tready,
    output reg           tag_ok,
    output wire [127:0]  tag_in_w
);

    localparam ST_IDLE = 2'd0;
    localparam ST_RX   = 2'd1;
    localparam ST_RUN  = 2'd2;

    reg [1:0] state;

    (* syn_ramstyle = "block" *) reg [127:0] frm_buf [0:95];
    reg         frm_wr_pend;
    reg [6:0]   frm_wr_addr;
    reg [127:0] frm_wr_data;
    reg [31:0] spi_r;
    reg [31:0] seq_r;
    reg [95:0] iv_r;
    reg [143:0] tail18;
    reg [127:0] blk_acc;
    reg [11:0]  fcnt;
    reg [11:0]  frm_len;
    reg [11:0]  ct_len;
    reg [7:0]   pt_idx;
    reg [7:0]   pt_rd_addr;
    reg [127:0] pt_rd_data;
    reg         pt_req;
    reg         pt_data_v;
    reg [127:0] tx_blk;
    reg [3:0]   tx_b;
    reg         tx_blk_v;
    reg [127:0] ct_hold;
    reg         ct_hold_v;
    reg         grant_used;
    reg [15:0]  tx_cnt;
    reg         tag_ok_r;

    wire [11:0] ct_len_w = fcnt + 12'd1 - 12'd38;
    wire [8:0]  nct = {1'b0, ct_len_w[11:4]} + {8'd0, |ct_len_w[3:0]};
    wire [15:0] frame_n = {4'd0, ct_len_w};

    wire [127:0] tag_w = tail18[127:0];
    assign tag_in_w = tag_w;

    assign gcm_pt_valid = pt_data_v;
    assign gcm_pt_data  = pt_rd_data;
    assign s_tready = (state == ST_IDLE) || (state == ST_RX);

    always @(posedge clk) begin
        pt_rd_data <= frm_buf[pt_rd_addr];
    end

    assign m_tdata = tx_blk[127:120];
    assign m_tvalid = (state == ST_RUN) && tx_blk_v && (tx_cnt < frame_n);
    assign m_tlast = (state == ST_RUN) && tx_blk_v && (tx_cnt == frame_n - 16'd1);
    assign gcm_ct_ready = gcm_ct_valid && !ct_hold_v;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            spi_r <= 32'd0;
            seq_r <= 32'd0;
            iv_r <= 96'd0;
            tail18 <= 144'd0;
            blk_acc <= 128'd0;
            frm_wr_pend <= 1'b0;
            frm_wr_addr <= 7'd0;
            frm_wr_data <= 128'd0;
            fcnt <= 12'd0;
            frm_len <= 12'd0;
            ct_len <= 12'd0;
            pt_idx <= 8'd0;
            pt_rd_addr <= 8'd0;
            pt_req <= 1'b0;
            pt_data_v <= 1'b0;
            tx_blk <= 128'd0;
            tx_b <= 4'd0;
            tx_blk_v <= 1'b0;
            ct_hold <= 128'd0;
            ct_hold_v <= 1'b0;
            grant_used <= 1'b0;
            tx_cnt <= 16'd0;
            tag_ok_r <= 1'b0;
            tag_ok <= 1'b0;
            gcm_req <= 1'b0;
            gcm_start <= 1'b0;
            gcm_pt_len <= 12'd0;
            gcm_nonce <= 96'd0;
            gcm_aad <= 128'd0;
        end else begin
            gcm_start <= 1'b0;
            if (gcm_tag_valid) begin
                tag_ok_r <= gcm_tag_ok;
                tag_ok <= gcm_tag_ok;
            end
            case (state)
                ST_IDLE: begin
                    if (s_tvalid) begin
                        tail18 <= {tail18[135:0], s_tdata};
                        spi_r[31 - 8*fcnt[1:0] -: 8] <= s_tdata;
                        fcnt <= 12'd1;
                        blk_acc <= {120'd0, s_tdata};
                        state <= ST_RX;
                    end
                end
                ST_RX: begin
                    if (s_tvalid) begin
                        tail18 <= {tail18[135:0], s_tdata};
                        if (fcnt < 12'd4)
                            spi_r[31 - 8*fcnt[1:0] -: 8] <= s_tdata;
                        else if (fcnt < 12'd8)
                            seq_r[31 - 8*(fcnt - 12'd4) -: 8] <= s_tdata;
                        else if (fcnt < 12'd20)
                            iv_r[95 - 8*(fcnt - 12'd8) -: 8] <= s_tdata;
                        else begin
                            if (fcnt[3:0] == 4'd3) begin
                                frm_buf[(fcnt - 12'd20) >> 4] <= {blk_acc[119:0], s_tdata};
                                blk_acc <= 128'd0;
                            end else begin
                                blk_acc <= {blk_acc[119:0], s_tdata};
                            end
                        end
                        if (s_tlast) begin
                            if (fcnt[3:0] != 4'd3) begin
                                frm_wr_pend <= 1'b1;
                                frm_wr_addr <= (fcnt - 12'd20) >> 4;
                                case (fcnt[3:0] - 4'd3)
                                    4'd1:  frm_wr_data <= {s_tdata, 120'd0};
                                    4'd2:  frm_wr_data <= {blk_acc[7:0], s_tdata, 112'd0};
                                    4'd3:  frm_wr_data <= {blk_acc[15:8], blk_acc[7:0], s_tdata, 104'd0};
                                    4'd4:  frm_wr_data <= {blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 96'd0};
                                    4'd5:  frm_wr_data <= {blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 88'd0};
                                    4'd6:  frm_wr_data <= {blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 80'd0};
                                    4'd7:  frm_wr_data <= {blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 72'd0};
                                    4'd8:  frm_wr_data <= {blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 64'd0};
                                    4'd9:  frm_wr_data <= {blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 56'd0};
                                    4'd10: frm_wr_data <= {blk_acc[71:64], blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 48'd0};
                                    4'd11: frm_wr_data <= {blk_acc[79:72], blk_acc[71:64], blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 40'd0};
                                    4'd12: frm_wr_data <= {blk_acc[87:80], blk_acc[79:72], blk_acc[71:64], blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 32'd0};
                                    4'd13: frm_wr_data <= {blk_acc[95:88], blk_acc[87:80], blk_acc[79:72], blk_acc[71:64], blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 24'd0};
                                    4'd14: frm_wr_data <= {blk_acc[103:96], blk_acc[95:88], blk_acc[87:80], blk_acc[79:72], blk_acc[71:64], blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 16'd0};
                                    default: frm_wr_data <= {blk_acc[111:104], blk_acc[103:96], blk_acc[95:88], blk_acc[87:80], blk_acc[79:72], blk_acc[71:64], blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 8'd0};
                                endcase
                            end
                            frm_len <= fcnt + 12'd1;
                            ct_len <= fcnt + 12'd1 - 12'd38;
                            gcm_req <= 1'b1;
                            state <= ST_RUN;
                        end else begin
                            fcnt <= fcnt + 12'd1;
                        end
                    end
                end
                ST_RUN: begin
                    if (frm_wr_pend) begin
                        frm_buf[frm_wr_addr] <= frm_wr_data;
                        frm_wr_pend <= 1'b0;
                    end
                    if (gcm_grant && !grant_used) begin
                        grant_used <= 1'b1;
                        gcm_req <= 1'b0;
                        gcm_start <= 1'b1;
                        gcm_pt_len <= ct_len;
                        gcm_nonce <= iv_r;
                        gcm_aad <= {spi_r, seq_r, 64'd0};
                        pt_idx <= 8'd0;
                        pt_req <= 1'b0;
                        pt_data_v <= 1'b0;
                        tx_cnt <= 16'd0;
                        tx_blk_v <= 1'b0;
                        ct_hold_v <= 1'b0;
                        tag_ok_r <= 1'b0;
                    end
                    if (gcm_pt_ready && !pt_req && !pt_data_v && (pt_idx < nct[7:0])) begin
                        pt_rd_addr <= pt_idx;
                        pt_req <= 1'b1;
                    end
                    if (pt_req && !pt_data_v) begin
                        pt_data_v <= 1'b1;
                    end
                    if (pt_data_v && gcm_pt_ready) begin
                        pt_req <= 1'b0;
                        pt_data_v <= 1'b0;
                        pt_idx <= pt_idx + 8'd1;
                    end
                    if (gcm_ct_valid && !ct_hold_v) begin
                        ct_hold <= gcm_ct_data;
                        ct_hold_v <= 1'b1;
                    end
                    if (m_tready && tx_blk_v) begin
                        if (tx_cnt == frame_n - 16'd1) begin
                            state <= ST_IDLE;
                            grant_used <= 1'b0;
                        end else begin
                            tx_cnt <= tx_cnt + 16'd1;
                            tx_blk <= {tx_blk[119:0], 8'd0};
                            if (tx_b == 4'd15) begin
                                tx_blk_v <= 1'b0;
                                tx_b <= 4'd0;
                            end else begin
                                tx_b <= tx_b + 4'd1;
                            end
                        end
                    end
                    if (!tx_blk_v && ct_hold_v) begin
                        tx_blk <= ct_hold;
                        tx_blk_v <= 1'b1;
                        tx_b <= 4'd0;
                        ct_hold_v <= 1'b0;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
