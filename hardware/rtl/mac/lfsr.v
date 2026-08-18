/*

Copyright (c) 2016-2023 Alex Forencich

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


module lfsr #
(

    parameter LFSR_WIDTH = 31,

    parameter LFSR_POLY = 31'h10000001,

    parameter LFSR_CONFIG = "FIBONACCI",

    parameter LFSR_FEED_FORWARD = 0,

    parameter REVERSE = 0,

    parameter DATA_WIDTH = 8,

    parameter STYLE = "AUTO"
)
(
    input  wire [DATA_WIDTH-1:0] data_in,
    input  wire [LFSR_WIDTH-1:0] state_in,
    output wire [DATA_WIDTH-1:0] data_out,
    output wire [LFSR_WIDTH-1:0] state_out
);



function [LFSR_WIDTH+DATA_WIDTH-1:0] lfsr_mask(input [31:0] index);
    reg [LFSR_WIDTH-1:0] lfsr_mask_state[LFSR_WIDTH-1:0];
    reg [DATA_WIDTH-1:0] lfsr_mask_data[LFSR_WIDTH-1:0];
    reg [LFSR_WIDTH-1:0] output_mask_state[DATA_WIDTH-1:0];
    reg [DATA_WIDTH-1:0] output_mask_data[DATA_WIDTH-1:0];

    reg [LFSR_WIDTH-1:0] state_val;
    reg [DATA_WIDTH-1:0] data_val;

    reg [DATA_WIDTH-1:0] data_mask;

    integer i, j;

    begin

        for (i = 0; i < LFSR_WIDTH; i = i + 1) begin
            lfsr_mask_state[i] = 0;
            lfsr_mask_state[i][i] = 1'b1;
            lfsr_mask_data[i] = 0;
        end
        for (i = 0; i < DATA_WIDTH; i = i + 1) begin
            output_mask_state[i] = 0;
            if (i < LFSR_WIDTH) begin
                output_mask_state[i][i] = 1'b1;
            end
            output_mask_data[i] = 0;
        end


        if (LFSR_CONFIG == "FIBONACCI") begin

            for (data_mask = {1'b1, {DATA_WIDTH-1{1'b0}}}; data_mask != 0; data_mask = data_mask >> 1) begin


                state_val = lfsr_mask_state[LFSR_WIDTH-1];
                data_val = lfsr_mask_data[LFSR_WIDTH-1];
                data_val = data_val ^ data_mask;


                for (j = 1; j < LFSR_WIDTH; j = j + 1) begin
                    if ((LFSR_POLY >> j) & 1) begin
                        state_val = lfsr_mask_state[j-1] ^ state_val;
                        data_val = lfsr_mask_data[j-1] ^ data_val;
                    end
                end


                for (j = LFSR_WIDTH-1; j > 0; j = j - 1) begin
                    lfsr_mask_state[j] = lfsr_mask_state[j-1];
                    lfsr_mask_data[j] = lfsr_mask_data[j-1];
                end
                for (j = DATA_WIDTH-1; j > 0; j = j - 1) begin
                    output_mask_state[j] = output_mask_state[j-1];
                    output_mask_data[j] = output_mask_data[j-1];
                end
                output_mask_state[0] = state_val;
                output_mask_data[0] = data_val;
                if (LFSR_FEED_FORWARD) begin

                    state_val = {LFSR_WIDTH{1'b0}};
                    data_val = data_mask;
                end
                lfsr_mask_state[0] = state_val;
                lfsr_mask_data[0] = data_val;
            end
        end else if (LFSR_CONFIG == "GALOIS") begin

            for (data_mask = {1'b1, {DATA_WIDTH-1{1'b0}}}; data_mask != 0; data_mask = data_mask >> 1) begin


                state_val = lfsr_mask_state[LFSR_WIDTH-1];
                data_val = lfsr_mask_data[LFSR_WIDTH-1];
                data_val = data_val ^ data_mask;


                for (j = LFSR_WIDTH-1; j > 0; j = j - 1) begin
                    lfsr_mask_state[j] = lfsr_mask_state[j-1];
                    lfsr_mask_data[j] = lfsr_mask_data[j-1];
                end
                for (j = DATA_WIDTH-1; j > 0; j = j - 1) begin
                    output_mask_state[j] = output_mask_state[j-1];
                    output_mask_data[j] = output_mask_data[j-1];
                end
                output_mask_state[0] = state_val;
                output_mask_data[0] = data_val;
                if (LFSR_FEED_FORWARD) begin

                    state_val = {LFSR_WIDTH{1'b0}};
                    data_val = data_mask;
                end
                lfsr_mask_state[0] = state_val;
                lfsr_mask_data[0] = data_val;


                for (j = 1; j < LFSR_WIDTH; j = j + 1) begin
                    if ((LFSR_POLY >> j) & 1) begin
                        lfsr_mask_state[j] = lfsr_mask_state[j] ^ state_val;
                        lfsr_mask_data[j] = lfsr_mask_data[j] ^ data_val;
                    end
                end
            end
        end else begin
            $error("Error: unknown configuration setting!");
            $finish;
        end


        if (REVERSE) begin
            if (index < LFSR_WIDTH) begin
                state_val = 0;
                for (i = 0; i < LFSR_WIDTH; i = i + 1) begin
                    state_val[i] = lfsr_mask_state[LFSR_WIDTH-index-1][LFSR_WIDTH-i-1];
                end

                data_val = 0;
                for (i = 0; i < DATA_WIDTH; i = i + 1) begin
                    data_val[i] = lfsr_mask_data[LFSR_WIDTH-index-1][DATA_WIDTH-i-1];
                end
            end else begin
                state_val = 0;
                for (i = 0; i < LFSR_WIDTH; i = i + 1) begin
                    state_val[i] = output_mask_state[DATA_WIDTH-(index-LFSR_WIDTH)-1][LFSR_WIDTH-i-1];
                end

                data_val = 0;
                for (i = 0; i < DATA_WIDTH; i = i + 1) begin
                    data_val[i] = output_mask_data[DATA_WIDTH-(index-LFSR_WIDTH)-1][DATA_WIDTH-i-1];
                end
            end
        end else begin
            if (index < LFSR_WIDTH) begin
                state_val = lfsr_mask_state[index];
                data_val = lfsr_mask_data[index];
            end else begin
                state_val = output_mask_state[index-LFSR_WIDTH];
                data_val = output_mask_data[index-LFSR_WIDTH];
            end
        end
        lfsr_mask = {data_val, state_val};
    end
endfunction


`define SIMULATION


`ifdef SIMULATION

parameter STYLE_INT = (STYLE == "AUTO") ? "REDUCTION" : STYLE;
`else

parameter STYLE_INT = (STYLE == "AUTO") ? "LOOP" : STYLE;
`endif

genvar n;

generate

if (STYLE_INT == "REDUCTION") begin







    for (n = 0; n < LFSR_WIDTH; n = n + 1) begin : lfsr_state
        wire [LFSR_WIDTH+DATA_WIDTH-1:0] mask = lfsr_mask(n);
        assign state_out[n] = ^({data_in, state_in} & mask);
    end
    for (n = 0; n < DATA_WIDTH; n = n + 1) begin : lfsr_data
        wire [LFSR_WIDTH+DATA_WIDTH-1:0] mask = lfsr_mask(n+LFSR_WIDTH);
        assign data_out[n] = ^({data_in, state_in} & mask);
    end

end else if (STYLE_INT == "LOOP") begin







    for (n = 0; n < LFSR_WIDTH; n = n + 1) begin : lfsr_state
        wire [LFSR_WIDTH+DATA_WIDTH-1:0] mask = lfsr_mask(n);

        reg state_reg;

        assign state_out[n] = state_reg;

        integer i;

        always @* begin
            state_reg = 1'b0;
            for (i = 0; i < LFSR_WIDTH; i = i + 1) begin
                if (mask[i]) begin
                    state_reg = state_reg ^ state_in[i];
                end
            end
            for (i = 0; i < DATA_WIDTH; i = i + 1) begin
                if (mask[i+LFSR_WIDTH]) begin
                    state_reg = state_reg ^ data_in[i];
                end
            end
        end
    end
    for (n = 0; n < DATA_WIDTH; n = n + 1) begin : lfsr_data
        wire [LFSR_WIDTH+DATA_WIDTH-1:0] mask = lfsr_mask(n+LFSR_WIDTH);

        reg data_reg;

        assign data_out[n] = data_reg;

        integer i;

        always @* begin
            data_reg = 1'b0;
            for (i = 0; i < LFSR_WIDTH; i = i + 1) begin
                if (mask[i]) begin
                    data_reg = data_reg ^ state_in[i];
                end
            end
            for (i = 0; i < DATA_WIDTH; i = i + 1) begin
                if (mask[i+LFSR_WIDTH]) begin
                    data_reg = data_reg ^ data_in[i];
                end
            end
        end
    end

end else begin

    initial begin
        $error("Error: unknown style setting!");
        $finish;
    end

end

endgenerate

endmodule

`resetall

