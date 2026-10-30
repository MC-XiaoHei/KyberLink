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


module iddr #(

    parameter TARGET = "GENERIC",



    parameter IODDR_STYLE = "IODDR2",

    parameter WIDTH = 1
) (
    input wire clk,

    input wire [WIDTH-1:0] d,

    output wire [WIDTH-1:0] q1,
    output wire [WIDTH-1:0] q2
);



  genvar n;

  generate

    if (TARGET == "XILINX") begin
      for (n = 0; n < WIDTH; n = n + 1) begin : iddr
        if (IODDR_STYLE == "IODDR") begin
          IDDR #(
              .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),
              .SRTYPE("ASYNC")
          ) iddr_inst (
              .Q1(q1[n]),
              .Q2(q2[n]),
              .C (clk),
              .CE(1'b1),
              .D (d[n]),
              .R (1'b0),
              .S (1'b0)
          );
        end else if (IODDR_STYLE == "IODDR2") begin
          wire q1_int;
          reg  q1_delay;

          IDDR2 #(
              .DDR_ALIGNMENT("C0")
          ) iddr_inst (
              .Q0(q1_int),
              .Q1(q2[n]),
              .C0(clk),
              .C1(~clk),
              .CE(1'b1),
              .D (d[n]),
              .R (1'b0),
              .S (1'b0)
          );

          always @(posedge clk) begin
            q1_delay <= q1_int;
          end

          assign q1[n] = q1_delay;
        end
      end
    end else if (TARGET == "GOWIN") begin
      for (n = 0; n < WIDTH; n = n + 1) begin : iddr
        IDDRC #(
            .Q0_INIT(1'b0),
            .Q1_INIT(1'b0)
        ) iddr_inst (
            .Q0(q1[n]),
            .Q1(q2[n]),
            .D(d[n]),
            .CLK(clk),
            .CLEAR(1'b0)
        );
      end
    end else if (TARGET == "ALTERA") begin
      wire [WIDTH-1:0] q1_int;
      reg  [WIDTH-1:0] q1_delay;

      altddio_in #(
          .WIDTH(WIDTH),
          .POWER_UP_HIGH("OFF")
      ) altddio_in_inst (
          .aset(1'b0),
          .datain(d),
          .inclocken(1'b1),
          .inclock(clk),
          .aclr(1'b0),
          .dataout_h(q1_int),
          .dataout_l(q2)
      );

      always @(posedge clk) begin
        q1_delay <= q1_int;
      end

      assign q1 = q1_delay;
    end else begin
      reg [WIDTH-1:0] d_reg_1 = {WIDTH{1'b0}};
      reg [WIDTH-1:0] d_reg_2 = {WIDTH{1'b0}};

      reg [WIDTH-1:0] q_reg_1 = {WIDTH{1'b0}};
      reg [WIDTH-1:0] q_reg_2 = {WIDTH{1'b0}};

      always @(posedge clk) begin
        d_reg_1 <= d;
      end

      always @(negedge clk) begin
        d_reg_2 <= d;
      end

      always @(posedge clk) begin
        q_reg_1 <= d_reg_1;
        q_reg_2 <= d_reg_2;
      end

      assign q1 = q_reg_1;
      assign q2 = q_reg_2;
    end

  endgenerate

endmodule

`resetall

