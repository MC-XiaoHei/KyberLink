module hs_tx (
    input  wire       clk,
    input  wire       rst_n,

    output wire       resp_ren,
    output wire [12:0] resp_raddr,
    input  wire [7:0]  resp_rdata,
    input  wire        resp_ready,
    input  wire [12:0] resp_len,
    output reg         resp_clear,
    output reg         resp_frame_done,

    input  wire [47:0] hdr_src_mac,
    input  wire [47:0] hdr_dst_mac,
    input  wire [31:0] hdr_src_ip,
    input  wire [31:0] hdr_dst_ip,
    input  wire [15:0] hdr_src_port,
    input  wire [15:0] hdr_dst_port,

    output wire [7:0]  m_tdata,
    output wire        m_tvalid,
    output wire        m_tlast,
    input  wire        m_tready
);

    localparam S_IDLE = 2'd0;
    localparam S_HDR  = 2'd1;
    localparam S_PAY  = 2'd2;

    reg [1:0]  state;
    reg [15:0] cnt;
    reg [12:0] raddr;
    reg [7:0]  pay_byte;
    reg        pay_v;
    reg        pre1;
    reg        served;

    assign resp_ren = (state == S_PAY);
    assign resp_raddr = raddr;

function [15:0] fold16(input [31:0] s);
        begin
            fold16 = s[15:0] + s[31:16];
        end
    endfunction

    wire [15:0] ip_sum = 16'h4500 + (16'd42 + {3'd0, resp_len}) + 16'h4000 + 16'h4011
                       + hdr_src_ip[31:16] + hdr_src_ip[15:0]
                       + hdr_dst_ip[31:16] + hdr_dst_ip[15:0];
    reg [15:0] ip_sum_q;
    always @(posedge clk) ip_sum_q <= ip_sum;
    wire [15:0] ip_csum_c = ~(fold16({16'd0, ip_sum_q}));

    wire [15:0] udp_len_w = 16'd8 + {3'd0, resp_len};

    function [7:0] hdr_byte(input [15:0] o);
        reg [15:0] total;
        reg [4:0]  ip_off;
        reg [3:0]  udp_off;
        begin
            total = 16'd42 + resp_len;
            if (o < 16'd6)
                hdr_byte = hdr_dst_mac[47 - 8*o[2:0] -: 8];
            else if (o < 16'd12)
                hdr_byte = hdr_src_mac[47 - 8*(o - 16'd6) -: 8];
            else if (o < 16'd14)
                hdr_byte = (o == 16'd12) ? 8'h08 : 8'h00;
            else if (o < 16'd34) begin
                ip_off = o - 16'd14;
                case (ip_off)
                    5'd0: hdr_byte = 8'h45;
                    5'd1: hdr_byte = 8'h00;
                    5'd2: hdr_byte = total[15:8];
                    5'd3: hdr_byte = total[7:0];
                    5'd4: hdr_byte = 8'h00;
                    5'd5: hdr_byte = 8'h00;
                    5'd6: hdr_byte = 8'h40;
                    5'd7: hdr_byte = 8'h00;
                    5'd8: hdr_byte = 8'h40;
                    5'd9: hdr_byte = 8'h11;
                    5'd10: hdr_byte = ip_csum_c[15:8];
                    5'd11: hdr_byte = ip_csum_c[7:0];
                    5'd12: hdr_byte = hdr_src_ip[31:24];
                    5'd13: hdr_byte = hdr_src_ip[23:16];
                    5'd14: hdr_byte = hdr_src_ip[15:8];
                    5'd15: hdr_byte = hdr_src_ip[7:0];
                    5'd16: hdr_byte = hdr_dst_ip[31:24];
                    5'd17: hdr_byte = hdr_dst_ip[23:16];
                    5'd18: hdr_byte = hdr_dst_ip[15:8];
                    default: hdr_byte = hdr_dst_ip[7:0];
                endcase
            end else if (o < 16'd42) begin
                udp_off = o - 16'd34;
                case (udp_off)
                    4'd0: hdr_byte = hdr_src_port[15:8];
                    4'd1: hdr_byte = hdr_src_port[7:0];
                    4'd2: hdr_byte = hdr_dst_port[15:8];
                    4'd3: hdr_byte = hdr_dst_port[7:0];
                    4'd4: hdr_byte = udp_len_w[15:8];
                    4'd5: hdr_byte = udp_len_w[7:0];
                    4'd6: hdr_byte = 8'h00;
                    default: hdr_byte = 8'h00;
                endcase
            end else
                hdr_byte = 8'h00;
        end
    endfunction

    reg [7:0] m_tdata_r;
    reg       m_tvalid_r;
    reg       m_tlast_r;
    assign m_tdata = m_tdata_r;
    assign m_tvalid = m_tvalid_r;
    assign m_tlast = m_tlast_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            cnt <= 16'd0;
            raddr <= 13'd0;
            pay_byte <= 8'd0;
            pay_v <= 1'b0;
            pre1 <= 1'b0;
            served <= 1'b0;
            resp_clear <= 1'b0;
            resp_frame_done <= 1'b0;
            m_tvalid_r <= 1'b0;
            m_tlast_r <= 1'b0;
        end else begin
            resp_clear <= 1'b0;
            resp_frame_done <= 1'b0;
            if (!resp_ready)
                served <= 1'b0;
            case (state)
                S_IDLE: begin
                    m_tvalid_r <= 1'b0;
                    if (resp_ready && (resp_len > 0) && !served) begin
                        cnt <= 16'd0;
                        raddr <= 13'd0;
                        pay_v <= 1'b0;
                        pre1 <= 1'b0;
                        served <= 1'b1;
                        state <= S_HDR;
                    end
                end
                S_HDR: begin
                    m_tvalid_r <= 1'b1;
                    m_tdata_r <= hdr_byte(cnt);
                    m_tlast_r <= 1'b0;
                    if (m_tready) begin
                        if (cnt == 16'd41) begin
                            cnt <= 16'd0;
                            state <= S_PAY;
                        end else begin
                            cnt <= cnt + 16'd1;
                        end
                    end
                end
                S_PAY: begin
                    m_tvalid_r <= pay_v;
                    m_tlast_r <= pay_v && (cnt == resp_len - 16'd1);
                    if (pay_v && m_tready) begin
                        m_tdata_r <= resp_rdata;
                        raddr <= raddr + 13'd1;
                        if (cnt == resp_len - 16'd1) begin
                            state <= S_IDLE;
                            pay_v <= 1'b0;
                            pre1 <= 1'b0;
                            resp_clear <= 1'b1;
                            resp_frame_done <= 1'b1;
                        end else begin
                            cnt <= cnt + 16'd1;
                            pay_v <= 1'b0;
                        end
                    end else if (!pay_v) begin
                        if (pre1) begin
                            pay_v <= 1'b1;
                            pre1 <= 1'b0;
                        end else begin
                            pre1 <= 1'b1;
                        end
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule