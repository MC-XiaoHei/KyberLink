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

    reg [7:0] sbox_mem [0:255];
    integer si;
    initial begin
        for (si = 0; si < 256; si = si + 1) sbox_mem[si] = 8'h00;
        sbox_mem[8'h00] = 8'h63; sbox_mem[8'h01] = 8'h7c; sbox_mem[8'h02] = 8'h77; sbox_mem[8'h03] = 8'h7b;
        sbox_mem[8'h04] = 8'hf2; sbox_mem[8'h05] = 8'h6b; sbox_mem[8'h06] = 8'h6f; sbox_mem[8'h07] = 8'hc5;
        sbox_mem[8'h08] = 8'h30; sbox_mem[8'h09] = 8'h01; sbox_mem[8'h0a] = 8'h67; sbox_mem[8'h0b] = 8'h2b;
        sbox_mem[8'h0c] = 8'hfe; sbox_mem[8'h0d] = 8'hd7; sbox_mem[8'h0e] = 8'hab; sbox_mem[8'h0f] = 8'h76;
        sbox_mem[8'h10] = 8'hca; sbox_mem[8'h11] = 8'h82; sbox_mem[8'h12] = 8'hc9; sbox_mem[8'h13] = 8'h7d;
        sbox_mem[8'h14] = 8'hfa; sbox_mem[8'h15] = 8'h59; sbox_mem[8'h16] = 8'h47; sbox_mem[8'h17] = 8'hf0;
        sbox_mem[8'h18] = 8'had; sbox_mem[8'h19] = 8'hd4; sbox_mem[8'h1a] = 8'ha2; sbox_mem[8'h1b] = 8'haf;
        sbox_mem[8'h1c] = 8'h9c; sbox_mem[8'h1d] = 8'ha4; sbox_mem[8'h1e] = 8'h72; sbox_mem[8'h1f] = 8'hc0;
        sbox_mem[8'h20] = 8'hb7; sbox_mem[8'h21] = 8'hfd; sbox_mem[8'h22] = 8'h93; sbox_mem[8'h23] = 8'h26;
        sbox_mem[8'h24] = 8'h36; sbox_mem[8'h25] = 8'h3f; sbox_mem[8'h26] = 8'hf7; sbox_mem[8'h27] = 8'hcc;
        sbox_mem[8'h28] = 8'h34; sbox_mem[8'h29] = 8'ha5; sbox_mem[8'h2a] = 8'he5; sbox_mem[8'h2b] = 8'hf1;
        sbox_mem[8'h2c] = 8'h71; sbox_mem[8'h2d] = 8'hd8; sbox_mem[8'h2e] = 8'h31; sbox_mem[8'h2f] = 8'h15;
        sbox_mem[8'h30] = 8'h04; sbox_mem[8'h31] = 8'hc7; sbox_mem[8'h32] = 8'h23; sbox_mem[8'h33] = 8'hc3;
        sbox_mem[8'h34] = 8'h18; sbox_mem[8'h35] = 8'h96; sbox_mem[8'h36] = 8'h05; sbox_mem[8'h37] = 8'h9a;
        sbox_mem[8'h38] = 8'h07; sbox_mem[8'h39] = 8'h12; sbox_mem[8'h3a] = 8'h80; sbox_mem[8'h3b] = 8'he2;
        sbox_mem[8'h3c] = 8'heb; sbox_mem[8'h3d] = 8'h27; sbox_mem[8'h3e] = 8'hb2; sbox_mem[8'h3f] = 8'h75;
        sbox_mem[8'h40] = 8'h09; sbox_mem[8'h41] = 8'h83; sbox_mem[8'h42] = 8'h2c; sbox_mem[8'h43] = 8'h1a;
        sbox_mem[8'h44] = 8'h1b; sbox_mem[8'h45] = 8'h6e; sbox_mem[8'h46] = 8'h5a; sbox_mem[8'h47] = 8'ha0;
        sbox_mem[8'h48] = 8'h52; sbox_mem[8'h49] = 8'h3b; sbox_mem[8'h4a] = 8'hd6; sbox_mem[8'h4b] = 8'hb3;
        sbox_mem[8'h4c] = 8'h29; sbox_mem[8'h4d] = 8'he3; sbox_mem[8'h4e] = 8'h2f; sbox_mem[8'h4f] = 8'h84;
        sbox_mem[8'h50] = 8'h53; sbox_mem[8'h51] = 8'hd1; sbox_mem[8'h52] = 8'h00; sbox_mem[8'h53] = 8'hed;
        sbox_mem[8'h54] = 8'h20; sbox_mem[8'h55] = 8'hfc; sbox_mem[8'h56] = 8'hb1; sbox_mem[8'h57] = 8'h5b;
        sbox_mem[8'h58] = 8'h6a; sbox_mem[8'h59] = 8'hcb; sbox_mem[8'h5a] = 8'hbe; sbox_mem[8'h5b] = 8'h39;
        sbox_mem[8'h5c] = 8'h4a; sbox_mem[8'h5d] = 8'h4c; sbox_mem[8'h5e] = 8'h58; sbox_mem[8'h5f] = 8'hcf;
        sbox_mem[8'h60] = 8'hd0; sbox_mem[8'h61] = 8'hef; sbox_mem[8'h62] = 8'haa; sbox_mem[8'h63] = 8'hfb;
        sbox_mem[8'h64] = 8'h43; sbox_mem[8'h65] = 8'h4d; sbox_mem[8'h66] = 8'h33; sbox_mem[8'h67] = 8'h85;
        sbox_mem[8'h68] = 8'h45; sbox_mem[8'h69] = 8'hf9; sbox_mem[8'h6a] = 8'h02; sbox_mem[8'h6b] = 8'h7f;
        sbox_mem[8'h6c] = 8'h50; sbox_mem[8'h6d] = 8'h3c; sbox_mem[8'h6e] = 8'h9f; sbox_mem[8'h6f] = 8'ha8;
        sbox_mem[8'h70] = 8'h51; sbox_mem[8'h71] = 8'ha3; sbox_mem[8'h72] = 8'h40; sbox_mem[8'h73] = 8'h8f;
        sbox_mem[8'h74] = 8'h92; sbox_mem[8'h75] = 8'h9d; sbox_mem[8'h76] = 8'h38; sbox_mem[8'h77] = 8'hf5;
        sbox_mem[8'h78] = 8'hbc; sbox_mem[8'h79] = 8'hb6; sbox_mem[8'h7a] = 8'hda; sbox_mem[8'h7b] = 8'h21;
        sbox_mem[8'h7c] = 8'h10; sbox_mem[8'h7d] = 8'hff; sbox_mem[8'h7e] = 8'hf3; sbox_mem[8'h7f] = 8'hd2;
        sbox_mem[8'h80] = 8'hcd; sbox_mem[8'h81] = 8'h0c; sbox_mem[8'h82] = 8'h13; sbox_mem[8'h83] = 8'hec;
        sbox_mem[8'h84] = 8'h5f; sbox_mem[8'h85] = 8'h97; sbox_mem[8'h86] = 8'h44; sbox_mem[8'h87] = 8'h17;
        sbox_mem[8'h88] = 8'hc4; sbox_mem[8'h89] = 8'ha7; sbox_mem[8'h8a] = 8'h7e; sbox_mem[8'h8b] = 8'h3d;
        sbox_mem[8'h8c] = 8'h64; sbox_mem[8'h8d] = 8'h5d; sbox_mem[8'h8e] = 8'h19; sbox_mem[8'h8f] = 8'h73;
        sbox_mem[8'h90] = 8'h60; sbox_mem[8'h91] = 8'h81; sbox_mem[8'h92] = 8'h4f; sbox_mem[8'h93] = 8'hdc;
        sbox_mem[8'h94] = 8'h22; sbox_mem[8'h95] = 8'h2a; sbox_mem[8'h96] = 8'h90; sbox_mem[8'h97] = 8'h88;
        sbox_mem[8'h98] = 8'h46; sbox_mem[8'h99] = 8'hee; sbox_mem[8'h9a] = 8'hb8; sbox_mem[8'h9b] = 8'h14;
        sbox_mem[8'h9c] = 8'hde; sbox_mem[8'h9d] = 8'h5e; sbox_mem[8'h9e] = 8'h0b; sbox_mem[8'h9f] = 8'hdb;
        sbox_mem[8'ha0] = 8'he0; sbox_mem[8'ha1] = 8'h32; sbox_mem[8'ha2] = 8'h3a; sbox_mem[8'ha3] = 8'h0a;
        sbox_mem[8'ha4] = 8'h49; sbox_mem[8'ha5] = 8'h06; sbox_mem[8'ha6] = 8'h24; sbox_mem[8'ha7] = 8'h5c;
        sbox_mem[8'ha8] = 8'hc2; sbox_mem[8'ha9] = 8'hd3; sbox_mem[8'haa] = 8'hac; sbox_mem[8'hab] = 8'h62;
        sbox_mem[8'hac] = 8'h91; sbox_mem[8'had] = 8'h95; sbox_mem[8'hae] = 8'he4; sbox_mem[8'haf] = 8'h79;
        sbox_mem[8'hb0] = 8'he7; sbox_mem[8'hb1] = 8'hc8; sbox_mem[8'hb2] = 8'h37; sbox_mem[8'hb3] = 8'h6d;
        sbox_mem[8'hb4] = 8'h8d; sbox_mem[8'hb5] = 8'hd5; sbox_mem[8'hb6] = 8'h4e; sbox_mem[8'hb7] = 8'ha9;
        sbox_mem[8'hb8] = 8'h6c; sbox_mem[8'hb9] = 8'h56; sbox_mem[8'hba] = 8'hf4; sbox_mem[8'hbb] = 8'hea;
        sbox_mem[8'hbc] = 8'h65; sbox_mem[8'hbd] = 8'h7a; sbox_mem[8'hbe] = 8'hae; sbox_mem[8'hbf] = 8'h08;
        sbox_mem[8'hc0] = 8'hba; sbox_mem[8'hc1] = 8'h78; sbox_mem[8'hc2] = 8'h25; sbox_mem[8'hc3] = 8'h2e;
        sbox_mem[8'hc4] = 8'h1c; sbox_mem[8'hc5] = 8'ha6; sbox_mem[8'hc6] = 8'hb4; sbox_mem[8'hc7] = 8'hc6;
        sbox_mem[8'hc8] = 8'he8; sbox_mem[8'hc9] = 8'hdd; sbox_mem[8'hca] = 8'h74; sbox_mem[8'hcb] = 8'h1f;
        sbox_mem[8'hcc] = 8'h4b; sbox_mem[8'hcd] = 8'hbd; sbox_mem[8'hce] = 8'h8b; sbox_mem[8'hcf] = 8'h8a;
        sbox_mem[8'hd0] = 8'h70; sbox_mem[8'hd1] = 8'h3e; sbox_mem[8'hd2] = 8'hb5; sbox_mem[8'hd3] = 8'h66;
        sbox_mem[8'hd4] = 8'h48; sbox_mem[8'hd5] = 8'h03; sbox_mem[8'hd6] = 8'hf6; sbox_mem[8'hd7] = 8'h0e;
        sbox_mem[8'hd8] = 8'h61; sbox_mem[8'hd9] = 8'h35; sbox_mem[8'hda] = 8'h57; sbox_mem[8'hdb] = 8'hb9;
        sbox_mem[8'hdc] = 8'h86; sbox_mem[8'hdd] = 8'hc1; sbox_mem[8'hde] = 8'h1d; sbox_mem[8'hdf] = 8'h9e;
        sbox_mem[8'he0] = 8'he1; sbox_mem[8'he1] = 8'hf8; sbox_mem[8'he2] = 8'h98; sbox_mem[8'he3] = 8'h11;
        sbox_mem[8'he4] = 8'h69; sbox_mem[8'he5] = 8'hd9; sbox_mem[8'he6] = 8'h8e; sbox_mem[8'he7] = 8'h94;
        sbox_mem[8'he8] = 8'h9b; sbox_mem[8'he9] = 8'h1e; sbox_mem[8'hea] = 8'h87; sbox_mem[8'heb] = 8'he9;
        sbox_mem[8'hec] = 8'hce; sbox_mem[8'hed] = 8'h55; sbox_mem[8'hee] = 8'h28; sbox_mem[8'hef] = 8'hdf;
        sbox_mem[8'hf0] = 8'h8c; sbox_mem[8'hf1] = 8'ha1; sbox_mem[8'hf2] = 8'h89; sbox_mem[8'hf3] = 8'h0d;
        sbox_mem[8'hf4] = 8'hbf; sbox_mem[8'hf5] = 8'he6; sbox_mem[8'hf6] = 8'h42; sbox_mem[8'hf7] = 8'h68;
        sbox_mem[8'hf8] = 8'h41; sbox_mem[8'hf9] = 8'h99; sbox_mem[8'hfa] = 8'h2d; sbox_mem[8'hfb] = 8'h0f;
        sbox_mem[8'hfc] = 8'hb0; sbox_mem[8'hfd] = 8'h54; sbox_mem[8'hfe] = 8'hbb; sbox_mem[8'hff] = 8'h16;
    end

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

    reg [7:0] sb0_r, sb1_r, sb2_r, sb3_r;
    always @(posedge clk) begin
        sb0_r  <= sbox_mem[wm1[31:24]];
        sb1_r  <= sbox_mem[wm1[23:16]];
        sb2_r  <= sbox_mem[wm1[15:8]];
        sb3_r  <= sbox_mem[wm1[7:0]];
    end

    wire [31:0] temp = rke[0]
        ? {sb0_r, sb1_r, sb2_r, sb3_r}
        : {sb1_r, sb2_r, sb3_r, sb0_r} ^ {rcon, 24'd0};
    wire [31:0] we0 = w8 ^ temp;
    wire [31:0] we1 = st_prev2[95:64] ^ we0;
    wire [31:0] we2 = st_prev2[63:32] ^ we1;
    wire [31:0] we3 = st_prev2[31:0] ^ we2;

    wire [7:0] sr0  = sbox_mem[a0];
    wire [7:0] sr1  = sbox_mem[a5];
    wire [7:0] sr2  = sbox_mem[a10];
    wire [7:0] sr3  = sbox_mem[a15];
    wire [7:0] sr4  = sbox_mem[a4];
    wire [7:0] sr5  = sbox_mem[a9];
    wire [7:0] sr6  = sbox_mem[a14];
    wire [7:0] sr7  = sbox_mem[a3];
    wire [7:0] sr8  = sbox_mem[a8];
    wire [7:0] sr9  = sbox_mem[a13];
    wire [7:0] sr10 = sbox_mem[a2];
    wire [7:0] sr11 = sbox_mem[a7];
    wire [7:0] sr12 = sbox_mem[a12];
    wire [7:0] sr13 = sbox_mem[a1];
    wire [7:0] sr14 = sbox_mem[a6];
    wire [7:0] sr15 = sbox_mem[a11];

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
                                rd <= 4'd0;
                                phase <= PHASE_CRYPT0;
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
