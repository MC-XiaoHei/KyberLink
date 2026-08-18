module ip_udp_eth_tx #(
    parameter FRAME_BUF_DEPTH = 512,
    parameter ETH_IP_PROTO = 8'h11
) (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [47:0]   cfg_src_mac,
    input  wire [47:0]   cfg_dst_mac,
    input  wire [31:0]   cfg_src_ip,
    input  wire [31:0]   cfg_dst_ip,
    input  wire [15:0]   cfg_src_port,
    input  wire [15:0]   cfg_dst_port,

    input  wire [7:0]    s_tdata,
    input  wire          s_tvalid,
    input  wire          s_tlast,
    output wire          s_tready,

    output wire [7:0]    m_tdata,
    output wire          m_tvalid,
    output wire          m_tlast,
    input  wire          m_tready
);

    localparam ST_IDLE = 3'd0;
    localparam ST_FILL = 3'd1;
    localparam ST_OUT  = 3'd2;

    reg [2:0] state;

    reg [9:0]  wptr;
    reg [7:0]  frm_buf [0:FRAME_BUF_DEPTH-1];

    reg [15:0] csum_acc;
    reg        csum_pend;
    reg [7:0]  csum_hi;

    reg        frame_vld;
    reg        out_run;
    reg  [15:0] ocnt;

    wire [15:0] ip_csum_y  = 16'h4500 + 16'h0000 + 16'h4000 + 16'h4011 + 16'h0000
                           + cfg_src_ip[31:16] + cfg_src_ip[15:0]
                           + cfg_dst_ip[31:16] + cfg_dst_ip[15:0];
    wire [15:0] udp_csum_x = cfg_src_ip[31:16] + cfg_src_ip[15:0]
                           + cfg_dst_ip[31:16] + cfg_dst_ip[15:0]
                           + 16'h0011 + cfg_src_port + cfg_dst_port + 16'h0000;
    reg  [15:0] ip_csum_y_r;
    reg  [15:0] udp_csum_x_r;
    reg  [15:0] udp_len_r;
    reg  [15:0] total_len_r;
    reg  [15:0] frame_n_r;

    function [15:0] oc_fold;
        input [31:0] s;
        integer i;
        begin
            for (i = 0; i < 2; i = i + 1) begin
                s = (s[15:0] + s[31:16]);
                oc_fold = s[15:0];
            end
        end
    endfunction

    assign s_tready = (state == ST_IDLE) || (state == ST_FILL);

    reg [15:0] ip_hdr_csum_r;
    reg [15:0] udp_csum_total_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ip_csum_y_r <= 16'd0;
            udp_csum_x_r <= 16'd0;
        end else begin
            ip_csum_y_r <= ip_csum_y;
            udp_csum_x_r <= udp_csum_x;
        end
    end

    reg  [15:0] rf;
    reg  [9:0]  raddr;
    wire [15:0] cur = rf;
    wire        cur_esp = (cur >= 16'd42);

    reg  [7:0]  head_byte;
    always @* begin
        case (1'b1)
            cur < 16'd6:            head_byte = cfg_dst_mac[47 - 8*cur[2:0] -: 8];
            cur < 16'd12:           head_byte = cfg_src_mac[47 - 8*(cur-16'd6) -: 8];
            cur < 16'd14:           head_byte = (cur == 16'd12) ? 8'h08 : 8'h00;
            cur < 16'd34: begin
                case (cur[4:0] - 5'd14)
                    5'd0:  head_byte = 8'h45;
                    5'd1:  head_byte = 8'h00;
                    5'd2:  head_byte = total_len_r[15:8];
                    5'd3:  head_byte = total_len_r[7:0];
                    5'd4:  head_byte = 8'h00;
                    5'd5:  head_byte = 8'h00;
                    5'd6:  head_byte = 8'h40;
                    5'd7:  head_byte = 8'h00;
                    5'd8:  head_byte = 8'h40;
                    5'd9:  head_byte = ETH_IP_PROTO;
                    5'd10: head_byte = ip_hdr_csum_r[15:8];
                    5'd11: head_byte = ip_hdr_csum_r[7:0];
                    5'd12: head_byte = cfg_src_ip[31:24];
                    5'd13: head_byte = cfg_src_ip[23:16];
                    5'd14: head_byte = cfg_src_ip[15:8];
                    5'd15: head_byte = cfg_src_ip[7:0];
                    5'd16: head_byte = cfg_dst_ip[31:24];
                    5'd17: head_byte = cfg_dst_ip[23:16];
                    5'd18: head_byte = cfg_dst_ip[15:8];
                    default: head_byte = cfg_dst_ip[7:0];
                endcase
            end
            cur < 16'd42: begin
                case (cur[3:0] - 4'd2)
                    4'd0:  head_byte = cfg_src_port[15:8];
                    4'd1:  head_byte = cfg_src_port[7:0];
                    4'd2:  head_byte = cfg_dst_port[15:8];
                    4'd3:  head_byte = cfg_dst_port[7:0];
                    4'd4:  head_byte = udp_len_r[15:8];
                    4'd5:  head_byte = udp_len_r[7:0];
                    4'd6:  head_byte = udp_csum_total_r[15:8];
                    default: head_byte = udp_csum_total_r[7:0];
                endcase
            end
            default:            head_byte = 8'h00;
        endcase
    end
    wire [7:0] head_byte_w = head_byte;

    wire [7:0] m_tdata_w = cur_esp ? frm_buf[raddr] : head_byte_w;

    reg  [7:0] m_tdata_r;
    reg        run1, run2;
    reg  [15:0] rf2;
    assign m_tdata  = m_tdata_r;
    assign m_tvalid = run2 && (rf2 < frame_n_r);
    assign m_tlast  = run2 && (rf2 == frame_n_r - 16'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            wptr  <= 10'd0;
            csum_acc <= 16'd0;
            csum_pend <= 1'b0;
            csum_hi  <= 8'd0;
            frame_vld <= 1'b0;
            out_run <= 1'b0;
            ocnt  <= 16'd0;
            ip_hdr_csum_r  <= 16'd0;
            udp_csum_total_r <= 16'd0;
            udp_len_r <= 16'd0;
            total_len_r <= 16'd0;
            frame_n_r <= 16'd0;
            rf  <= 16'd0;
            raddr <= 10'd0;
            m_tdata_r <= 8'd0;
            rf2 <= 16'd0;
            run1 <= 0; run2 <= 0;
        end else begin
            rf    <= ocnt;
            raddr <= (ocnt - 16'd42);
            rf2   <= rf;
            run1  <= out_run;
            run2  <= run1;

            m_tdata_r <= m_tdata_w;

            case (state)
                ST_IDLE: begin
                    if (s_tvalid) begin
                        frm_buf[0] <= s_tdata;
                        wptr   <= 10'd1;
                        csum_acc <= 16'd0;
                        csum_pend <= 1'b1;
                        csum_hi  <= s_tdata;
                        if (s_tlast) begin
                            frame_vld <= 1'b1;
                            csum_acc <= oc_fold({16'd0, s_tdata, 8'd0});
                            udp_len_r   <= 16'd9;
                            total_len_r <= 16'd29;
                            frame_n_r   <= 16'd43;
                            state <= ST_OUT;
                        end else begin
                            state <= ST_FILL;
                        end
                    end
                end

                ST_FILL: begin
                    if (s_tvalid) begin
                        frm_buf[wptr] <= s_tdata;
                        if (!csum_pend)
                            csum_hi <= s_tdata;
                        csum_pend <= !csum_pend;
                        csum_acc <= csum_pend ? oc_fold({16'd0, csum_acc} + {csum_hi, s_tdata}) : csum_acc;
                        if (s_tlast) begin
                            if (!csum_pend)
                                csum_acc <= oc_fold({16'd0, csum_acc} + {s_tdata, 8'd0});
                            frame_vld <= 1'b1;
                            udp_len_r   <= 16'd9 + {6'd0, wptr};
                            total_len_r <= 16'd29 + {6'd0, wptr};
                            frame_n_r   <= 16'd43 + {6'd0, wptr};
                            state <= ST_OUT;
                        end else begin
                            wptr <= wptr + 10'd1;
                        end
                    end
                end

                ST_OUT: begin
                    if (frame_vld) begin
                        ip_hdr_csum_r  <= ~oc_fold({16'd0, ip_csum_y_r} + {16'd0, total_len_r});
                        udp_csum_total_r <= ~oc_fold({16'd0, csum_acc} + {16'd0, udp_csum_x_r + udp_len_r + udp_len_r});
                        out_run <= 1'b1;
                        frame_vld <= 1'b0;
                        ocnt  <= 16'd0;
                    end else if (out_run && m_tready) begin
                        if (ocnt >= frame_n_r - 16'd1 + 16'd2) begin
                            out_run <= 1'b0;
                            ocnt    <= 16'd0;
                            wptr    <= 10'd0;
                            csum_acc <= 16'd0;
                            csum_pend <= 1'b0;
                            state   <= ST_IDLE;
                        end else begin
                            ocnt <= ocnt + 16'd1;
                        end
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
