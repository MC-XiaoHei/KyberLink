module ip_udp_eth_rx (
    input wire clk,
    input wire rst_n,

    input  wire [7:0] s_tdata,
    input  wire       s_tvalid,
    input  wire       s_tlast,
    output wire       s_tready,

    input wire [47:0] cfg_src_mac,
    input wire [15:0] cfg_dport,

    output reg  [7:0] m_data_tdata,
    output reg        m_data_tvalid,
    output reg        m_data_tlast,
    input  wire       m_data_tready,

    output reg         hsk_wr,
    output reg  [31:0] hsk_data,
    output reg         hsk_last,
    output reg  [15:0] hsk_len,
    input  wire        hsk_ready,
    input  wire [ 9:0] hsk_room,

    output reg err_rxdrop,
    output wire [31:0] dbg_rx,
    output wire [31:0] dbg_rx2,
    output wire [31:0] dbg_head
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
  reg hsk_seen;
  reg is_data;
  reg [15:0] udp_len_r;
  reg pay_done;
  reg [1:0] hsk_tail;
  reg hsk_tail_v;
  reg [15:0] cnt_data_end;
  reg [15:0] cnt_drop_end;
  reg [15:0] cnt_hsk_end;
  reg [15:0] cnt_rxdrop;
  reg [15:0] cnt_bytes;
  reg [4:0] drop_reason;
  reg [31:0] head;
  assign dbg_head = head;
  wire [7:0] d = s_tdata;

  assign dbg_rx = {cnt_drop_end, cnt_data_end};
  assign dbg_rx2 = {drop_reason, cnt_bytes};

  wire [15:0] pay_w = udp_len_r - 16'd8;
  wire in_pay = (cnt >= 14'd42) && (cnt < 14'd42 + {2'd0, pay_w});
  wire pay_end = (cnt == 14'd41 + {2'd0, pay_w});
  wire [15:0] pay_words = {2'd0, pay_w[15:2]} + {14'd0, |pay_w[1:0]};
  wire hsk_fit = (pay_w >= 16'd8) && ({6'd0, hsk_room} >= pay_words);

  wire dmac_ok = (cnt < 14'd6) ? (d == cfg_src_mac[47-8*cnt[2:0]-:8]) : 1'b1;
  wire etype_ok = (cnt == 14'd12) ? (d == 8'h08) : (cnt == 14'd13) ? (d == 8'h00) : 1'b1;
  wire ver_ok = (cnt == 14'd14) ? (d == 8'h45) : 1'b1;
  wire proto_ok = (cnt == 14'd23) ? (d == 8'h11) : 1'b1;
  wire dport_ok = (cnt == 14'd36) ? ((d == cfg_dport[15:8]) || (d == 8'h11)) :
                  (cnt == 14'd37) ? ((d == cfg_dport[7:0]) || (d == 8'h94) || (d == 8'h95)) : 1'b1;

  wire bad_here = !dmac_ok || !etype_ok || !ver_ok || !proto_ok || !dport_ok;

  assign s_tready = (state == ST_IDLE) || (state == ST_RX);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE;
      cnt <= 14'd0;
      drop <= 1'b0;
      hsk_bc <= 2'd0;
      hsk_acc <= 32'd0;
      hsk_len_r <= 16'd0;
      is_hsk <= 1'b0;
      hsk_seen <= 1'b0;
      is_data <= 1'b0;
      udp_len_r <= 16'd0;
      pay_done <= 1'b0;
      hsk_tail <= 2'd0;
      hsk_tail_v <= 1'b0;
      cnt_data_end <= 16'd0;
      cnt_drop_end <= 16'd0;
      cnt_hsk_end <= 16'd0;
      cnt_rxdrop <= 16'd0;
      cnt_bytes <= 16'd0;
      drop_reason <= 5'd0;
      head <= 32'd0;
      m_data_tdata <= 8'd0;
      m_data_tvalid <= 1'b0;
      m_data_tlast <= 1'b0;
      hsk_wr <= 1'b0;
      hsk_data <= 32'd0;
      hsk_last <= 1'b0;
      hsk_len <= 16'd0;
      err_rxdrop <= 1'b0;
    end else begin
      m_data_tvalid <= 1'b0;
      m_data_tlast <= 1'b0;
      hsk_wr <= 1'b0;
      hsk_last <= 1'b0;
      err_rxdrop <= 1'b0;
      if (m_data_tvalid && m_data_tready) begin
        m_data_tvalid <= 1'b0;
        m_data_tlast  <= 1'b0;
      end
      case (state)
        ST_IDLE: begin
          if (s_tvalid) begin
            head[31:24] <= d;
            cnt <= 14'd1;
            drop <= 1'b0;
            hsk_bc <= 2'd0;
            hsk_acc <= 32'd0;
            hsk_len_r <= 16'd0;
            is_hsk <= 1'b0;
            hsk_seen <= 1'b0;
            is_data <= 1'b0;
            udp_len_r <= 16'd0;
            pay_done <= 1'b0;
            hsk_tail_v <= 1'b0;
            state <= ST_RX;
          end
        end
        ST_RX: begin
          if (s_tvalid && s_tready) begin
            if (bad_here) begin
              drop <= 1'b1;
              if (!dmac_ok) drop_reason[0] <= 1'b1;
              if (!etype_ok) drop_reason[1] <= 1'b1;
              if (!ver_ok) drop_reason[2] <= 1'b1;
              if (!proto_ok) drop_reason[3] <= 1'b1;
              if (!dport_ok) drop_reason[4] <= 1'b1;
            end
            if (cnt == 14'd37) begin
              if (d == 8'h95) hsk_seen <= 1'b1;
              else if ((d == 8'h94) || (d == cfg_dport[7:0])) is_data <= 1'b1;
            end
            if (cnt == 14'd40 && hsk_seen && hsk_ready && hsk_fit) is_hsk <= 1'b1;
            if (cnt == 14'd1) head[23:16] <= d;
            if (cnt == 14'd2) head[15:8] <= d;
            if (cnt == 14'd3) head[7:0] <= d;
            if (cnt == 14'd38) udp_len_r[15:8] <= d;
            if (cnt == 14'd39) udp_len_r[7:0] <= d;
            if (cnt >= 14'd42 && in_pay && !drop && !pay_done) begin
              if (is_data) begin
                if (!m_data_tvalid || m_data_tready) begin
                  m_data_tvalid <= 1'b1;
                  m_data_tdata  <= d;
                  m_data_tlast  <= pay_end || s_tlast;
                end else begin
                  err_rxdrop <= 1'b1;
                end
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
            if (pay_end && (is_data || is_hsk) && !drop) begin
              pay_done <= 1'b1;
              if (is_hsk) begin
                hsk_tail <= hsk_bc + 2'd1;
                hsk_tail_v <= 1'b1;
                hsk_len <= hsk_len_r + 16'd1;
              end
            end
            if (s_tlast) begin
              if (drop && is_data) err_rxdrop <= 1'b1;
              if (drop && is_hsk) err_rxdrop <= 1'b1;
              if (drop) cnt_drop_end <= cnt_drop_end + 16'd1;
              if (pay_done && is_data && !drop) cnt_data_end <= cnt_data_end + 16'd1;
              if (is_hsk && !drop && !pay_done) begin
                hsk_tail <= hsk_bc + 2'd1;
                hsk_tail_v <= 1'b1;
                hsk_len <= hsk_len_r + 16'd1;
              end
              state <= ST_IDLE;
              cnt   <= 14'd0;
            end else begin
              cnt <= cnt + 14'd1;
            end
          end
        end
        default: state <= ST_IDLE;
      endcase
      if (err_rxdrop) cnt_rxdrop <= cnt_rxdrop + 16'd1;
      if (s_tvalid && s_tready) cnt_bytes <= cnt_bytes + 16'd1;
      if (hsk_last) cnt_hsk_end <= cnt_hsk_end + 16'd1;
      if (hsk_tail_v) begin
        hsk_tail_v <= 1'b0;
        hsk_last   <= 1'b1;
        if (hsk_tail != 2'd0) begin
          hsk_wr <= 1'b1;
          case (hsk_tail)
            2'd1: hsk_data <= {hsk_acc[31:24], 24'd0};
            2'd2: hsk_data <= {hsk_acc[31:16], 16'd0};
            default: hsk_data <= {hsk_acc[31:8], 8'd0};
          endcase
        end
      end
    end
  end

endmodule
