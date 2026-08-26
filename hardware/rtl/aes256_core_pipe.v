module aes256_core_pipe (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         key_mode,
    input  wire         key_load,
    input  wire         start,
    input  wire [255:0] key,
    input  wire [1919:0] ksch_in,
    input  wire [127:0] block_in,
    input  wire         blk_valid,
    output wire         busy,
    output wire         crypt_rdy,
    output wire         load_rdy,
    output reg          done,
    output reg  [127:0] block_out,
    output wire [1919:0] ksch_out
);
    localparam PHASE_IDLE     = 3'd0;
    localparam PHASE_KEYEXP_A = 3'd1;
    localparam PHASE_KEYEXP_B = 3'd2;
    localparam PHASE_CRYPT    = 3'd3;

    reg [2:0]  phase;
    reg [3:0]  rke;
    reg [127:0] ksch [0:14];
    reg ax_loaded;

    function [7:0] gmul2(input [7:0] x);
        gmul2 = {x[6:0], 1'b0} ^ (x[7] ? 8'h1b : 8'h00);
    endfunction

    function [7:0] gmul3(input [7:0] x);
        gmul3 = gmul2(x) ^ x;
    endfunction

    reg [127:0] st_prev;
    reg [127:0] st_prev2;
    wire [31:0] wm1 = st_prev[31:0];
    wire [31:0] w8  = st_prev2[127:96];
    wire [7:0]  rcon = rke[0] ? 8'h00 :
                       (rke >> 1) == 4'd1 ? 8'h01 :
                       (rke >> 1) == 4'd2 ? 8'h02 :
                       (rke >> 1) == 4'd3 ? 8'h04 :
                       (rke >> 1) == 4'd4 ? 8'h08 :
                       (rke >> 1) == 4'd5 ? 8'h10 :
                       (rke >> 1) == 4'd6 ? 8'h20 : 8'h40;

    wire [7:0] sb0_c, sb1_c, sb2_c, sb3_c;
    sbox_combo_cf_lut u_sb_k0 (.clk(clk), .x(wm1[31:24]), .y(sb0_c));
    sbox_combo_cf_lut u_sb_k1 (.clk(clk), .x(wm1[23:16]), .y(sb1_c));
    sbox_combo_cf_lut u_sb_k2 (.clk(clk), .x(wm1[15:8]),  .y(sb2_c));
    sbox_combo_cf_lut u_sb_k3 (.clk(clk), .x(wm1[7:0]),   .y(sb3_c));

    reg [7:0] sb0_r, sb1_r, sb2_r, sb3_r;
    always @(posedge clk) begin
        sb0_r <= sb0_c;
        sb1_r <= sb1_c;
        sb2_r <= sb2_c;
        sb3_r <= sb3_c;
    end

    wire [31:0] temp = rke[0]
        ? {sb0_r, sb1_r, sb2_r, sb3_r}
        : {sb1_r, sb2_r, sb3_r, sb0_r} ^ {rcon, 24'd0};
    wire [31:0] we0 = w8 ^ temp;
    wire [31:0] we1 = st_prev2[95:64] ^ we0;
    wire [31:0] we2 = st_prev2[63:32] ^ we1;
    wire [31:0] we3 = st_prev2[31:0] ^ we2;

    reg [127:0] state [0:3];
    reg [127:0] sr_r  [0:3];
    reg [3:0]   rd    [0:3];
    reg [1:0]   blk_sel;
    reg [1:0]   blk_sel_d;
    reg [1:0]   blk_sel_dd;
    reg [127:0] out_r;

    wire [1:0] b2 = (blk_sel == 2'd3) ? 2'd0 : blk_sel + 2'd1;
    wire [1:0] b1_dd = (blk_sel_dd == 2'd0) ? 2'd3 : blk_sel_dd - 2'd1;

    wire [127:0] sbox_c;
    wire [127:0] sr_in = {state[blk_sel][127:120], state[blk_sel][87:80], state[blk_sel][47:40], state[blk_sel][7:0],
                          state[blk_sel][95:88], state[blk_sel][55:48], state[blk_sel][15:8], state[blk_sel][103:96],
                          state[blk_sel][63:56], state[blk_sel][23:16], state[blk_sel][111:104], state[blk_sel][71:64],
                          state[blk_sel][31:24], state[blk_sel][119:112], state[blk_sel][79:72], state[blk_sel][39:32]};
    sb_sbox16 u_sb (.clk(clk), .x(sr_in), .y(sbox_c));

    wire [7:0] m0  = sr_r[b1_dd][127:120];
    wire [7:0] m1  = sr_r[b1_dd][119:112];
    wire [7:0] m2  = sr_r[b1_dd][111:104];
    wire [7:0] m3  = sr_r[b1_dd][103:96];
    wire [7:0] m4  = sr_r[b1_dd][95:88];
    wire [7:0] m5  = sr_r[b1_dd][87:80];
    wire [7:0] m6  = sr_r[b1_dd][79:72];
    wire [7:0] m7  = sr_r[b1_dd][71:64];
    wire [7:0] m8  = sr_r[b1_dd][63:56];
    wire [7:0] m9  = sr_r[b1_dd][55:48];
    wire [7:0] m10 = sr_r[b1_dd][47:40];
    wire [7:0] m11 = sr_r[b1_dd][39:32];
    wire [7:0] m12 = sr_r[b1_dd][31:24];
    wire [7:0] m13 = sr_r[b1_dd][23:16];
    wire [7:0] m14 = sr_r[b1_dd][15:8];
    wire [7:0] m15 = sr_r[b1_dd][7:0];

    wire [7:0] mc_col0[3:0];
    wire [7:0] mc_col1[3:0];
    wire [7:0] mc_col2[3:0];
    wire [7:0] mc_col3[3:0];
    assign mc_col0[0] = gmul2(m0)  ^ gmul3(m1)  ^ m2  ^ m3;
    assign mc_col0[1] = m0  ^ gmul2(m1)  ^ gmul3(m2)  ^ m3;
    assign mc_col0[2] = m0  ^ m1  ^ gmul2(m2)  ^ gmul3(m3);
    assign mc_col0[3] = gmul3(m0)  ^ m1  ^ m2  ^ gmul2(m3);
    assign mc_col1[0] = gmul2(m4)  ^ gmul3(m5)  ^ m6  ^ m7;
    assign mc_col1[1] = m4  ^ gmul2(m5)  ^ gmul3(m6)  ^ m7;
    assign mc_col1[2] = m4  ^ m5  ^ gmul2(m6)  ^ gmul3(m7);
    assign mc_col1[3] = gmul3(m4)  ^ m5  ^ m6  ^ gmul2(m7);
    assign mc_col2[0] = gmul2(m8)  ^ gmul3(m9)  ^ m10 ^ m11;
    assign mc_col2[1] = m8  ^ gmul2(m9)  ^ gmul3(m10) ^ m11;
    assign mc_col2[2] = m8  ^ m9  ^ gmul2(m10) ^ gmul3(m11);
    assign mc_col2[3] = gmul3(m8)  ^ m9  ^ m10 ^ gmul2(m11);
    assign mc_col3[0] = gmul2(m12) ^ gmul3(m13) ^ m14 ^ m15;
    assign mc_col3[1] = m12 ^ gmul2(m13) ^ gmul3(m14) ^ m15;
    assign mc_col3[2] = m12 ^ m13 ^ gmul2(m14) ^ gmul3(m15);
    assign mc_col3[3] = gmul3(m12) ^ m13 ^ m14 ^ gmul2(m15);

    wire [127:0] mc_comb = {mc_col0[0], mc_col0[1], mc_col0[2], mc_col0[3],
                            mc_col1[0], mc_col1[1], mc_col1[2], mc_col1[3],
                            mc_col2[0], mc_col2[1], mc_col2[2], mc_col2[3],
                            mc_col3[0], mc_col3[1], mc_col3[2], mc_col3[3]};

    wire [127:0] mid_cmb = (rd[b1_dd] == 4'd14) ? sr_r[b1_dd] : mc_comb;
    reg [127:0] rk;
    always @(*) begin
        case (rd[b1_dd])
            4'd0:  rk = ksch[0];
            4'd1:  rk = ksch[1];
            4'd2:  rk = ksch[2];
            4'd3:  rk = ksch[3];
            4'd4:  rk = ksch[4];
            4'd5:  rk = ksch[5];
            4'd6:  rk = ksch[6];
            4'd7:  rk = ksch[7];
            4'd8:  rk = ksch[8];
            4'd9:  rk = ksch[9];
            4'd10: rk = ksch[10];
            4'd11: rk = ksch[11];
            4'd12: rk = ksch[12];
            4'd13: rk = ksch[13];
            4'd14: rk = ksch[14];
            default: rk = ksch[0];
        endcase
    end
    wire [127:0] state_next = mid_cmb ^ rk;
    wire [127:0] block_out_comb = (rd[b1_dd] == 4'd14) ? state_next : out_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            block_out <= 128'd0;
        end else begin
            block_out <= block_out_comb;
        end
    end

    genvar ko;
    generate
        for (ko = 0; ko < 15; ko = ko + 1) begin : kout
            assign ksch_out[128*ko +: 128] = ksch[ko];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            rke <= 4'd0;
            ax_loaded <= 1'b0;
            st_prev <= 128'd0;
            st_prev2 <= 128'd0;
            state[0] <= 128'd0; state[1] <= 128'd0; state[2] <= 128'd0; state[3] <= 128'd0;
            sr_r[0] <= 128'd0; sr_r[1] <= 128'd0; sr_r[2] <= 128'd0; sr_r[3] <= 128'd0;
            rd[0] <= 4'd0; rd[1] <= 4'd0; rd[2] <= 4'd0; rd[3] <= 4'd0;
            blk_sel <= 2'd0;
            blk_sel_d <= 2'd0;
            blk_sel_dd <= 2'd0;
            out_r <= 128'd0;
        end else begin
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        if (key_mode) begin
                            if (key_load || !ax_loaded) begin
                                ksch[0] <= key[255:128];
                                ksch[1] <= key[127:0];
                                st_prev  <= key[127:0];
                                st_prev2 <= key[255:128];
                                rke <= 4'd2;
                                phase <= PHASE_KEYEXP_A;
                            end else begin
                                phase <= PHASE_CRYPT;
                            end
                        end else begin
                            ksch[0] <= ksch_in[127:0];
                            ksch[1] <= ksch_in[255:128];
                            ksch[2] <= ksch_in[383:256];
                            ksch[3] <= ksch_in[511:384];
                            ksch[4] <= ksch_in[639:512];
                            ksch[5] <= ksch_in[767:640];
                            ksch[6] <= ksch_in[895:768];
                            ksch[7] <= ksch_in[1023:896];
                            ksch[8] <= ksch_in[1151:1024];
                            ksch[9] <= ksch_in[1279:1152];
                            ksch[10] <= ksch_in[1407:1280];
                            ksch[11] <= ksch_in[1535:1408];
                            ksch[12] <= ksch_in[1663:1536];
                            ksch[13] <= ksch_in[1791:1664];
                            ksch[14] <= ksch_in[1919:1792];
                            ax_loaded <= 1'b1;
                            phase <= PHASE_CRYPT;
                        end
                    end
                end
                PHASE_KEYEXP_A: begin
                    phase <= PHASE_KEYEXP_B;
                end
                PHASE_KEYEXP_B: begin
                    ksch[rke] <= {we0, we1, we2, we3};
                    st_prev2 <= st_prev;
                    st_prev  <= {we0, we1, we2, we3};
                    if (rke == 4'd14) begin
                        ax_loaded <= 1'b1;
                        phase <= PHASE_CRYPT;
                    end else begin
                        rke <= rke + 4'd1;
                        phase <= PHASE_KEYEXP_A;
                    end
                end
                PHASE_CRYPT: begin
                    if (blk_valid && (rd[b2] == 4'd0)) begin
                        state[b2] <= block_in ^ ksch[0];
                        rd[b2] <= 4'd1;
                    end
                    sr_r[blk_sel_dd] <= sbox_c;
                    if (rd[b1_dd] == 4'd14) begin
                        state[b1_dd] <= state_next;
                        out_r <= state_next;
                        if (blk_valid && (rd[b2] == 4'd1)) begin
                            rd[b1_dd] <= 4'd1;
                            state[b1_dd] <= block_in ^ ksch[0];
                        end else begin
                            rd[b1_dd] <= 4'd0;
                        end
                    end else if (rd[b1_dd] != 4'd0) begin
                        state[b1_dd] <= state_next;
                        rd[b1_dd] <= rd[b1_dd] + 4'd1;
                    end
                    blk_sel_d <= blk_sel;
                    blk_sel_dd <= blk_sel_d;
                    blk_sel <= (blk_sel == 2'd3) ? 2'd0 : blk_sel + 2'd1;
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end

    assign busy = (rd[0] != 4'd0) && (rd[1] != 4'd0) && (rd[2] != 4'd0) && (rd[3] != 4'd0);
    assign crypt_rdy = (phase == PHASE_CRYPT) && !busy;
    assign load_rdy = (phase == PHASE_CRYPT) && (rd[b2] == 4'd0);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done <= 1'b0;
        end else begin
            done <= (rd[b1_dd] == 4'd14);
        end
    end

endmodule
