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
    sbox_combo u_sb_k0 (.x(wm1[31:24]), .y(sb0_c));
    sbox_combo u_sb_k1 (.x(wm1[23:16]), .y(sb1_c));
    sbox_combo u_sb_k2 (.x(wm1[15:8]),  .y(sb2_c));
    sbox_combo u_sb_k3 (.x(wm1[7:0]),   .y(sb3_c));

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

    wire [7:0] mc0  = gmul2(sr0)  ^ gmul3(sr1)  ^ sr2  ^ sr3;
    wire [7:0] mc1  = sr0  ^ gmul2(sr1)  ^ gmul3(sr2)  ^ sr3;
    wire [7:0] mc2  = sr0  ^ sr1  ^ gmul2(sr2)  ^ gmul3(sr3);
    wire [7:0] mc3  = gmul3(sr0)  ^ sr1  ^ sr2  ^ gmul2(sr3);
    wire [7:0] mc4  = gmul2(sr4)  ^ gmul3(sr5)  ^ sr6  ^ sr7;
    wire [7:0] mc5  = sr4  ^ gmul2(sr5)  ^ gmul3(sr6)  ^ sr7;
    wire [7:0] mc6  = sr4  ^ sr5  ^ gmul2(sr6)  ^ gmul3(sr7);
    wire [7:0] mc7  = gmul3(sr4)  ^ sr5  ^ sr6  ^ gmul2(sr7);
    wire [7:0] mc8  = gmul2(sr8)  ^ gmul3(sr9)  ^ sr10 ^ sr11;
    wire [7:0] mc9  = sr8  ^ gmul2(sr9)  ^ gmul3(sr10) ^ sr11;
    wire [7:0] mc10 = sr8  ^ sr9  ^ gmul2(sr10) ^ gmul3(sr11);
    wire [7:0] mc11 = gmul3(sr8)  ^ sr9  ^ sr10 ^ gmul2(sr11);
    wire [7:0] mc12 = gmul2(sr12) ^ gmul3(sr13) ^ sr14 ^ sr15;
    wire [7:0] mc13 = sr12 ^ gmul2(sr13) ^ gmul3(sr14) ^ sr15;
    wire [7:0] mc14 = sr12 ^ sr13 ^ gmul2(sr14) ^ gmul3(sr15);
    wire [7:0] mc15 = gmul3(sr12) ^ sr13 ^ sr14 ^ gmul2(sr15);

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
