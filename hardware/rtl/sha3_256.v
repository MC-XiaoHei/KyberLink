module sha3_256 (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [11:0]   len,
    input  wire          msg_wr,
    input  wire [11:0]   msg_waddr,
    input  wire [7:0]    msg_wdata,
    output reg           busy,
    output reg           done,
    output reg           error,
    output wire [255:0]  digest,

    output reg           shk_req,
    output wire [17:0]   shk_cfg,
    input  wire          shk_ready,
    input  wire          shk_done,
    output reg           shk_blk_valid,
    input  wire          shk_blk_ready,
    output wire [1343:0] shk_blk_data,
    input  wire          shk_out_valid,
    output reg           shk_out_ready,
    input  wire [1343:0] shk_out_data
);
    localparam PHASE_IDLE = 2'd0;
    localparam PHASE_RUN  = 2'd1;
    localparam PHASE_DONE = 2'd2;

    reg [1:0]    phase;
    reg [11:0]   len_r;
    reg          c_start;
    reg [7:0]    msg_mem [0:3199];
    reg [255:0]  digest_r;
    integer      bb;

    wire [4:0] cli_nblk;
    wire [4:0] cli_idx;
    wire       cli_os;
    wire [1343:0] cli_bd;

    integer nl;
    reg [4:0] nblk_w;
    always @(*) begin
        nblk_w = 5'd0;
        for (nl = 0; nl < 24; nl = nl + 1) begin
            if ({7'd0, nblk_w} * 12'd136 < len_r) nblk_w = nblk_w + 5'd1;
        end
    end

    assign cli_nblk = nblk_w;
    assign shk_cfg  = {4'd1, 2'd2, len_r};
    assign cli_bd   = {256'b0, blk_w};

    wire [1087:0] blk_w;
    genvar mb;
    generate
        for (mb = 0; mb < 136; mb = mb + 1) begin : mbm
            assign blk_w[8*mb +: 8] =
                ({6'd0, cli_idx} * 12'd136 + (12'd135 - {4'd0, mb[7:0]}) < len_r)
                ? msg_mem[{6'd0, cli_idx} * 12'd136 + (12'd135 - {4'd0, mb[7:0]})]
                : 8'd0;
        end
    endgenerate

    engine_client #(.NBLK_W(5)) u_cli (
        .clk(clk), .rst_n(rst_n),
        .start(c_start), .cfg(shk_cfg), .nblk(cli_nblk), .msg_blk(cli_bd),
        .req_ready(shk_ready), .blk_ready(shk_blk_ready),
        .out_valid(shk_out_valid), .done(shk_done),
        .req_valid(shk_req), .blk_valid(shk_blk_valid), .blk_data(shk_blk_data),
        .out_ready(shk_out_ready), .blk_idx(cli_idx), .out_sync(cli_os)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            error <= 1'b0;
            len_r <= 12'd0;
            c_start <= 1'b0;
            digest_r <= 256'b0;
        end else begin
            done <= 1'b0;
            if (msg_wr) msg_mem[msg_waddr] <= msg_wdata;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        len_r <= len;
                        c_start <= 1'b1;
                        phase <= PHASE_RUN;
                    end
                end
                PHASE_RUN: begin
                    c_start <= 1'b0;
                    if (cli_os) begin
                        for (bb = 0; bb < 32; bb = bb + 1)
                            digest_r[8*(31-bb) +: 8] <= shk_out_data[1087 - 8*bb -: 8];
                    end
                    if (shk_done) phase <= PHASE_DONE;
                end
                PHASE_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    phase <= PHASE_IDLE;
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end

    assign digest = digest_r;
endmodule
