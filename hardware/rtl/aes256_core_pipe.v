module aes256_core_pipe (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         key_mode,
    input  wire         key_load,
    input  wire         start,
    input  wire [255:0] key,
    input  wire [1919:0] ksch_in,
    input  wire [127:0] block_in_a,
    input  wire [127:0] block_in_b,
    input  wire         blk_b_valid,
    output reg          busy,
    output reg          done,
    output wire [127:0] block_out_a,
    output wire [127:0] block_out_b,
    output wire [1919:0] ksch_out
);
    localparam PHASE_IDLE     = 3'd0;
    localparam PHASE_KEYEXP_A = 3'd1;
    localparam PHASE_KEYEXP_B = 3'd2;
    localparam PHASE_LOAD     = 3'd3;
    localparam PHASE_CRYPT    = 3'd4;

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
    sbox_combo_cf u_sb_k0 (.x(wm1[31:24]), .y(sb0_c));
    sbox_combo_cf u_sb_k1 (.x(wm1[23:16]), .y(sb1_c));
    sbox_combo_cf u_sb_k2 (.x(wm1[15:8]),  .y(sb2_c));
    sbox_combo_cf u_sb_k3 (.x(wm1[7:0]),   .y(sb3_c));

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

    reg [127:0] state_a;
    reg [127:0] state_b;
    reg [127:0] blk_q_a;
    reg [127:0] blk_q_b;
    reg         bv_q;
    reg [127:0] sr_pipe_a;
    reg [127:0] sr_pipe_b;
    reg         sr_valid_a;
    reg         sr_valid_b;
    reg [3:0]   rd_a;
    reg [3:0]   rd_b;
    reg         blk_sel;
    reg [127:0] out_a_r;
    reg [127:0] out_b_r;
    reg         done_a;
    reg         done_b;

    wire [7:0] a0  = blk_sel ? state_b[127:120] : state_a[127:120];
    wire [7:0] a1  = blk_sel ? state_b[119:112] : state_a[119:112];
    wire [7:0] a2  = blk_sel ? state_b[111:104] : state_a[111:104];
    wire [7:0] a3  = blk_sel ? state_b[103:96]  : state_a[103:96];
    wire [7:0] a4  = blk_sel ? state_b[95:88]   : state_a[95:88];
    wire [7:0] a5  = blk_sel ? state_b[87:80]   : state_a[87:80];
    wire [7:0] a6  = blk_sel ? state_b[79:72]   : state_a[79:72];
    wire [7:0] a7  = blk_sel ? state_b[71:64]   : state_a[71:64];
    wire [7:0] a8  = blk_sel ? state_b[63:56]   : state_a[63:56];
    wire [7:0] a9  = blk_sel ? state_b[55:48]   : state_a[55:48];
    wire [7:0] a10 = blk_sel ? state_b[47:40]   : state_a[47:40];
    wire [7:0] a11 = blk_sel ? state_b[39:32]   : state_a[39:32];
    wire [7:0] a12 = blk_sel ? state_b[31:24]   : state_a[31:24];
    wire [7:0] a13 = blk_sel ? state_b[23:16]   : state_a[23:16];
    wire [7:0] a14 = blk_sel ? state_b[15:8]    : state_a[15:8];
    wire [7:0] a15 = blk_sel ? state_b[7:0]     : state_a[7:0];

    wire [7:0] sr0, sr1, sr2, sr3, sr4, sr5, sr6, sr7;
    wire [7:0] sr8, sr9, sr10, sr11, sr12, sr13, sr14, sr15;
    sbox_combo u_sb_r0  (.x(a0),  .y(sr0));
    sbox_combo u_sb_r1  (.x(a5),  .y(sr1));
    sbox_combo u_sb_r2  (.x(a10), .y(sr2));
    sbox_combo u_sb_r3  (.x(a15), .y(sr3));
    sbox_combo u_sb_r4  (.x(a4),  .y(sr4));
    sbox_combo u_sb_r5  (.x(a9),  .y(sr5));
    sbox_combo u_sb_r6  (.x(a14), .y(sr6));
    sbox_combo u_sb_r7  (.x(a3),  .y(sr7));
    sbox_combo u_sb_r8  (.x(a8),  .y(sr8));
    sbox_combo u_sb_r9  (.x(a13), .y(sr9));
    sbox_combo u_sb_r10 (.x(a2),  .y(sr10));
    sbox_combo u_sb_r11 (.x(a7),  .y(sr11));
    sbox_combo u_sb_r12 (.x(a12), .y(sr12));
    sbox_combo u_sb_r13 (.x(a1),  .y(sr13));
    sbox_combo u_sb_r14 (.x(a6),  .y(sr14));
    sbox_combo u_sb_r15 (.x(a11), .y(sr15));

    wire [127:0] sr_comb = {sr0, sr1, sr2, sr3, sr4, sr5, sr6, sr7,
                            sr8, sr9, sr10, sr11, sr12, sr13, sr14, sr15};

    wire [7:0] m0  = blk_sel ? sr_pipe_a[127:120] : sr_pipe_b[127:120];
    wire [7:0] m1  = blk_sel ? sr_pipe_a[119:112] : sr_pipe_b[119:112];
    wire [7:0] m2  = blk_sel ? sr_pipe_a[111:104] : sr_pipe_b[111:104];
    wire [7:0] m3  = blk_sel ? sr_pipe_a[103:96]  : sr_pipe_b[103:96];
    wire [7:0] m4  = blk_sel ? sr_pipe_a[95:88]   : sr_pipe_b[95:88];
    wire [7:0] m5  = blk_sel ? sr_pipe_a[87:80]   : sr_pipe_b[87:80];
    wire [7:0] m6  = blk_sel ? sr_pipe_a[79:72]   : sr_pipe_b[79:72];
    wire [7:0] m7  = blk_sel ? sr_pipe_a[71:64]   : sr_pipe_b[71:64];
    wire [7:0] m8  = blk_sel ? sr_pipe_a[63:56]   : sr_pipe_b[63:56];
    wire [7:0] m9  = blk_sel ? sr_pipe_a[55:48]   : sr_pipe_b[55:48];
    wire [7:0] m10 = blk_sel ? sr_pipe_a[47:40]   : sr_pipe_b[47:40];
    wire [7:0] m11 = blk_sel ? sr_pipe_a[39:32]   : sr_pipe_b[39:32];
    wire [7:0] m12 = blk_sel ? sr_pipe_a[31:24]   : sr_pipe_b[31:24];
    wire [7:0] m13 = blk_sel ? sr_pipe_a[23:16]   : sr_pipe_b[23:16];
    wire [7:0] m14 = blk_sel ? sr_pipe_a[15:8]    : sr_pipe_b[15:8];
    wire [7:0] m15 = blk_sel ? sr_pipe_a[7:0]     : sr_pipe_b[7:0];

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

    wire [3:0] rd_mc = blk_sel ? rd_a : rd_b;
    wire [127:0] mc_in = blk_sel ? sr_pipe_a : sr_pipe_b;
    wire         mc_ok = blk_sel ? sr_valid_a : sr_valid_b;
    wire [127:0] mid = (rd_mc == 4'd14) ? mc_in : mc_comb;
    wire [127:0] state_next = mid ^ ksch[rd_mc];

    assign block_out_a = out_a_r;
    assign block_out_b = out_b_r;
    genvar ko;
    generate
        for (ko = 0; ko < 15; ko = ko + 1) begin : kout
            assign ksch_out[128*ko +: 128] = ksch[ko];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            rke <= 4'd0;
            ax_loaded <= 1'b0;
            st_prev <= 128'd0;
            st_prev2 <= 128'd0;
            state_a <= 128'd0;
            state_b <= 128'd0;
            sr_pipe_a <= 128'd0;
            sr_pipe_b <= 128'd0;
            sr_valid_a <= 1'b0;
            sr_valid_b <= 1'b0;
            rd_a <= 4'd0;
            rd_b <= 4'd0;
            blk_sel <= 1'b0;
            out_a_r <= 128'd0;
            out_b_r <= 128'd0;
            done_a <= 1'b0;
            done_b <= 1'b0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        done_a <= 1'b0;
                        done_b <= 1'b0;
                        blk_q_a <= block_in_a;
                        blk_q_b <= block_in_b;
                        bv_q <= blk_b_valid;
                        if (key_mode) begin
                            if (key_load || !ax_loaded) begin
                                ksch[0] <= key[255:128];
                                ksch[1] <= key[127:0];
                                st_prev  <= key[127:0];
                                st_prev2 <= key[255:128];
                                rke <= 4'd2;
                                phase <= PHASE_KEYEXP_A;
                            end else begin
                                phase <= PHASE_LOAD;
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
                            phase <= PHASE_LOAD;
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
                        phase <= PHASE_LOAD;
                    end else begin
                        rke <= rke + 4'd1;
                        phase <= PHASE_KEYEXP_A;
                    end
                end
                PHASE_LOAD: begin
                    sr_valid_a <= 1'b0;
                    sr_valid_b <= 1'b0;
                    done_a <= 1'b0;
                    done_b <= 1'b0;
                    state_a <= blk_q_a ^ ksch[0];
                    state_b <= blk_q_b ^ ksch[0];
                    rd_a <= 4'd1;
                    rd_b <= 4'd1;
                    blk_sel <= 1'b0;
                    phase <= PHASE_CRYPT;
                end
                PHASE_CRYPT: begin
                    if (blk_sel) begin
                        sr_pipe_b <= sr_comb;
                        sr_valid_b <= 1'b1;
                        if (mc_ok) begin
                            if (rd_a == 4'd14) begin
                                state_a <= state_next;                                out_a_r <= state_next;
                                done_a <= 1'b1;
                                rd_a <= 4'd0;
                                if (!bv_q) begin
                                    done <= 1'b1;
                                    busy <= 1'b0;
                                    phase <= PHASE_IDLE;
                                end
                            end else begin
                                state_a <= state_next;
                                rd_a <= rd_a + 4'd1;
                            end
                        end
                    end else begin
                        sr_pipe_a <= sr_comb;
                        sr_valid_a <= 1'b1;
                        if (mc_ok) begin
                            if (rd_b == 4'd14) begin
                                state_b <= state_next;
                                out_b_r <= state_next;
                                done_b <= 1'b1;
                                rd_b <= 4'd0;
                                if (bv_q) begin
                                    done <= 1'b1;
                                    busy <= 1'b0;
                                    phase <= PHASE_IDLE;
                                end
                            end else begin
                                state_b <= state_next;
                                rd_b <= rd_b + 4'd1;
                            end
                        end
                    end
                    blk_sel <= ~blk_sel;
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end

endmodule
