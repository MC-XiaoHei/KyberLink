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
  wire        sck_rise = sck && !sck_d;
  wire        sck_fall = !sck && sck_d;
  wire        csn_act = !csn && csn_d;

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
      csn_d  <= csn;
      sck_d  <= sck;
      wvalid <= 1'b0;
      rreq   <= 1'b0;
      if (csn_act) begin
        bit_cnt <= 6'd0;
        sh <= 40'd0;
        rd_mode <= 1'b0;
        miso <= 1'b0;
      end else if (!csn) begin
        if (sck_rise) begin
          if (bit_cnt == 6'd7) begin
            rd_mode <= sh[6];
            raddr <= {sh[5:0], mosi};
            waddr <= {sh[5:0], mosi};
            rreq <= sh[6];
          end
          sh <= {sh[38:0], mosi};
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
