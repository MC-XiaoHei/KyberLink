module spi_slave (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sck,
    input  wire        mosi,
    input  wire        csn,
    output reg         miso,
    output reg  [ 6:0] waddr,
    output reg  [31:0] wdata,
    output reg         wvalid,
    output reg  [ 6:0] raddr,
    output reg         rreq,
    input  wire [31:0] rdata
);

  reg  [ 5:0] bit_cnt;
  reg  [39:0] sh;
  reg         rd_mode;
  reg  [31:0] rd_data;
  reg         csn_d;
  reg         sck_d;
  reg         sck_s0;
  reg         sck_s1;
  reg         mosi_s0;
  reg         mosi_s1;
  reg         csn_s0;
  reg         csn_s1;
  wire        sck_rise = sck_s1 && !sck_d;
  wire        sck_fall = !sck_s1 && sck_d;
  wire        csn_act = !csn_s1 && csn_d;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sck_s0 <= 1'b0;
      sck_s1 <= 1'b0;
      mosi_s0 <= 1'b0;
      mosi_s1 <= 1'b0;
      csn_s0 <= 1'b1;
      csn_s1 <= 1'b1;
    end else begin
      sck_s0 <= sck;
      sck_s1 <= sck_s0;
      mosi_s0 <= mosi;
      mosi_s1 <= mosi_s0;
      csn_s0 <= csn;
      csn_s1 <= csn_s0;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bit_cnt <= 6'd0;
      sh <= 40'd0;
      rd_mode <= 1'b0;
      rd_data <= 32'd0;
      csn_d <= 1'b1;
      sck_d <= 1'b0;
      miso <= 1'b0;
      waddr <= 7'd0;
      wdata <= 32'd0;
      wvalid <= 1'b0;
      raddr <= 7'd0;
      rreq <= 1'b0;
    end else begin
      csn_d  <= csn_s1;
      sck_d  <= sck_s1;
      wvalid <= 1'b0;
      rreq   <= 1'b0;
      if (csn_act) begin
        bit_cnt <= 6'd0;
        sh <= 40'd0;
        rd_mode <= 1'b0;
        miso <= 1'b0;
      end else if (!csn_s1) begin
        if (sck_rise) begin
          if (bit_cnt == 6'd7) begin
            rd_mode <= sh[6];
            raddr <= {sh[5:0], mosi_s1};
            waddr <= {sh[5:0], mosi_s1};
            rreq <= sh[6];
          end
          sh <= {sh[38:0], mosi_s1};
          bit_cnt <= bit_cnt + 6'd1;
        end
        if (sck_fall) begin
          if (bit_cnt == 6'd8) begin
            rd_data <= rdata;
            miso <= rdata[31];
          end
          if (rd_mode && bit_cnt >= 6'd9 && bit_cnt <= 6'd39) miso <= rd_data[39-bit_cnt];
          if (bit_cnt == 6'd40) begin
            wvalid <= !rd_mode;
            wdata  <= sh[31:0];
          end
        end
      end
    end
  end

endmodule
