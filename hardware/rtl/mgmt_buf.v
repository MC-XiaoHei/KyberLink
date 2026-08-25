module mgmt_buf (
    input  wire        clk_dp,
    input  wire        clk_nrv,
    input  wire        rst_n,

    input  wire        req_wen,
    input  wire [12:0] req_waddr,
    input  wire [7:0]  req_wdata,
    input  wire        req_done_p,
    input  wire [12:0] req_len,
    input  wire        req_ren,
    input  wire [12:0] req_raddr,
    output wire [7:0]  req_rdata,
    output wire        req_pending,
    input  wire        req_ack,

    input  wire        resp_wen,
    input  wire [12:0] resp_waddr,
    input  wire [7:0]  resp_wdata,
    input  wire [12:0] resp_len_w,
    input  wire        resp_done_p,
    input  wire        resp_ren,
    input  wire [12:0] resp_raddr,
    output wire [7:0]  resp_rdata,
    output wire        resp_ready,
    input  wire        resp_clear,
    output wire [12:0] req_len_o,
    output wire [12:0] resp_len_o
);

    wire req_ws0 = req_wen && (req_waddr[12:11] == 2'd0);
    wire req_ws1 = req_wen && (req_waddr[12:11] == 2'd1);
    wire req_ws2 = req_wen && (req_waddr[12:11] == 2'd2);
    wire req_ws3 = req_wen && (req_waddr[12:11] == 2'd3);
    wire req_rs0 = req_ren && (req_raddr[12:11] == 2'd0);
    wire req_rs1 = req_ren && (req_raddr[12:11] == 2'd1);
    wire req_rs2 = req_ren && (req_raddr[12:11] == 2'd2);
    wire req_rs3 = req_ren && (req_raddr[12:11] == 2'd3);
    wire [7:0] req_d0, req_d1, req_d2, req_d3;

    DPB #(.READ_MODE0(1'b1), .READ_MODE1(1'b1), .BIT_WIDTH_0(8), .BIT_WIDTH_1(8)) u_rq0 (
        .DOA(), .DOB(req_d0), .DIA(req_wdata), .DIB(8'd0), .BLKSELA(3'b000), .BLKSELB(3'b000),
        .ADA({req_waddr[10:0], 3'b000}), .ADB({req_raddr[10:0], 3'b000}), .WREA(req_ws0), .WREB(1'b0),
        .CLKA(clk_dp), .CLKB(clk_nrv), .CEA(1'b1), .CEB(req_rs0), .OCEA(1'b0), .OCEB(1'b1),
        .RESETA(~rst_n), .RESETB(~rst_n));
    DPB #(.READ_MODE0(1'b1), .READ_MODE1(1'b1), .BIT_WIDTH_0(8), .BIT_WIDTH_1(8)) u_rq1 (
        .DOA(), .DOB(req_d1), .DIA(req_wdata), .DIB(8'd0), .BLKSELA(3'b000), .BLKSELB(3'b000),
        .ADA({req_waddr[10:0], 3'b000}), .ADB({req_raddr[10:0], 3'b000}), .WREA(req_ws1), .WREB(1'b0),
        .CLKA(clk_dp), .CLKB(clk_nrv), .CEA(1'b1), .CEB(req_rs1), .OCEA(1'b0), .OCEB(1'b1),
        .RESETA(~rst_n), .RESETB(~rst_n));
    DPB #(.READ_MODE0(1'b1), .READ_MODE1(1'b1), .BIT_WIDTH_0(8), .BIT_WIDTH_1(8)) u_rq2 (
        .DOA(), .DOB(req_d2), .DIA(req_wdata), .DIB(8'd0), .BLKSELA(3'b000), .BLKSELB(3'b000),
        .ADA({req_waddr[10:0], 3'b000}), .ADB({req_raddr[10:0], 3'b000}), .WREA(req_ws2), .WREB(1'b0),
        .CLKA(clk_dp), .CLKB(clk_nrv), .CEA(1'b1), .CEB(req_rs2), .OCEA(1'b0), .OCEB(1'b1),
        .RESETA(~rst_n), .RESETB(~rst_n));
    DPB #(.READ_MODE0(1'b1), .READ_MODE1(1'b1), .BIT_WIDTH_0(8), .BIT_WIDTH_1(8)) u_rq3 (
        .DOA(), .DOB(req_d3), .DIA(req_wdata), .DIB(8'd0), .BLKSELA(3'b000), .BLKSELB(3'b000),
        .ADA({req_waddr[10:0], 3'b000}), .ADB({req_raddr[10:0], 3'b000}), .WREA(req_ws3), .WREB(1'b0),
        .CLKA(clk_dp), .CLKB(clk_nrv), .CEA(1'b1), .CEB(req_rs3), .OCEA(1'b0), .OCEB(1'b1),
        .RESETA(~rst_n), .RESETB(~rst_n));

    wire resp_ws0 = resp_wen && (resp_waddr[12:11] == 2'd0);
    wire resp_ws1 = resp_wen && (resp_waddr[12:11] == 2'd1);
    wire resp_ws2 = resp_wen && (resp_waddr[12:11] == 2'd2);
    wire resp_ws3 = resp_wen && (resp_waddr[12:11] == 2'd3);
    wire resp_rs0 = resp_ren && (resp_raddr[12:11] == 2'd0);
    wire resp_rs1 = resp_ren && (resp_raddr[12:11] == 2'd1);
    wire resp_rs2 = resp_ren && (resp_raddr[12:11] == 2'd2);
    wire resp_rs3 = resp_ren && (resp_raddr[12:11] == 2'd3);
    wire [7:0] resp_d0, resp_d1, resp_d2, resp_d3;

    DPB #(.READ_MODE0(1'b1), .READ_MODE1(1'b1), .BIT_WIDTH_0(8), .BIT_WIDTH_1(8)) u_sp0 (
        .DOA(), .DOB(resp_d0), .DIA(resp_wdata), .DIB(8'd0), .BLKSELA(3'b000), .BLKSELB(3'b000),
        .ADA({resp_waddr[10:0], 3'b000}), .ADB({resp_raddr[10:0], 3'b000}), .WREA(resp_ws0), .WREB(1'b0),
        .CLKA(clk_nrv), .CLKB(clk_dp), .CEA(1'b1), .CEB(resp_rs0), .OCEA(1'b0), .OCEB(1'b1),
        .RESETA(~rst_n), .RESETB(~rst_n));
    DPB #(.READ_MODE0(1'b1), .READ_MODE1(1'b1), .BIT_WIDTH_0(8), .BIT_WIDTH_1(8)) u_sp1 (
        .DOA(), .DOB(resp_d1), .DIA(resp_wdata), .DIB(8'd0), .BLKSELA(3'b000), .BLKSELB(3'b000),
        .ADA({resp_waddr[10:0], 3'b000}), .ADB({resp_raddr[10:0], 3'b000}), .WREA(resp_ws1), .WREB(1'b0),
        .CLKA(clk_nrv), .CLKB(clk_dp), .CEA(1'b1), .CEB(resp_rs1), .OCEA(1'b0), .OCEB(1'b1),
        .RESETA(~rst_n), .RESETB(~rst_n));
    DPB #(.READ_MODE0(1'b1), .READ_MODE1(1'b1), .BIT_WIDTH_0(8), .BIT_WIDTH_1(8)) u_sp2 (
        .DOA(), .DOB(resp_d2), .DIA(resp_wdata), .DIB(8'd0), .BLKSELA(3'b000), .BLKSELB(3'b000),
        .ADA({resp_waddr[10:0], 3'b000}), .ADB({resp_raddr[10:0], 3'b000}), .WREA(resp_ws2), .WREB(1'b0),
        .CLKA(clk_nrv), .CLKB(clk_dp), .CEA(1'b1), .CEB(resp_rs2), .OCEA(1'b0), .OCEB(1'b1),
        .RESETA(~rst_n), .RESETB(~rst_n));
    DPB #(.READ_MODE0(1'b1), .READ_MODE1(1'b1), .BIT_WIDTH_0(8), .BIT_WIDTH_1(8)) u_sp3 (
        .DOA(), .DOB(resp_d3), .DIA(resp_wdata), .DIB(8'd0), .BLKSELA(3'b000), .BLKSELB(3'b000),
        .ADA({resp_waddr[10:0], 3'b000}), .ADB({resp_raddr[10:0], 3'b000}), .WREA(resp_ws3), .WREB(1'b0),
        .CLKA(clk_nrv), .CLKB(clk_dp), .CEA(1'b1), .CEB(resp_rs3), .OCEA(1'b0), .OCEB(1'b1),
        .RESETA(~rst_n), .RESETB(~rst_n));

    assign req_rdata = (req_raddr[12:11] == 2'd0) ? req_d0 :
                       (req_raddr[12:11] == 2'd1) ? req_d1 :
                       (req_raddr[12:11] == 2'd2) ? req_d2 : req_d3;
    assign resp_rdata = (resp_raddr[12:11] == 2'd0) ? resp_d0 :
                        (resp_raddr[12:11] == 2'd1) ? resp_d1 :
                        (resp_raddr[12:11] == 2'd2) ? resp_d2 : resp_d3;

    reg req_pending_dp;
    reg req_ack_s1;
    reg req_ack_s2;
    reg req_pending_s1;
    reg req_pending_s2;
    reg [12:0] req_len_s1;
    reg [12:0] req_len_s2;
    reg resp_ready_nrv;
    reg resp_clear_s1;
    reg resp_clear_s2;
    reg resp_ready_s1;
    reg resp_ready_s2;
    reg [12:0] resp_len_s1;
    reg [12:0] resp_len_s2;

    always @(posedge clk_dp or negedge rst_n) begin
        if (!rst_n) begin
            req_pending_dp <= 1'b0;
            req_ack_s1 <= 1'b0;
            req_ack_s2 <= 1'b0;
            resp_ready_s1 <= 1'b0;
            resp_ready_s2 <= 1'b0;
            resp_len_s1 <= 13'd0;
            resp_len_s2 <= 13'd0;
        end else begin
            req_ack_s1 <= req_ack;
            req_ack_s2 <= req_ack_s1;
            if (req_done_p)
                req_pending_dp <= 1'b1;
            else if (req_ack_s2)
                req_pending_dp <= 1'b0;
            resp_ready_s1 <= resp_ready_nrv;
            resp_ready_s2 <= resp_ready_s1;
            resp_len_s1 <= resp_len_w;
            resp_len_s2 <= resp_len_s1;
        end
    end

    always @(posedge clk_nrv or negedge rst_n) begin
        if (!rst_n) begin
            req_pending_s1 <= 1'b0;
            req_pending_s2 <= 1'b0;
            req_len_s1 <= 13'd0;
            req_len_s2 <= 13'd0;
            resp_ready_nrv <= 1'b0;
            resp_clear_s1 <= 1'b0;
            resp_clear_s2 <= 1'b0;
        end else begin
            req_pending_s1 <= req_pending_dp;
            req_pending_s2 <= req_pending_s1;
            req_len_s1 <= req_len;
            req_len_s2 <= req_len_s1;
            resp_clear_s1 <= resp_clear;
            resp_clear_s2 <= resp_clear_s1;
            if (resp_done_p)
                resp_ready_nrv <= 1'b1;
            else if (resp_clear_s2)
                resp_ready_nrv <= 1'b0;
        end
    end

    assign req_pending = req_pending_s2;
    assign resp_ready = resp_ready_s2;
    assign req_len_o = req_len_s2;
    assign resp_len_o = resp_len_s2;

endmodule