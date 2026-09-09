module arp_catch (
    input wire clk,
    input wire rst_n,

    input  wire [ 7:0] s_tdata,
    input  wire        s_tvalid,
    input  wire        s_tlast,
    input  wire [31:0] cfg_src_ip,
    input  wire        arp_read,
    output reg         pending,
    output reg [79:0]  capture
);

  reg [8:0] wcnt;
  reg p12h, p12l, p20h, p20l;
  reg p38a, p38b, p38c;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wcnt <= 9'd0;
      pending <= 1'b0;
      capture <= 80'd0;
      p12h <= 1'b0;
      p12l <= 1'b0;
      p20h <= 1'b0;
      p20l <= 1'b0;
      p38a <= 1'b0;
      p38b <= 1'b0;
      p38c <= 1'b0;
    end else begin
      if (s_tvalid) begin
        case (wcnt)
          9'd12: p12h <= (s_tdata == 8'h08);
          9'd13: p12l <= (s_tdata == 8'h06);
          9'd20: p20h <= (s_tdata == 8'h00);
          9'd21: p20l <= (s_tdata == 8'h01);
          9'd22: capture[79:72] <= s_tdata;
          9'd23: capture[71:64] <= s_tdata;
          9'd24: capture[63:56] <= s_tdata;
          9'd25: capture[55:48] <= s_tdata;
          9'd26: capture[47:40] <= s_tdata;
          9'd27: capture[39:32] <= s_tdata;
          9'd28: capture[31:24] <= s_tdata;
          9'd29: capture[23:16] <= s_tdata;
          9'd30: capture[15:8] <= s_tdata;
          9'd31: capture[7:0] <= s_tdata;
          9'd38: p38a <= (s_tdata == cfg_src_ip[31:24]);
          9'd39: p38b <= (s_tdata == cfg_src_ip[23:16]);
          9'd40: p38c <= (s_tdata == cfg_src_ip[15:8]);
          default: ;
        endcase
        if (s_tlast) begin
          wcnt <= 9'd0;
          if (!wcnt[8] && wcnt >= 9'd41 && p12h && p12l && p20h && p20l
              && p38a && p38b && p38c && (s_tdata == cfg_src_ip[7:0])) begin
            pending <= 1'b1;
          end
        end else begin
          wcnt <= wcnt + 9'd1;
        end
      end
      if (arp_read) pending <= 1'b0;
    end
  end

endmodule
