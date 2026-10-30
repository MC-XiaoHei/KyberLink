/*

Copyright (c) 2016-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/



`resetall
`timescale 1ns / 1ps
`default_nettype none


module oddr #(

    parameter TARGET = "GENERIC",



    parameter IODDR_STYLE = "IODDR2",

    parameter WIDTH = 1
) (
    input wire clk,

    input wire [WIDTH-1:0] d1,
    input wire [WIDTH-1:0] d2,

    output wire [WIDTH-1:0] q
);



  genvar n;

  generate

    if (TARGET == "XILINX") begin
      for (n = 0; n < WIDTH; n = n + 1) begin : oddr
        if (IODDR_STYLE == "IODDR") begin
          ODDR #(
              .DDR_CLK_EDGE("SAME_EDGE"),
              .SRTYPE("ASYNC")
          ) oddr_inst (
              .Q (q[n]),
              .C (clk),
              .CE(1'b1),
              .D1(d1[n]),
              .D2(d2[n]),
              .R (1'b0),
              .S (1'b0)
          );
        end else if (IODDR_STYLE == "IODDR2") begin
          ODDR2 #(
              .DDR_ALIGNMENT("C0"),
              .SRTYPE("ASYNC")
          ) oddr_inst (
              .Q (q[n]),
              .C0(clk),
              .C1(~clk),
              .CE(1'b1),
              .D0(d1[n]),
              .D1(d2[n]),
              .R (1'b0),
              .S (1'b0)
          );
        end
      end
    end else if (TARGET == "ALTERA") begin
      altddio_out #(
          .WIDTH(WIDTH),
          .POWER_UP_HIGH("OFF"),
          .OE_REG("UNUSED")
      ) altddio_out_inst (
          .aset(1'b0),
          .datain_h(d1),
          .datain_l(d2),
          .outclocken(1'b1),
          .outclock(clk),
          .aclr(1'b0),
          .dataout(q)
      );
    end else if (TARGET == "GOWIN") begin

      for (n = 0; n < WIDTH; n = n + 1) begin : oddr
        ODDRC #(
            .INIT(1'b0)
        ) oddr_inst (
            .Q0(q[n]),
            .Q1(),
            .D0(d1[n]),
            .D1(d2[n]),
            .TX(1'b1),
            .CLK(clk),
            .CLEAR(1'b0)
        );
      end
    end else begin
      reg [WIDTH-1:0] d_reg_1 = {WIDTH{1'b0}};
      reg [WIDTH-1:0] d_reg_2 = {WIDTH{1'b0}};

      always @(posedge clk) begin
        d_reg_1 <= d1;
      end

      always @(negedge clk) begin
        d_reg_2 <= d2;
      end

      assign q = clk ? d_reg_1 : d_reg_2;
    end

  endgenerate

endmodule

`resetall

