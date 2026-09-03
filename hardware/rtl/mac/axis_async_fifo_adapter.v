/*

Copyright (c) 2019 Alex Forencich

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


module axis_async_fifo_adapter #(



    parameter DEPTH = 4096,

    parameter S_DATA_WIDTH = 8,


    parameter S_KEEP_ENABLE = (S_DATA_WIDTH > 8),

    parameter S_KEEP_WIDTH = ((S_DATA_WIDTH + 7) / 8),

    parameter M_DATA_WIDTH = 8,


    parameter M_KEEP_ENABLE = (M_DATA_WIDTH > 8),

    parameter M_KEEP_WIDTH = ((M_DATA_WIDTH + 7) / 8),

    parameter ID_ENABLE = 0,

    parameter ID_WIDTH = 8,

    parameter DEST_ENABLE = 0,

    parameter DEST_WIDTH = 8,

    parameter USER_ENABLE = 1,

    parameter USER_WIDTH = 1,

    parameter RAM_PIPELINE = 1,


    parameter OUTPUT_FIFO_ENABLE = 0,



    parameter FRAME_FIFO = 0,

    parameter USER_BAD_FRAME_VALUE = 1'b1,

    parameter USER_BAD_FRAME_MASK = 1'b1,


    parameter DROP_OVERSIZE_FRAME = FRAME_FIFO,


    parameter DROP_BAD_FRAME = 0,



    parameter DROP_WHEN_FULL = 0,



    parameter MARK_WHEN_FULL = 0,

    parameter PAUSE_ENABLE = 0,

    parameter FRAME_PAUSE = FRAME_FIFO
) (

    input  wire                    s_clk,
    input  wire                    s_rst,
    input  wire [S_DATA_WIDTH-1:0] s_axis_tdata,
    input  wire [S_KEEP_WIDTH-1:0] s_axis_tkeep,
    input  wire                    s_axis_tvalid,
    output wire                    s_axis_tready,
    input  wire                    s_axis_tlast,
    input  wire [    ID_WIDTH-1:0] s_axis_tid,
    input  wire [  DEST_WIDTH-1:0] s_axis_tdest,
    input  wire [  USER_WIDTH-1:0] s_axis_tuser,


    input  wire                    m_clk,
    input  wire                    m_rst,
    output wire [M_DATA_WIDTH-1:0] m_axis_tdata,
    output wire [M_KEEP_WIDTH-1:0] m_axis_tkeep,
    output wire                    m_axis_tvalid,
    input  wire                    m_axis_tready,
    output wire                    m_axis_tlast,
    output wire [    ID_WIDTH-1:0] m_axis_tid,
    output wire [  DEST_WIDTH-1:0] m_axis_tdest,
    output wire [  USER_WIDTH-1:0] m_axis_tuser,


    input  wire s_pause_req,
    output wire s_pause_ack,
    input  wire m_pause_req,
    output wire m_pause_ack,


    output wire [$clog2(DEPTH):0] s_status_depth,
    output wire [$clog2(DEPTH):0] s_status_depth_commit,
    output wire                   s_status_overflow,
    output wire                   s_status_bad_frame,
    output wire                   s_status_good_frame,
    output wire [$clog2(DEPTH):0] m_status_depth,
    output wire [$clog2(DEPTH):0] m_status_depth_commit,
    output wire                   m_status_overflow,
    output wire                   m_status_bad_frame,
    output wire                   m_status_good_frame
);


  localparam S_BYTE_LANES = S_KEEP_ENABLE ? S_KEEP_WIDTH : 1;
  localparam M_BYTE_LANES = M_KEEP_ENABLE ? M_KEEP_WIDTH : 1;


  localparam S_BYTE_SIZE  = S_DATA_WIDTH / S_BYTE_LANES;
  localparam M_BYTE_SIZE  = M_DATA_WIDTH / M_BYTE_LANES;

  localparam EXPAND_BUS   = M_BYTE_LANES > S_BYTE_LANES;

  localparam DATA_WIDTH   = EXPAND_BUS ? M_DATA_WIDTH : S_DATA_WIDTH;
  localparam KEEP_WIDTH   = EXPAND_BUS ? M_BYTE_LANES : S_BYTE_LANES;


  initial begin
    if (S_BYTE_SIZE * S_BYTE_LANES != S_DATA_WIDTH) begin
      $error("Error: input data width not evenly divisible (instance %m)");
      $finish;
    end

    if (M_BYTE_SIZE * M_BYTE_LANES != M_DATA_WIDTH) begin
      $error("Error: output data width not evenly divisible (instance %m)");
      $finish;
    end

    if (S_BYTE_SIZE != M_BYTE_SIZE) begin
      $error("Error: byte size mismatch (instance %m)");
      $finish;
    end
  end

  wire [DATA_WIDTH-1:0] pre_fifo_axis_tdata;
  wire [KEEP_WIDTH-1:0] pre_fifo_axis_tkeep;
  wire                  pre_fifo_axis_tvalid;
  wire                  pre_fifo_axis_tready;
  wire                  pre_fifo_axis_tlast;
  wire [  ID_WIDTH-1:0] pre_fifo_axis_tid;
  wire [DEST_WIDTH-1:0] pre_fifo_axis_tdest;
  wire [USER_WIDTH-1:0] pre_fifo_axis_tuser;

  wire [DATA_WIDTH-1:0] post_fifo_axis_tdata;
  wire [KEEP_WIDTH-1:0] post_fifo_axis_tkeep;
  wire                  post_fifo_axis_tvalid;
  wire                  post_fifo_axis_tready;
  wire                  post_fifo_axis_tlast;
  wire [  ID_WIDTH-1:0] post_fifo_axis_tid;
  wire [DEST_WIDTH-1:0] post_fifo_axis_tdest;
  wire [USER_WIDTH-1:0] post_fifo_axis_tuser;

  generate

    if (M_BYTE_LANES > S_BYTE_LANES) begin : upsize_pre



      axis_adapter #(
          .S_DATA_WIDTH(S_DATA_WIDTH),
          .S_KEEP_ENABLE(S_KEEP_ENABLE),
          .S_KEEP_WIDTH(S_KEEP_WIDTH),
          .M_DATA_WIDTH(M_DATA_WIDTH),
          .M_KEEP_ENABLE(M_KEEP_ENABLE),
          .M_KEEP_WIDTH(M_KEEP_WIDTH),
          .ID_ENABLE(ID_ENABLE),
          .ID_WIDTH(ID_WIDTH),
          .DEST_ENABLE(DEST_ENABLE),
          .DEST_WIDTH(DEST_WIDTH),
          .USER_ENABLE(USER_ENABLE),
          .USER_WIDTH(USER_WIDTH)
      ) adapter_inst (
          .clk(s_clk),
          .rst(s_rst),

          .s_axis_tdata(s_axis_tdata),
          .s_axis_tkeep(s_axis_tkeep),
          .s_axis_tvalid(s_axis_tvalid),
          .s_axis_tready(s_axis_tready),
          .s_axis_tlast(s_axis_tlast),
          .s_axis_tid(s_axis_tid),
          .s_axis_tdest(s_axis_tdest),
          .s_axis_tuser(s_axis_tuser),

          .m_axis_tdata(pre_fifo_axis_tdata),
          .m_axis_tkeep(pre_fifo_axis_tkeep),
          .m_axis_tvalid(pre_fifo_axis_tvalid),
          .m_axis_tready(pre_fifo_axis_tready),
          .m_axis_tlast(pre_fifo_axis_tlast),
          .m_axis_tid(pre_fifo_axis_tid),
          .m_axis_tdest(pre_fifo_axis_tdest),
          .m_axis_tuser(pre_fifo_axis_tuser)
      );

    end else begin : bypass_pre

      assign pre_fifo_axis_tdata = s_axis_tdata;
      assign pre_fifo_axis_tkeep = s_axis_tkeep;
      assign pre_fifo_axis_tvalid = s_axis_tvalid;
      assign s_axis_tready = pre_fifo_axis_tready;
      assign pre_fifo_axis_tlast = s_axis_tlast;
      assign pre_fifo_axis_tid = s_axis_tid;
      assign pre_fifo_axis_tdest = s_axis_tdest;
      assign pre_fifo_axis_tuser = s_axis_tuser;

    end

    axis_async_fifo #(
        .DEPTH(DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(EXPAND_BUS ? M_KEEP_ENABLE : S_KEEP_ENABLE),
        .KEEP_WIDTH(KEEP_WIDTH),
        .LAST_ENABLE(1),
        .ID_ENABLE(ID_ENABLE),
        .ID_WIDTH(ID_WIDTH),
        .DEST_ENABLE(DEST_ENABLE),
        .DEST_WIDTH(DEST_WIDTH),
        .USER_ENABLE(USER_ENABLE),
        .USER_WIDTH(USER_WIDTH),
        .RAM_PIPELINE(RAM_PIPELINE),
        .OUTPUT_FIFO_ENABLE(OUTPUT_FIFO_ENABLE),
        .FRAME_FIFO(FRAME_FIFO),
        .USER_BAD_FRAME_VALUE(USER_BAD_FRAME_VALUE),
        .USER_BAD_FRAME_MASK(USER_BAD_FRAME_MASK),
        .DROP_OVERSIZE_FRAME(DROP_OVERSIZE_FRAME),
        .DROP_BAD_FRAME(DROP_BAD_FRAME),
        .DROP_WHEN_FULL(DROP_WHEN_FULL),
        .MARK_WHEN_FULL(MARK_WHEN_FULL),
        .PAUSE_ENABLE(PAUSE_ENABLE),
        .FRAME_PAUSE(FRAME_PAUSE)
    ) fifo_inst (

        .s_clk(s_clk),
        .s_rst(s_rst),
        .s_axis_tdata(pre_fifo_axis_tdata),
        .s_axis_tkeep(pre_fifo_axis_tkeep),
        .s_axis_tvalid(pre_fifo_axis_tvalid),
        .s_axis_tready(pre_fifo_axis_tready),
        .s_axis_tlast(pre_fifo_axis_tlast),
        .s_axis_tid(pre_fifo_axis_tid),
        .s_axis_tdest(pre_fifo_axis_tdest),
        .s_axis_tuser(pre_fifo_axis_tuser),

        .m_clk(m_clk),
        .m_rst(m_rst),
        .m_axis_tdata(post_fifo_axis_tdata),
        .m_axis_tkeep(post_fifo_axis_tkeep),
        .m_axis_tvalid(post_fifo_axis_tvalid),
        .m_axis_tready(post_fifo_axis_tready),
        .m_axis_tlast(post_fifo_axis_tlast),
        .m_axis_tid(post_fifo_axis_tid),
        .m_axis_tdest(post_fifo_axis_tdest),
        .m_axis_tuser(post_fifo_axis_tuser),

        .s_pause_req(s_pause_req),
        .s_pause_ack(s_pause_ack),
        .m_pause_req(m_pause_req),
        .m_pause_ack(m_pause_ack),

        .s_status_depth(s_status_depth),
        .s_status_depth_commit(s_status_depth_commit),
        .s_status_overflow(s_status_overflow),
        .s_status_bad_frame(s_status_bad_frame),
        .s_status_good_frame(s_status_good_frame),
        .m_status_depth(m_status_depth),
        .m_status_depth_commit(m_status_depth_commit),
        .m_status_overflow(m_status_overflow),
        .m_status_bad_frame(m_status_bad_frame),
        .m_status_good_frame(m_status_good_frame)
    );

    if (M_BYTE_LANES < S_BYTE_LANES) begin : downsize_post



      axis_adapter #(
          .S_DATA_WIDTH(S_DATA_WIDTH),
          .S_KEEP_ENABLE(S_KEEP_ENABLE),
          .S_KEEP_WIDTH(S_KEEP_WIDTH),
          .M_DATA_WIDTH(M_DATA_WIDTH),
          .M_KEEP_ENABLE(M_KEEP_ENABLE),
          .M_KEEP_WIDTH(M_KEEP_WIDTH),
          .ID_ENABLE(ID_ENABLE),
          .ID_WIDTH(ID_WIDTH),
          .DEST_ENABLE(DEST_ENABLE),
          .DEST_WIDTH(DEST_WIDTH),
          .USER_ENABLE(USER_ENABLE),
          .USER_WIDTH(USER_WIDTH)
      ) adapter_inst (
          .clk(m_clk),
          .rst(m_rst),

          .s_axis_tdata(post_fifo_axis_tdata),
          .s_axis_tkeep(post_fifo_axis_tkeep),
          .s_axis_tvalid(post_fifo_axis_tvalid),
          .s_axis_tready(post_fifo_axis_tready),
          .s_axis_tlast(post_fifo_axis_tlast),
          .s_axis_tid(post_fifo_axis_tid),
          .s_axis_tdest(post_fifo_axis_tdest),
          .s_axis_tuser(post_fifo_axis_tuser),

          .m_axis_tdata(m_axis_tdata),
          .m_axis_tkeep(m_axis_tkeep),
          .m_axis_tvalid(m_axis_tvalid),
          .m_axis_tready(m_axis_tready),
          .m_axis_tlast(m_axis_tlast),
          .m_axis_tid(m_axis_tid),
          .m_axis_tdest(m_axis_tdest),
          .m_axis_tuser(m_axis_tuser)
      );

    end else begin : bypass_post

      assign m_axis_tdata = post_fifo_axis_tdata;
      assign m_axis_tkeep = post_fifo_axis_tkeep;
      assign m_axis_tvalid = post_fifo_axis_tvalid;
      assign post_fifo_axis_tready = m_axis_tready;
      assign m_axis_tlast = post_fifo_axis_tlast;
      assign m_axis_tid = post_fifo_axis_tid;
      assign m_axis_tdest = post_fifo_axis_tdest;
      assign m_axis_tuser = post_fifo_axis_tuser;

    end

  endgenerate

endmodule

`resetall

