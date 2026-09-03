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


module ssio_sdr_in #(

    parameter TARGET = "GENERIC",




    parameter CLOCK_INPUT_STYLE = "BUFIO2",

    parameter WIDTH = 1
) (
    input wire input_clk,

    input wire [WIDTH-1:0] input_d,

    output wire output_clk,

    output wire [WIDTH-1:0] output_q
);

  wire clk_int;
  wire clk_io;

  generate

    if (TARGET == "XILINX") begin



      if (CLOCK_INPUT_STYLE == "BUFG") begin


        BUFG clk_bufg (
            .I(input_clk),
            .O(clk_int)
        );


        assign clk_io = clk_int;
        assign output_clk = clk_int;

      end else if (CLOCK_INPUT_STYLE == "BUFR") begin

        assign clk_int = input_clk;


        BUFIO clk_bufio (
            .I(clk_int),
            .O(clk_io)
        );


        BUFR #(
            .BUFR_DIVIDE("BYPASS")
        ) clk_bufr (
            .I  (clk_int),
            .O  (output_clk),
            .CE (1'b1),
            .CLR(1'b0)
        );

      end else if (CLOCK_INPUT_STYLE == "BUFIO") begin

        assign clk_int = input_clk;


        BUFIO clk_bufio (
            .I(clk_int),
            .O(clk_io)
        );


        BUFG clk_bufg (
            .I(clk_int),
            .O(output_clk)
        );

      end else if (CLOCK_INPUT_STYLE == "BUFIO2") begin


        BUFIO2 #(
            .DIVIDE(1),
            .DIVIDE_BYPASS("TRUE"),
            .I_INVERT("FALSE"),
            .USE_DOUBLER("FALSE")
        ) clk_bufio (
            .I(input_clk),
            .DIVCLK(clk_int),
            .IOCLK(clk_io),
            .SERDESSTROBE()
        );


        BUFG clk_bufg (
            .I(clk_int),
            .O(output_clk)
        );

      end

    end else begin


      assign clk_io = input_clk;


      assign clk_int = input_clk;
      assign output_clk = clk_int;

    end

  endgenerate

  (* IOB = "TRUE" *)
  reg [WIDTH-1:0] output_q_reg = {WIDTH{1'b0}};

  assign output_q = output_q_reg;

  always @(posedge clk_io) begin
    output_q_reg <= input_d;
  end

endmodule

`resetall

