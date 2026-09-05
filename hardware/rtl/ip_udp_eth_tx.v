module ip_udp_eth_tx (
    input wire clk,
    input wire rst_n,

    input  wire [7:0] s_esp_tdata,
    input  wire       s_esp_tvalid,
    input  wire       s_esp_tlast,
    output wire       s_esp_tready,

    input  wire [31:0] s_hsk_tdata,
    input  wire        s_hsk_tvalid,
    output wire        s_hsk_tready,
    input  wire [15:0] hsk_len,

    input wire [31:0] cfg_src_ip,
    input wire [31:0] cfg_dst_ip,
    input wire [47:0] cfg_src_mac,
    input wire [47:0] cfg_dst_mac,

    input  wire [7:0] s_ctrl_tdata,
    input  wire       s_ctrl_tvalid,
    input  wire       s_ctrl_tlast,
    output wire       s_ctrl_tready,

    output reg  [7:0] m_tdata,
    output reg        m_tvalid,
    output reg        m_tlast,
    input  wire       m_tready
);

  localparam ST_IDLE = 3'd0;
  localparam ST_ESP  = 3'd1;
  localparam ST_HDR  = 3'd2;
  localparam ST_PAY  = 3'd3;
  localparam ST_PRE1 = 3'd4;
  localparam ST_PRE2 = 3'd5;
  localparam ST_CTRL = 3'd6;

  reg [ 2:0] state;
  reg [ 5:0] hcnt;
  reg [ 1:0] hb;
  reg [15:0] pay_len;
  reg [15:0] len_sum_r;
  reg [15:0] ip_sum_r;
  reg [15:0] total_len_r;
  reg [15:0] udp_len_r;
  reg [15:0] ip_csum_r;
  reg [15:0] pb;

  function [15:0] fold16(input [31:0] s);
    begin
      fold16 = s[15:0] + s[31:16];
    end
  endfunction

  wire [15:0] total_len_w = 16'd28 + pay_len;
  wire [15:0] udp_len_w = 16'd8 + pay_len;
  wire [31:0] ip_sum = 16'h4500 + total_len_w + 16'h4000 + 16'h4011
                       + cfg_src_ip[31:16] + cfg_src_ip[15:0]
                       + cfg_dst_ip[31:16] + cfg_dst_ip[15:0];
  wire [15:0] ip_csum = ~fold16(ip_sum);

  function [7:0] hdr_byte(input [5:0] o);
    begin
      case (o)
        6'd0: hdr_byte = cfg_dst_mac[47:40];
        6'd1: hdr_byte = cfg_dst_mac[39:32];
        6'd2: hdr_byte = cfg_dst_mac[31:24];
        6'd3: hdr_byte = cfg_dst_mac[23:16];
        6'd4: hdr_byte = cfg_dst_mac[15:8];
        6'd5: hdr_byte = cfg_dst_mac[7:0];
        6'd6: hdr_byte = cfg_src_mac[47:40];
        6'd7: hdr_byte = cfg_src_mac[39:32];
        6'd8: hdr_byte = cfg_src_mac[31:24];
        6'd9: hdr_byte = cfg_src_mac[23:16];
        6'd10: hdr_byte = cfg_src_mac[15:8];
        6'd11: hdr_byte = cfg_src_mac[7:0];
        6'd12: hdr_byte = 8'h08;
        6'd13: hdr_byte = 8'h00;
        6'd14: hdr_byte = 8'h45;
        6'd15: hdr_byte = 8'h00;
        6'd16: hdr_byte = total_len_w[15:8];
        6'd17: hdr_byte = total_len_w[7:0];
        6'd18: hdr_byte = 8'h00;
        6'd19: hdr_byte = 8'h00;
        6'd20: hdr_byte = 8'h40;
        6'd21: hdr_byte = 8'h00;
        6'd22: hdr_byte = 8'h40;
        6'd23: hdr_byte = 8'h11;
        6'd24: hdr_byte = ip_csum_r[15:8];
        6'd25: hdr_byte = ip_csum_r[7:0];
        6'd26: hdr_byte = cfg_src_ip[31:24];
        6'd27: hdr_byte = cfg_src_ip[23:16];
        6'd28: hdr_byte = cfg_src_ip[15:8];
        6'd29: hdr_byte = cfg_src_ip[7:0];
        6'd30: hdr_byte = cfg_dst_ip[31:24];
        6'd31: hdr_byte = cfg_dst_ip[23:16];
        6'd32: hdr_byte = cfg_dst_ip[15:8];
        6'd33: hdr_byte = cfg_dst_ip[7:0];
        6'd34: hdr_byte = 8'h11;
        6'd35: hdr_byte = 8'h95;
        6'd36: hdr_byte = 8'h11;
        6'd37: hdr_byte = 8'h95;
        6'd38: hdr_byte = udp_len_w[15:8];
        6'd39: hdr_byte = udp_len_w[7:0];
        6'd40: hdr_byte = 8'h00;
        default: hdr_byte = 8'h00;
      endcase
    end
  endfunction
  wire [7:0] hdr_byte_w = hdr_byte(hcnt);

  assign s_esp_tready = (state == ST_IDLE && s_esp_tvalid) || (state == ST_ESP && m_tready);
  assign s_ctrl_tready = (state == ST_IDLE && s_ctrl_tvalid) || (state == ST_CTRL && m_tready);
  assign s_hsk_tready = (state == ST_PAY) && m_tready &&
                        (((hb == 2'd3) && (pb + 16'd1) < pay_len) ||
                         ((pb + 16'd1) == pay_len));

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE;
      hcnt <= 6'd0;
      hb <= 2'd0;
      pay_len <= 16'd0;
      len_sum_r <= 16'd0;
      ip_sum_r <= 16'd0;
      total_len_r <= 16'd0;
      udp_len_r <= 16'd0;
      ip_csum_r <= 16'd0;
      pb <= 16'd0;
      m_tdata <= 8'd0;
      m_tvalid <= 1'b0;
      m_tlast <= 1'b0;
    end else begin
      m_tvalid <= 1'b0;
      m_tlast  <= 1'b0;
      case (state)
        ST_IDLE: begin
          if (s_ctrl_tvalid) begin
            state <= (s_ctrl_tlast) ? ST_IDLE : ST_CTRL;
            m_tvalid <= 1'b1;
            m_tdata <= s_ctrl_tdata;
            m_tlast <= s_ctrl_tlast;
          end else if (s_esp_tvalid) begin
            state <= (s_esp_tlast) ? ST_IDLE : ST_ESP;
            m_tvalid <= 1'b1;
            m_tdata <= s_esp_tdata;
            m_tlast <= s_esp_tlast;
          end else if (s_hsk_tvalid && !m_tlast) begin
            pay_len <= hsk_len;
            len_sum_r <= 16'd28 + hsk_len;
            state <= ST_PRE1;
          end
        end
        ST_PRE1: begin
          ip_sum_r <= 16'h4500 + len_sum_r + 16'h4000 + 16'h4011
                              + cfg_src_ip[31:16] + cfg_src_ip[15:0]
                              + cfg_dst_ip[31:16] + cfg_dst_ip[15:0];
          state <= ST_PRE2;
        end
        ST_PRE2: begin
          ip_csum_r <= ~fold16(ip_sum_r);
          total_len_r <= 16'd28 + pay_len;
          udp_len_r <= 16'd8 + pay_len;
          hcnt <= 6'd1;
          pb <= 16'd0;
          hb <= 2'd0;
          m_tvalid <= 1'b1;
          m_tdata <= cfg_dst_mac[47:40];
          state <= ST_HDR;
        end
        ST_ESP: begin
          if (m_tready) begin
            m_tvalid <= s_esp_tvalid;
            m_tdata  <= s_esp_tdata;
            m_tlast  <= s_esp_tlast;
            if (s_esp_tlast) state <= ST_IDLE;
          end
        end
        ST_CTRL: begin
          if (m_tready) begin
            m_tvalid <= s_ctrl_tvalid;
            m_tdata  <= s_ctrl_tdata;
            m_tlast  <= s_ctrl_tlast;
            if (s_ctrl_tlast) state <= ST_IDLE;
          end
        end
        ST_HDR: begin
          if (m_tready) begin
            m_tvalid <= 1'b1;
            if (hcnt == 6'd42) begin
              m_tdata <= s_hsk_tdata[31:24];
              hb <= 2'd1;
              pb <= 16'd1;
              state <= ST_PAY;
            end else begin
              m_tdata <= hdr_byte_w;
              hcnt <= hcnt + 6'd1;
            end
          end
        end
        ST_PAY: begin
          if (m_tready) begin
            m_tvalid <= (hb != 2'd0) || s_hsk_tvalid;
            m_tdata  <= s_hsk_tdata[31-8*hb-:8];
            if (hb != 2'd0 || s_hsk_tvalid) begin
              if (pb == (pay_len - 16'd1)) begin
                m_tlast <= 1'b1;
                state   <= ST_IDLE;
              end else begin
                pb <= pb + 16'd1;
                if (hb == 2'd3) hb <= 2'd0;
                else hb <= hb + 2'd1;
              end
            end
          end
        end
        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
