module ip_udp_eth_rx (
    input wire clk,
    input wire rst_n,

    input  wire [7:0] s_tdata,
    input  wire       s_tvalid,
    input  wire       s_tlast,
    output wire       s_tready,

    input wire [47:0] cfg_src_mac,

    output reg  [7:0] m_data_tdata,
    output reg        m_data_tvalid,
    output reg        m_data_tlast,
    input  wire       m_data_tready,

    output reg         hsk_wr,
    output reg  [31:0] hsk_data,
    output reg         hsk_last,
    output reg  [15:0] hsk_len,
    input  wire        hsk_ready
);

  localparam ST_IDLE = 1'b0;
  localparam ST_RX   = 1'b1;

  reg state;
  reg [13:0] cnt;
  reg drop;
  reg [1:0] hsk_bc;
  reg [31:0] hsk_acc;
  reg [15:0] hsk_len_r;
  reg is_hsk;
  reg is_data;
  wire [7:0] d = s_tdata;

  wire dmac_ok = (cnt < 14'd6) ? (d == cfg_src_mac[47-8*cnt[2:0]-:8]) : 1'b1;
  wire etype_ok = (cnt == 14'd12) ? (d == 8'h08) : (cnt == 14'd13) ? (d == 8'h00) : 1'b1;
  wire ver_ok = (cnt == 14'd14) ? (d == 8'h45) : 1'b1;
  wire proto_ok = (cnt == 14'd23) ? (d == 8'h11) : 1'b1;
  wire dport_ok = (cnt == 14'd36) ? (d == 8'h11) :
                    (cnt == 14'd37) ? ((d == 8'h94) || (d == 8'h95)) : 1'b1;

  wire bad_here = !dmac_ok || !etype_ok || !ver_ok || !proto_ok || !dport_ok;

  assign s_tready = (state == ST_IDLE) ||
                      (state == ST_RX && !drop &&
                       (!is_data || m_data_tready) &&
                       (!is_hsk || hsk_ready));

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE;
      cnt <= 14'd0;
      drop <= 1'b0;
      hsk_bc <= 2'd0;
      hsk_acc <= 32'd0;
      hsk_len_r <= 16'd0;
      is_hsk <= 1'b0;
      is_data <= 1'b0;
      m_data_tdata <= 8'd0;
      m_data_tvalid <= 1'b0;
      m_data_tlast <= 1'b0;
      hsk_wr <= 1'b0;
      hsk_data <= 32'd0;
      hsk_last <= 1'b0;
      hsk_len <= 16'd0;
    end else begin
      m_data_tvalid <= 1'b0;
      m_data_tlast <= 1'b0;
      hsk_wr <= 1'b0;
      hsk_last <= 1'b0;
      case (state)
        ST_IDLE: begin
          if (s_tvalid) begin
            cnt <= 14'd1;
            drop <= 1'b0;
            hsk_bc <= 2'd0;
            hsk_acc <= 32'd0;
            hsk_len_r <= 16'd0;
            is_hsk <= 1'b0;
            is_data <= 1'b0;
            state <= ST_RX;
          end
        end
        ST_RX: begin
          if (s_tvalid && s_tready) begin
            if (bad_here) drop <= 1'b1;
            if (cnt == 14'd37) begin
              if (d == 8'h94) is_data <= 1'b1;
              else if (d == 8'h95) is_hsk <= 1'b1;
            end
            if (cnt >= 14'd42 && !drop) begin
              if (is_data) begin
                m_data_tvalid <= 1'b1;
                m_data_tdata  <= d;
                m_data_tlast  <= s_tlast;
              end else if (is_hsk) begin
                hsk_len_r <= hsk_len_r + 16'd1;
                case (hsk_bc)
                  2'd0: hsk_acc[31:24] <= d;
                  2'd1: hsk_acc[23:16] <= d;
                  2'd2: hsk_acc[15:8] <= d;
                  default: begin
                    hsk_data <= {hsk_acc[31:8], d};
                    hsk_wr   <= 1'b1;
                  end
                endcase
                hsk_bc <= hsk_bc + 2'd1;
              end
            end
            if (s_tlast) begin
              if (is_hsk) begin
                hsk_wr <= 1'b1;
                case (hsk_bc)
                  2'd0: hsk_data <= {d, 24'd0};
                  2'd1: hsk_data <= {hsk_acc[31:24], d, 16'd0};
                  2'd2: hsk_data <= {hsk_acc[31:16], d, 8'd0};
                  default: hsk_data <= {hsk_acc[31:8], d};
                endcase
              end
              if (is_hsk) hsk_last <= 1'b1;
              hsk_len <= hsk_len_r + 16'd1;
              state <= ST_IDLE;
              cnt <= 14'd0;
            end else begin
              cnt <= cnt + 14'd1;
            end
          end
        end
        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
