module hs_rx (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] s_tdata,
    input  wire       s_tvalid,
    input  wire       s_tlast,
    output wire       s_tready,

    input  wire       req_pending_nrv,
    output wire       req_wen,
    output wire [12:0] req_waddr,
    output wire [7:0]  req_wdata,
    output reg         req_done_p,
    output reg  [12:0] req_len
);

    localparam DEPTH = 4096;
    reg [7:0] fifo_mem [0:DEPTH-1];
    reg       fifo_last [0:DEPTH-1];
    reg [11:0] wr_ptr;
    reg [11:0] rd_ptr;
    reg [12:0] fifo_cnt;

    reg pending_s1;
    reg pending_s2;

    wire fifo_full  = (fifo_cnt >= DEPTH);
    wire fifo_empty = (fifo_cnt == 0);
    assign s_tready = !fifo_full;

    wire wr_en = s_tvalid && s_tready;

    reg rd_busy;
    reg [12:0] wptr;

    wire rd_data = rd_busy && !fifo_empty;
    wire rd_last = rd_data && fifo_last[rd_ptr];
    wire rd_en   = rd_data;

    assign req_wen   = rd_data;
    assign req_waddr = wptr;
    assign req_wdata = fifo_mem[rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_s1 <= 1'b0;
            pending_s2 <= 1'b0;
            wr_ptr <= 12'd0;
            rd_ptr <= 12'd0;
            fifo_cnt <= 13'd0;
            rd_busy <= 1'b0;
            wptr <= 13'd0;
            req_done_p <= 1'b0;
            req_len <= 13'd0;
        end else begin
            pending_s1 <= req_pending_nrv;
            pending_s2 <= pending_s1;
            req_done_p <= 1'b0;

            if (wr_en) begin
                fifo_mem[wr_ptr] <= s_tdata;
                fifo_last[wr_ptr] <= s_tlast;
                wr_ptr <= wr_ptr + 12'd1;
            end
            if (rd_en)
                rd_ptr <= rd_ptr + 12'd1;
            if (wr_en && !rd_en)
                fifo_cnt <= fifo_cnt + 13'd1;
            else if (!wr_en && rd_en)
                fifo_cnt <= fifo_cnt - 13'd1;

            if (!rd_busy && !pending_s2 && !fifo_empty) begin
                rd_busy <= 1'b1;
                wptr <= 13'd0;
            end
            if (rd_last) begin
                rd_busy <= 1'b0;
                req_len <= wptr + 13'd1;
                req_done_p <= 1'b1;
                wptr <= 13'd0;
            end else if (rd_en) begin
                wptr <= wptr + 13'd1;
            end
        end
    end

endmodule
