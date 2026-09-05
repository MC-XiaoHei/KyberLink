module ctrl_resp (
    input wire clk,
    input wire rst_n,

    input  wire [7:0] s_tdata,
    input  wire       s_tvalid,
    input  wire       s_tlast,

    input  wire [47:0] cfg_src_mac,
    input  wire [31:0] cfg_src_ip,
    input  wire        key_load,

    output wire [7:0] m_tdata,
    output wire       m_tvalid,
    output wire       m_tlast,
    input  wire       m_tready
);

  localparam ST_IDLE = 2'd0;
  localparam ST_RX   = 2'd1;
  localparam ST_JUD  = 2'd2;
  localparam ST_TX   = 2'd3;

  localparam MODE_ARP  = 2'd0;
  localparam MODE_ICMP = 2'd1;
  localparam MODE_GARP = 2'd2;

  reg [1:0] state;
  reg [1:0] mode;
  reg [8:0] wcnt;
  reg [8:0] rcnt;
  reg [8:0] tx_len;
  reg [15:0] total_len_r;
  reg [15:0] ip_csum_r;
  reg [15:0] ic_csum_r;
  reg [47:0] ra_mac;
  reg [31:0] ra_ip;
  reg [47:0] eth_da;
  reg [7:0] rbuf [0:255];
  reg garp_pend;

  wire [16:0] ic_fix_w = {1'b0, ~rbuf[36], ~rbuf[37]} + {1'b0, 16'hF7FF};

  assign m_tvalid = (state == ST_TX);
  assign m_tlast = (state == ST_TX) && (rcnt + 9'd1 == tx_len);
  assign m_tdata = obyte(rcnt);

  function [15:0] fold16(input [31:0] s);
    begin
      fold16 = s[15:0] + s[31:16];
    end
  endfunction

  function [7:0] obyte(input [8:0] i);
    begin
      if (mode != MODE_ICMP) begin
        case (i)
          9'd0: obyte = eth_da[47:40];
          9'd1: obyte = eth_da[39:32];
          9'd2: obyte = eth_da[31:24];
          9'd3: obyte = eth_da[23:16];
          9'd4: obyte = eth_da[15:8];
          9'd5: obyte = eth_da[7:0];
          9'd6: obyte = cfg_src_mac[47:40];
          9'd7: obyte = cfg_src_mac[39:32];
          9'd8: obyte = cfg_src_mac[31:24];
          9'd9: obyte = cfg_src_mac[23:16];
          9'd10: obyte = cfg_src_mac[15:8];
          9'd11: obyte = cfg_src_mac[7:0];
          9'd12: obyte = 8'h08;
          9'd13: obyte = 8'h06;
          9'd14: obyte = 8'h00;
          9'd15: obyte = 8'h01;
          9'd16: obyte = 8'h08;
          9'd17: obyte = 8'h00;
          9'd18: obyte = 8'h06;
          9'd19: obyte = 8'h04;
          9'd20: obyte = 8'h00;
          9'd21: obyte = (mode == MODE_ARP) ? 8'h02 : 8'h01;
          9'd22: obyte = cfg_src_mac[47:40];
          9'd23: obyte = cfg_src_mac[39:32];
          9'd24: obyte = cfg_src_mac[31:24];
          9'd25: obyte = cfg_src_mac[23:16];
          9'd26: obyte = cfg_src_mac[15:8];
          9'd27: obyte = cfg_src_mac[7:0];
          9'd28: obyte = cfg_src_ip[31:24];
          9'd29: obyte = cfg_src_ip[23:16];
          9'd30: obyte = cfg_src_ip[15:8];
          9'd31: obyte = cfg_src_ip[7:0];
          9'd32: obyte = (mode == MODE_ARP) ? ra_mac[47:40] : 8'h00;
          9'd33: obyte = (mode == MODE_ARP) ? ra_mac[39:32] : 8'h00;
          9'd34: obyte = (mode == MODE_ARP) ? ra_mac[31:24] : 8'h00;
          9'd35: obyte = (mode == MODE_ARP) ? ra_mac[23:16] : 8'h00;
          9'd36: obyte = (mode == MODE_ARP) ? ra_mac[15:8] : 8'h00;
          9'd37: obyte = (mode == MODE_ARP) ? ra_mac[7:0] : 8'h00;
          9'd38: obyte = (mode == MODE_ARP) ? ra_ip[31:24] : cfg_src_ip[31:24];
          9'd39: obyte = (mode == MODE_ARP) ? ra_ip[23:16] : cfg_src_ip[23:16];
          9'd40: obyte = (mode == MODE_ARP) ? ra_ip[15:8] : cfg_src_ip[15:8];
          default: obyte = (mode == MODE_ARP) ? ra_ip[7:0] : cfg_src_ip[7:0];
        endcase
      end else begin
        case (i)
          9'd0: obyte = rbuf[6];
          9'd1: obyte = rbuf[7];
          9'd2: obyte = rbuf[8];
          9'd3: obyte = rbuf[9];
          9'd4: obyte = rbuf[10];
          9'd5: obyte = rbuf[11];
          9'd6: obyte = cfg_src_mac[47:40];
          9'd7: obyte = cfg_src_mac[39:32];
          9'd8: obyte = cfg_src_mac[31:24];
          9'd9: obyte = cfg_src_mac[23:16];
          9'd10: obyte = cfg_src_mac[15:8];
          9'd11: obyte = cfg_src_mac[7:0];
          9'd12: obyte = 8'h08;
          9'd13: obyte = 8'h00;
          9'd14: obyte = 8'h45;
          9'd15: obyte = 8'h00;
          9'd16: obyte = total_len_r[15:8];
          9'd17: obyte = total_len_r[7:0];
          9'd18: obyte = rbuf[18];
          9'd19: obyte = rbuf[19];
          9'd20: obyte = rbuf[20];
          9'd21: obyte = rbuf[21];
          9'd22: obyte = 8'h40;
          9'd23: obyte = 8'h01;
          9'd24: obyte = ip_csum_r[15:8];
          9'd25: obyte = ip_csum_r[7:0];
          9'd26: obyte = rbuf[30];
          9'd27: obyte = rbuf[31];
          9'd28: obyte = rbuf[32];
          9'd29: obyte = rbuf[33];
          9'd30: obyte = rbuf[26];
          9'd31: obyte = rbuf[27];
          9'd32: obyte = rbuf[28];
          9'd33: obyte = rbuf[29];
          9'd34: obyte = 8'h00;
          9'd35: obyte = rbuf[35];
          9'd36: obyte = ic_csum_r[15:8];
          9'd37: obyte = ic_csum_r[7:0];
          default: obyte = rbuf[i[7:0]];
        endcase
      end
    end
  endfunction

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE;
      mode <= MODE_ARP;
      wcnt <= 9'd0;
      rcnt <= 9'd0;
      tx_len <= 9'd0;
      total_len_r <= 16'd0;
      ip_csum_r <= 16'd0;
      ic_csum_r <= 16'd0;
      ra_mac <= 48'd0;
      ra_ip <= 32'd0;
      eth_da <= 48'd0;
      garp_pend <= 1'b0;
    end else begin
      if (key_load) garp_pend <= 1'b1;
      case (state)
        ST_IDLE: begin
          wcnt <= 9'd0;
          if (s_tvalid) begin
            rbuf[0] <= s_tdata;
            wcnt <= 9'd1;
            state <= ST_RX;
          end else if (garp_pend) begin
            garp_pend <= 1'b0;
            mode <= MODE_GARP;
            eth_da <= 48'hFF_FF_FF_FF_FF_FF;
            tx_len <= 9'd42;
            rcnt <= 9'd0;
            state <= ST_TX;
          end
        end
        ST_RX: begin
          if (s_tvalid) begin
            if (wcnt < 9'd256) rbuf[wcnt[7:0]] <= s_tdata;
            wcnt <= wcnt + 9'd1;
            if (s_tlast) state <= ST_JUD;
          end
        end
        ST_JUD: begin
          if (!wcnt[8] && wcnt >= 9'd42) begin
            if (rbuf[12] == 8'h08 && rbuf[13] == 8'h06 && rbuf[20] == 8'h00 && rbuf[21] == 8'h01
                && {rbuf[38], rbuf[39], rbuf[40], rbuf[41]} == cfg_src_ip) begin
              mode <= MODE_ARP;
              ra_mac <= {rbuf[22], rbuf[23], rbuf[24], rbuf[25], rbuf[26], rbuf[27]};
              ra_ip <= {rbuf[28], rbuf[29], rbuf[30], rbuf[31]};
              eth_da <= {rbuf[22], rbuf[23], rbuf[24], rbuf[25], rbuf[26], rbuf[27]};
              tx_len <= 9'd42;
              rcnt <= 9'd0;
              state <= ST_TX;
            end else if (rbuf[12] == 8'h08 && rbuf[13] == 8'h00 && rbuf[14] == 8'h45
                         && rbuf[23] == 8'h01 && {rbuf[30], rbuf[31], rbuf[32], rbuf[33]} == cfg_src_ip
                         && rbuf[34] == 8'h08) begin
              mode <= MODE_ICMP;
              total_len_r <= {7'd0, wcnt} - 16'd14;
              ip_csum_r <= ~fold16(32'h4500 + {24'd0, wcnt} - 32'd14 + 32'h4000 + 32'h4001
                                   + {8'd0, rbuf[30], rbuf[31]} + {8'd0, rbuf[32], rbuf[33]}
                                   + {8'd0, rbuf[26], rbuf[27]} + {8'd0, rbuf[28], rbuf[29]});
              ic_csum_r <= ~(ic_fix_w[15:0] + {16'd0, ic_fix_w[16]});
              tx_len <= wcnt;
              rcnt <= 9'd0;
              state <= ST_TX;
            end else begin
              state <= ST_IDLE;
            end
          end else begin
            state <= ST_IDLE;
          end
        end
        ST_TX: begin
          if (m_tready) begin
            rcnt <= rcnt + 9'd1;
            if (rcnt + 9'd1 == tx_len) state <= ST_IDLE;
          end
        end
        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
