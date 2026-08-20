module aes256_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         key_mode,
    input  wire         key_load,
    input  wire         start,
    input  wire [255:0] key,
    input  wire [1919:0] ksch_in,
    input  wire [127:0] block_in,
    output reg          busy,
    output reg          done,
    output wire [127:0] block_out,
    output wire [1919:0] ksch_out
);
    localparam PHASE_IDLE     = 3'd0;
    localparam PHASE_KEYEXP_A = 3'd1;
    localparam PHASE_KEYEXP_B = 3'd2;
    localparam PHASE_CRYPT0   = 3'd3;
    localparam PHASE_CRYPT_B  = 3'd4;

    reg [2:0]  phase;
    reg [3:0]  rke;
    reg [3:0]  rd;
    reg [127:0] state;
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
    reg [127:0] rkey_r;
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

    wire [7:0] a0  = state[127:120];
    wire [7:0] a1  = state[119:112];
    wire [7:0] a2  = state[111:104];
    wire [7:0] a3  = state[103:96];
    wire [7:0] a4  = state[95:88];
    wire [7:0] a5  = state[87:80];
    wire [7:0] a6  = state[79:72];
    wire [7:0] a7  = state[71:64];
    wire [7:0] a8  = state[63:56];
    wire [7:0] a9  = state[55:48];
    wire [7:0] a10 = state[47:40];
    wire [7:0] a11 = state[39:32];
    wire [7:0] a12 = state[31:24];
    wire [7:0] a13 = state[23:16];
    wire [7:0] a14 = state[15:8];
    wire [7:0] a15 = state[7:0];

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

    wire [7:0] mc0;
    wire [7:0] mc1;
    wire [7:0] mc2;
    wire [7:0] mc3;
    wire [7:0] mc4;
    wire [7:0] mc5;
    wire [7:0] mc6;
    wire [7:0] mc7;
    wire [7:0] mc8;
    wire [7:0] mc9;
    wire [7:0] mc10;
    wire [7:0] mc11;
    wire [7:0] mc12;
    wire [7:0] mc13;
    wire [7:0] mc14;
    wire [7:0] mc15;
    assign mc0[0] = sr0[7] ^ sr1[7] ^ sr1[0] ^ sr2[0] ^ sr3[0];
    assign mc0[1] = sr0[0] ^ sr0[7] ^ sr1[0] ^ sr1[7] ^ sr1[1] ^ sr2[1] ^ sr3[1];
    assign mc0[2] = sr0[1] ^ sr1[1] ^ sr1[2] ^ sr2[2] ^ sr3[2];
    assign mc0[3] = sr0[2] ^ sr0[7] ^ sr1[2] ^ sr1[7] ^ sr1[3] ^ sr2[3] ^ sr3[3];
    assign mc0[4] = sr0[3] ^ sr0[7] ^ sr1[3] ^ sr1[7] ^ sr1[4] ^ sr2[4] ^ sr3[4];
    assign mc0[5] = sr0[4] ^ sr1[4] ^ sr1[5] ^ sr2[5] ^ sr3[5];
    assign mc0[6] = sr0[5] ^ sr1[5] ^ sr1[6] ^ sr2[6] ^ sr3[6];
    assign mc0[7] = sr0[6] ^ sr1[6] ^ sr1[7] ^ sr2[7] ^ sr3[7];
    assign mc1[0] = sr0[0] ^ sr1[7] ^ sr2[7] ^ sr2[0] ^ sr3[0];
    assign mc1[1] = sr0[1] ^ sr1[0] ^ sr1[7] ^ sr2[0] ^ sr2[7] ^ sr2[1] ^ sr3[1];
    assign mc1[2] = sr0[2] ^ sr1[1] ^ sr2[1] ^ sr2[2] ^ sr3[2];
    assign mc1[3] = sr0[3] ^ sr1[2] ^ sr1[7] ^ sr2[2] ^ sr2[7] ^ sr2[3] ^ sr3[3];
    assign mc1[4] = sr0[4] ^ sr1[3] ^ sr1[7] ^ sr2[3] ^ sr2[7] ^ sr2[4] ^ sr3[4];
    assign mc1[5] = sr0[5] ^ sr1[4] ^ sr2[4] ^ sr2[5] ^ sr3[5];
    assign mc1[6] = sr0[6] ^ sr1[5] ^ sr2[5] ^ sr2[6] ^ sr3[6];
    assign mc1[7] = sr0[7] ^ sr1[6] ^ sr2[6] ^ sr2[7] ^ sr3[7];
    assign mc2[0] = sr0[0] ^ sr1[0] ^ sr2[7] ^ sr3[7] ^ sr3[0];
    assign mc2[1] = sr0[1] ^ sr1[1] ^ sr2[0] ^ sr2[7] ^ sr3[0] ^ sr3[7] ^ sr3[1];
    assign mc2[2] = sr0[2] ^ sr1[2] ^ sr2[1] ^ sr3[1] ^ sr3[2];
    assign mc2[3] = sr0[3] ^ sr1[3] ^ sr2[2] ^ sr2[7] ^ sr3[2] ^ sr3[7] ^ sr3[3];
    assign mc2[4] = sr0[4] ^ sr1[4] ^ sr2[3] ^ sr2[7] ^ sr3[3] ^ sr3[7] ^ sr3[4];
    assign mc2[5] = sr0[5] ^ sr1[5] ^ sr2[4] ^ sr3[4] ^ sr3[5];
    assign mc2[6] = sr0[6] ^ sr1[6] ^ sr2[5] ^ sr3[5] ^ sr3[6];
    assign mc2[7] = sr0[7] ^ sr1[7] ^ sr2[6] ^ sr3[6] ^ sr3[7];
    assign mc3[0] = sr0[7] ^ sr0[0] ^ sr1[0] ^ sr2[0] ^ sr3[7];
    assign mc3[1] = sr0[0] ^ sr0[7] ^ sr0[1] ^ sr1[1] ^ sr2[1] ^ sr3[0] ^ sr3[7];
    assign mc3[2] = sr0[1] ^ sr0[2] ^ sr1[2] ^ sr2[2] ^ sr3[1];
    assign mc3[3] = sr0[2] ^ sr0[7] ^ sr0[3] ^ sr1[3] ^ sr2[3] ^ sr3[2] ^ sr3[7];
    assign mc3[4] = sr0[3] ^ sr0[7] ^ sr0[4] ^ sr1[4] ^ sr2[4] ^ sr3[3] ^ sr3[7];
    assign mc3[5] = sr0[4] ^ sr0[5] ^ sr1[5] ^ sr2[5] ^ sr3[4];
    assign mc3[6] = sr0[5] ^ sr0[6] ^ sr1[6] ^ sr2[6] ^ sr3[5];
    assign mc3[7] = sr0[6] ^ sr0[7] ^ sr1[7] ^ sr2[7] ^ sr3[6];
    assign mc4[0] = sr4[7] ^ sr5[7] ^ sr5[0] ^ sr6[0] ^ sr7[0];
    assign mc4[1] = sr4[0] ^ sr4[7] ^ sr5[0] ^ sr5[7] ^ sr5[1] ^ sr6[1] ^ sr7[1];
    assign mc4[2] = sr4[1] ^ sr5[1] ^ sr5[2] ^ sr6[2] ^ sr7[2];
    assign mc4[3] = sr4[2] ^ sr4[7] ^ sr5[2] ^ sr5[7] ^ sr5[3] ^ sr6[3] ^ sr7[3];
    assign mc4[4] = sr4[3] ^ sr4[7] ^ sr5[3] ^ sr5[7] ^ sr5[4] ^ sr6[4] ^ sr7[4];
    assign mc4[5] = sr4[4] ^ sr5[4] ^ sr5[5] ^ sr6[5] ^ sr7[5];
    assign mc4[6] = sr4[5] ^ sr5[5] ^ sr5[6] ^ sr6[6] ^ sr7[6];
    assign mc4[7] = sr4[6] ^ sr5[6] ^ sr5[7] ^ sr6[7] ^ sr7[7];
    assign mc5[0] = sr4[0] ^ sr5[7] ^ sr6[7] ^ sr6[0] ^ sr7[0];
    assign mc5[1] = sr4[1] ^ sr5[0] ^ sr5[7] ^ sr6[0] ^ sr6[7] ^ sr6[1] ^ sr7[1];
    assign mc5[2] = sr4[2] ^ sr5[1] ^ sr6[1] ^ sr6[2] ^ sr7[2];
    assign mc5[3] = sr4[3] ^ sr5[2] ^ sr5[7] ^ sr6[2] ^ sr6[7] ^ sr6[3] ^ sr7[3];
    assign mc5[4] = sr4[4] ^ sr5[3] ^ sr5[7] ^ sr6[3] ^ sr6[7] ^ sr6[4] ^ sr7[4];
    assign mc5[5] = sr4[5] ^ sr5[4] ^ sr6[4] ^ sr6[5] ^ sr7[5];
    assign mc5[6] = sr4[6] ^ sr5[5] ^ sr6[5] ^ sr6[6] ^ sr7[6];
    assign mc5[7] = sr4[7] ^ sr5[6] ^ sr6[6] ^ sr6[7] ^ sr7[7];
    assign mc6[0] = sr4[0] ^ sr5[0] ^ sr6[7] ^ sr7[7] ^ sr7[0];
    assign mc6[1] = sr4[1] ^ sr5[1] ^ sr6[0] ^ sr6[7] ^ sr7[0] ^ sr7[7] ^ sr7[1];
    assign mc6[2] = sr4[2] ^ sr5[2] ^ sr6[1] ^ sr7[1] ^ sr7[2];
    assign mc6[3] = sr4[3] ^ sr5[3] ^ sr6[2] ^ sr6[7] ^ sr7[2] ^ sr7[7] ^ sr7[3];
    assign mc6[4] = sr4[4] ^ sr5[4] ^ sr6[3] ^ sr6[7] ^ sr7[3] ^ sr7[7] ^ sr7[4];
    assign mc6[5] = sr4[5] ^ sr5[5] ^ sr6[4] ^ sr7[4] ^ sr7[5];
    assign mc6[6] = sr4[6] ^ sr5[6] ^ sr6[5] ^ sr7[5] ^ sr7[6];
    assign mc6[7] = sr4[7] ^ sr5[7] ^ sr6[6] ^ sr7[6] ^ sr7[7];
    assign mc7[0] = sr4[7] ^ sr4[0] ^ sr5[0] ^ sr6[0] ^ sr7[7];
    assign mc7[1] = sr4[0] ^ sr4[7] ^ sr4[1] ^ sr5[1] ^ sr6[1] ^ sr7[0] ^ sr7[7];
    assign mc7[2] = sr4[1] ^ sr4[2] ^ sr5[2] ^ sr6[2] ^ sr7[1];
    assign mc7[3] = sr4[2] ^ sr4[7] ^ sr4[3] ^ sr5[3] ^ sr6[3] ^ sr7[2] ^ sr7[7];
    assign mc7[4] = sr4[3] ^ sr4[7] ^ sr4[4] ^ sr5[4] ^ sr6[4] ^ sr7[3] ^ sr7[7];
    assign mc7[5] = sr4[4] ^ sr4[5] ^ sr5[5] ^ sr6[5] ^ sr7[4];
    assign mc7[6] = sr4[5] ^ sr4[6] ^ sr5[6] ^ sr6[6] ^ sr7[5];
    assign mc7[7] = sr4[6] ^ sr4[7] ^ sr5[7] ^ sr6[7] ^ sr7[6];
    assign mc8[0] = sr8[7] ^ sr9[7] ^ sr9[0] ^ sr10[0] ^ sr11[0];
    assign mc8[1] = sr8[0] ^ sr8[7] ^ sr9[0] ^ sr9[7] ^ sr9[1] ^ sr10[1] ^ sr11[1];
    assign mc8[2] = sr8[1] ^ sr9[1] ^ sr9[2] ^ sr10[2] ^ sr11[2];
    assign mc8[3] = sr8[2] ^ sr8[7] ^ sr9[2] ^ sr9[7] ^ sr9[3] ^ sr10[3] ^ sr11[3];
    assign mc8[4] = sr8[3] ^ sr8[7] ^ sr9[3] ^ sr9[7] ^ sr9[4] ^ sr10[4] ^ sr11[4];
    assign mc8[5] = sr8[4] ^ sr9[4] ^ sr9[5] ^ sr10[5] ^ sr11[5];
    assign mc8[6] = sr8[5] ^ sr9[5] ^ sr9[6] ^ sr10[6] ^ sr11[6];
    assign mc8[7] = sr8[6] ^ sr9[6] ^ sr9[7] ^ sr10[7] ^ sr11[7];
    assign mc9[0] = sr8[0] ^ sr9[7] ^ sr10[7] ^ sr10[0] ^ sr11[0];
    assign mc9[1] = sr8[1] ^ sr9[0] ^ sr9[7] ^ sr10[0] ^ sr10[7] ^ sr10[1] ^ sr11[1];
    assign mc9[2] = sr8[2] ^ sr9[1] ^ sr10[1] ^ sr10[2] ^ sr11[2];
    assign mc9[3] = sr8[3] ^ sr9[2] ^ sr9[7] ^ sr10[2] ^ sr10[7] ^ sr10[3] ^ sr11[3];
    assign mc9[4] = sr8[4] ^ sr9[3] ^ sr9[7] ^ sr10[3] ^ sr10[7] ^ sr10[4] ^ sr11[4];
    assign mc9[5] = sr8[5] ^ sr9[4] ^ sr10[4] ^ sr10[5] ^ sr11[5];
    assign mc9[6] = sr8[6] ^ sr9[5] ^ sr10[5] ^ sr10[6] ^ sr11[6];
    assign mc9[7] = sr8[7] ^ sr9[6] ^ sr10[6] ^ sr10[7] ^ sr11[7];
    assign mc10[0] = sr8[0] ^ sr9[0] ^ sr10[7] ^ sr11[7] ^ sr11[0];
    assign mc10[1] = sr8[1] ^ sr9[1] ^ sr10[0] ^ sr10[7] ^ sr11[0] ^ sr11[7] ^ sr11[1];
    assign mc10[2] = sr8[2] ^ sr9[2] ^ sr10[1] ^ sr11[1] ^ sr11[2];
    assign mc10[3] = sr8[3] ^ sr9[3] ^ sr10[2] ^ sr10[7] ^ sr11[2] ^ sr11[7] ^ sr11[3];
    assign mc10[4] = sr8[4] ^ sr9[4] ^ sr10[3] ^ sr10[7] ^ sr11[3] ^ sr11[7] ^ sr11[4];
    assign mc10[5] = sr8[5] ^ sr9[5] ^ sr10[4] ^ sr11[4] ^ sr11[5];
    assign mc10[6] = sr8[6] ^ sr9[6] ^ sr10[5] ^ sr11[5] ^ sr11[6];
    assign mc10[7] = sr8[7] ^ sr9[7] ^ sr10[6] ^ sr11[6] ^ sr11[7];
    assign mc11[0] = sr8[7] ^ sr8[0] ^ sr9[0] ^ sr10[0] ^ sr11[7];
    assign mc11[1] = sr8[0] ^ sr8[7] ^ sr8[1] ^ sr9[1] ^ sr10[1] ^ sr11[0] ^ sr11[7];
    assign mc11[2] = sr8[1] ^ sr8[2] ^ sr9[2] ^ sr10[2] ^ sr11[1];
    assign mc11[3] = sr8[2] ^ sr8[7] ^ sr8[3] ^ sr9[3] ^ sr10[3] ^ sr11[2] ^ sr11[7];
    assign mc11[4] = sr8[3] ^ sr8[7] ^ sr8[4] ^ sr9[4] ^ sr10[4] ^ sr11[3] ^ sr11[7];
    assign mc11[5] = sr8[4] ^ sr8[5] ^ sr9[5] ^ sr10[5] ^ sr11[4];
    assign mc11[6] = sr8[5] ^ sr8[6] ^ sr9[6] ^ sr10[6] ^ sr11[5];
    assign mc11[7] = sr8[6] ^ sr8[7] ^ sr9[7] ^ sr10[7] ^ sr11[6];
    assign mc12[0] = sr12[7] ^ sr13[7] ^ sr13[0] ^ sr14[0] ^ sr15[0];
    assign mc12[1] = sr12[0] ^ sr12[7] ^ sr13[0] ^ sr13[7] ^ sr13[1] ^ sr14[1] ^ sr15[1];
    assign mc12[2] = sr12[1] ^ sr13[1] ^ sr13[2] ^ sr14[2] ^ sr15[2];
    assign mc12[3] = sr12[2] ^ sr12[7] ^ sr13[2] ^ sr13[7] ^ sr13[3] ^ sr14[3] ^ sr15[3];
    assign mc12[4] = sr12[3] ^ sr12[7] ^ sr13[3] ^ sr13[7] ^ sr13[4] ^ sr14[4] ^ sr15[4];
    assign mc12[5] = sr12[4] ^ sr13[4] ^ sr13[5] ^ sr14[5] ^ sr15[5];
    assign mc12[6] = sr12[5] ^ sr13[5] ^ sr13[6] ^ sr14[6] ^ sr15[6];
    assign mc12[7] = sr12[6] ^ sr13[6] ^ sr13[7] ^ sr14[7] ^ sr15[7];
    assign mc13[0] = sr12[0] ^ sr13[7] ^ sr14[7] ^ sr14[0] ^ sr15[0];
    assign mc13[1] = sr12[1] ^ sr13[0] ^ sr13[7] ^ sr14[0] ^ sr14[7] ^ sr14[1] ^ sr15[1];
    assign mc13[2] = sr12[2] ^ sr13[1] ^ sr14[1] ^ sr14[2] ^ sr15[2];
    assign mc13[3] = sr12[3] ^ sr13[2] ^ sr13[7] ^ sr14[2] ^ sr14[7] ^ sr14[3] ^ sr15[3];
    assign mc13[4] = sr12[4] ^ sr13[3] ^ sr13[7] ^ sr14[3] ^ sr14[7] ^ sr14[4] ^ sr15[4];
    assign mc13[5] = sr12[5] ^ sr13[4] ^ sr14[4] ^ sr14[5] ^ sr15[5];
    assign mc13[6] = sr12[6] ^ sr13[5] ^ sr14[5] ^ sr14[6] ^ sr15[6];
    assign mc13[7] = sr12[7] ^ sr13[6] ^ sr14[6] ^ sr14[7] ^ sr15[7];
    assign mc14[0] = sr12[0] ^ sr13[0] ^ sr14[7] ^ sr15[7] ^ sr15[0];
    assign mc14[1] = sr12[1] ^ sr13[1] ^ sr14[0] ^ sr14[7] ^ sr15[0] ^ sr15[7] ^ sr15[1];
    assign mc14[2] = sr12[2] ^ sr13[2] ^ sr14[1] ^ sr15[1] ^ sr15[2];
    assign mc14[3] = sr12[3] ^ sr13[3] ^ sr14[2] ^ sr14[7] ^ sr15[2] ^ sr15[7] ^ sr15[3];
    assign mc14[4] = sr12[4] ^ sr13[4] ^ sr14[3] ^ sr14[7] ^ sr15[3] ^ sr15[7] ^ sr15[4];
    assign mc14[5] = sr12[5] ^ sr13[5] ^ sr14[4] ^ sr15[4] ^ sr15[5];
    assign mc14[6] = sr12[6] ^ sr13[6] ^ sr14[5] ^ sr15[5] ^ sr15[6];
    assign mc14[7] = sr12[7] ^ sr13[7] ^ sr14[6] ^ sr15[6] ^ sr15[7];
    assign mc15[0] = sr12[7] ^ sr12[0] ^ sr13[0] ^ sr14[0] ^ sr15[7];
    assign mc15[1] = sr12[0] ^ sr12[7] ^ sr12[1] ^ sr13[1] ^ sr14[1] ^ sr15[0] ^ sr15[7];
    assign mc15[2] = sr12[1] ^ sr12[2] ^ sr13[2] ^ sr14[2] ^ sr15[1];
    assign mc15[3] = sr12[2] ^ sr12[7] ^ sr12[3] ^ sr13[3] ^ sr14[3] ^ sr15[2] ^ sr15[7];
    assign mc15[4] = sr12[3] ^ sr12[7] ^ sr12[4] ^ sr13[4] ^ sr14[4] ^ sr15[3] ^ sr15[7];
    assign mc15[5] = sr12[4] ^ sr12[5] ^ sr13[5] ^ sr14[5] ^ sr15[4];
    assign mc15[6] = sr12[5] ^ sr12[6] ^ sr13[6] ^ sr14[6] ^ sr15[5];
    assign mc15[7] = sr12[6] ^ sr12[7] ^ sr13[7] ^ sr14[7] ^ sr15[6];

    wire [127:0] mid = rd == 4'd14 ? {sr0, sr1, sr2, sr3, sr4, sr5, sr6, sr7,
                                      sr8, sr9, sr10, sr11, sr12, sr13, sr14, sr15}
                                  : {mc0, mc1, mc2, mc3, mc4, mc5, mc6, mc7,
                                     mc8, mc9, mc10, mc11, mc12, mc13, mc14, mc15};
    wire [127:0] state_next = mid ^ rkey_r;

    assign block_out = state;

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
            rd <= 4'd0;
            ax_loaded <= 1'b0;
            st_prev <= 128'd0;
            st_prev2 <= 128'd0;
            rkey_r <= 128'd0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        state <= block_in;
                        busy <= 1'b1;
                        if (key_mode) begin
                            if (key_load || !ax_loaded) begin
                                ksch[0] <= key[255:128];
                                ksch[1] <= key[127:0];
                                st_prev  <= key[127:0];
                                st_prev2 <= key[255:128];
                                rke <= 4'd2;
                                phase <= PHASE_KEYEXP_A;
                            end else begin
                                rke <= 4'd2;
                                state <= block_in ^ ksch[0];
                                rkey_r <= ksch[1];
                                rd <= 4'd1;
                                phase <= PHASE_CRYPT_B;
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
                            rd <= 4'd0;
                            phase <= PHASE_CRYPT0;
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
                        rd <= 4'd0;
                        phase <= PHASE_CRYPT0;
                    end else begin
                        rke <= rke + 4'd1;
                        phase <= PHASE_KEYEXP_A;
                    end
                end
                PHASE_CRYPT0: begin
                    state <= state ^ ksch[0];
                    rkey_r <= ksch[1];
                    rd <= 4'd1;
                    phase <= PHASE_CRYPT_B;
                end
                PHASE_CRYPT_B: begin
                    state <= state_next;
                    if (rd == 4'd14) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        phase <= PHASE_IDLE;
                    end else begin
                        rkey_r <= ksch[rd + 4'd1];
                        rd <= rd + 4'd1;
                    end
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end
endmodule
