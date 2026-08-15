module hkdf_sha3_256 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [255:0] h4_in,
    input  wire [255:0] ss_i_in,
    input  wire [255:0] ss_r_in,
    input  wire [31:0]  spi_i_in,
    input  wire [31:0]  spi_r_in,
    output reg          busy,
    output reg          done,
    output wire         error,
    output wire [767:0] okm,

    output reg          shk_req,
    output wire [17:0]  shk_cfg,
    input  wire         shk_ready,
    input  wire         shk_done,
    output reg          shk_blk_valid,
    input  wire         shk_blk_ready,
    output wire [1343:0] shk_blk_data,
    input  wire         shk_out_valid,
    output reg          shk_out_ready,
    input  wire [1343:0] shk_out_data
);
    localparam PHASE_IDLE  = 3'd0;
    localparam PHASE_WR    = 3'd1;
    localparam PHASE_START = 3'd2;
    localparam PHASE_RUN   = 3'd3;
    localparam PHASE_DONE  = 3'd4;

    wire [119:0] INFO_STR = 120'h4b796265724c696e6b2d76312d5341;

    reg [2:0]  phase;
    reg [2:0]  stage;
    reg [7:0]  wpos;
    reg [255:0] h4_r;
    reg [255:0] ss_i_r;
    reg [255:0] ss_r_r;
    reg [31:0] spi_i_r;
    reg [31:0] spi_r_r;
    reg [255:0] inner_r;
    reg [255:0] prk_r;
    reg [255:0] td_r;
    reg [255:0] t1_r;
    reg [255:0] t2_r;
    reg [255:0] t3_r;

    reg          u_start;
    reg          u_wr;
    reg [7:0]    u_waddr;
    reg [7:0]    u_wdata;
    wire [11:0]  u_len;
    wire         u_done;
    wire [255:0] u_digest;

    function [7:0] pad_byte;
        input [255:0] k;
        input [7:0]   pos;
        input [7:0]   padv;
        if (pos < 8'd32) pad_byte = k[8*(31-pos) +: 8] ^ padv;
        else pad_byte = padv;
    endfunction

    function [7:0] info_byte;
        input [7:0] kk;
        if (kk < 8'd15) info_byte = INFO_STR[8*(14-kk) +: 8];
        else if (kk < 8'd19) info_byte = spi_i_r[8*(3-(kk-8'd15)) +: 8];
        else info_byte = spi_r_r[8*(3-(kk-8'd19)) +: 8];
    endfunction

    function [7:0] len_w;
        input [2:0] st;
        case (st)
            3'd0: len_w = 8'd200;
            3'd1: len_w = 8'd168;
            3'd2: len_w = 8'd160;
            3'd3: len_w = 8'd168;
            3'd4: len_w = 8'd192;
            3'd5: len_w = 8'd168;
            3'd6: len_w = 8'd192;
            default: len_w = 8'd168;
        endcase
    endfunction

    reg [7:0] wdata_w;
    always @(*) begin
        case (stage)
            3'd0: begin
                if (wpos < 8'd136) wdata_w = pad_byte(h4_r, wpos, 8'h36);
                else if (wpos < 8'd168) wdata_w = ss_i_r[8*(31-(wpos-8'd136)) +: 8];
                else wdata_w = ss_r_r[8*(31-(wpos-8'd168)) +: 8];
            end
            3'd1: begin
                if (wpos < 8'd136) wdata_w = pad_byte(h4_r, wpos, 8'h5c);
                else wdata_w = inner_r[8*(31-(wpos-8'd136)) +: 8];
            end
            3'd2: begin
                if (wpos < 8'd136) wdata_w = pad_byte(prk_r, wpos, 8'h36);
                else if (wpos < 8'd159) wdata_w = info_byte(wpos - 8'd136);
                else wdata_w = 8'h01;
            end
            3'd3: begin
                if (wpos < 8'd136) wdata_w = pad_byte(prk_r, wpos, 8'h5c);
                else wdata_w = td_r[8*(31-(wpos-8'd136)) +: 8];
            end
            3'd4: begin
                if (wpos < 8'd136) wdata_w = pad_byte(prk_r, wpos, 8'h36);
                else if (wpos < 8'd168) wdata_w = t1_r[8*(31-(wpos-8'd136)) +: 8];
                else if (wpos < 8'd191) wdata_w = info_byte(wpos - 8'd168);
                else wdata_w = 8'h02;
            end
            3'd5: begin
                if (wpos < 8'd136) wdata_w = pad_byte(prk_r, wpos, 8'h5c);
                else wdata_w = td_r[8*(31-(wpos-8'd136)) +: 8];
            end
            3'd6: begin
                if (wpos < 8'd136) wdata_w = pad_byte(prk_r, wpos, 8'h36);
                else if (wpos < 8'd168) wdata_w = t2_r[8*(31-(wpos-8'd136)) +: 8];
                else if (wpos < 8'd191) wdata_w = info_byte(wpos - 8'd168);
                else wdata_w = 8'h03;
            end
            default: begin
                if (wpos < 8'd136) wdata_w = pad_byte(prk_r, wpos, 8'h5c);
                else wdata_w = td_r[8*(31-(wpos-8'd136)) +: 8];
            end
        endcase
    end

    assign u_len = {4'd0, len_w(stage)};

    sha3_256 u_hash (
        .clk(clk), .rst_n(rst_n),
        .start(u_start), .len(u_len),
        .msg_wr(u_wr), .msg_waddr({4'd0, u_waddr}), .msg_wdata(u_wdata),
        .busy(), .done(u_done), .error(error), .digest(u_digest),
        .shk_req(shk_req), .shk_cfg(shk_cfg),
        .shk_ready(shk_ready), .shk_done(shk_done),
        .shk_blk_valid(shk_blk_valid), .shk_blk_ready(shk_blk_ready),
        .shk_blk_data(shk_blk_data),
        .shk_out_valid(shk_out_valid), .shk_out_ready(shk_out_ready),
        .shk_out_data(shk_out_data)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            stage <= 3'd0;
            wpos <= 8'd0;
            u_start <= 1'b0;
            u_wr <= 1'b0;
        end else begin
            done <= 1'b0;
            u_start <= 1'b0;
            u_wr <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        h4_r <= h4_in;
                        ss_i_r <= ss_i_in;
                        ss_r_r <= ss_r_in;
                        spi_i_r <= spi_i_in;
                        spi_r_r <= spi_r_in;
                        stage <= 3'd0;
                        wpos <= 8'd0;
                        phase <= PHASE_WR;
                    end
                end
                PHASE_WR: begin
                    u_wr <= 1'b1;
                    u_waddr <= wpos;
                    u_wdata <= wdata_w;
                    if (wpos >= len_w(stage) - 8'd1) begin
                        wpos <= 8'd0;
                        phase <= PHASE_START;
                    end else begin
                        wpos <= wpos + 8'd1;
                    end
                end
                PHASE_START: begin
                    u_start <= 1'b1;
                    phase <= PHASE_RUN;
                end
                PHASE_RUN: begin
                    if (u_done) begin
                        case (stage)
                            3'd0: inner_r <= u_digest;
                            3'd1: prk_r <= u_digest;
                            3'd2: td_r <= u_digest;
                            3'd3: t1_r <= u_digest;
                            3'd4: td_r <= u_digest;
                            3'd5: t2_r <= u_digest;
                            3'd6: td_r <= u_digest;
                            default: t3_r <= u_digest;
                        endcase
                        if (stage == 3'd7) begin
                            phase <= PHASE_DONE;
                        end else begin
                            stage <= stage + 3'd1;
                            phase <= PHASE_WR;
                        end
                    end
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

    genvar og;
    generate
        for (og = 0; og < 32; og = og + 1) begin : okm1
            assign okm[8*(95-og) +: 8] = t1_r[8*(31-og) +: 8];
        end
        for (og = 32; og < 64; og = og + 1) begin : okm2
            assign okm[8*(95-og) +: 8] = t2_r[8*(63-og) +: 8];
        end
        for (og = 64; og < 96; og = og + 1) begin : okm3
            assign okm[8*(95-og) +: 8] = t3_r[8*(95-og) +: 8];
        end
    endgenerate
endmodule
