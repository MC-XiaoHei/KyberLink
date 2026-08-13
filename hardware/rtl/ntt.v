module ntt (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [3071:0] coeffs_in,
    output reg          busy,
    output reg          done,
    output wire [3071:0] coeffs_out
);
    localparam Q = 13'd3329;
    localparam PHASE_IDLE = 1'b0;
    localparam PHASE_RUN  = 1'b1;

    reg        phase;
    reg [9:0]  p;
    reg [11:0] r [0:255];
    reg [11:0] zeta_rom [0:127];

    integer k;
    initial begin
        for (k = 0; k < 128; k = k + 1) begin
            case (k)
                0: zeta_rom[k] = 12'd1;
                1: zeta_rom[k] = 12'd1729;
                2: zeta_rom[k] = 12'd2580;
                3: zeta_rom[k] = 12'd3289;
                4: zeta_rom[k] = 12'd2642;
                5: zeta_rom[k] = 12'd630;
                6: zeta_rom[k] = 12'd1897;
                7: zeta_rom[k] = 12'd848;
                8: zeta_rom[k] = 12'd1062;
                9: zeta_rom[k] = 12'd1919;
                10: zeta_rom[k] = 12'd193;
                11: zeta_rom[k] = 12'd797;
                12: zeta_rom[k] = 12'd2786;
                13: zeta_rom[k] = 12'd3260;
                14: zeta_rom[k] = 12'd569;
                15: zeta_rom[k] = 12'd1746;
                16: zeta_rom[k] = 12'd296;
                17: zeta_rom[k] = 12'd2447;
                18: zeta_rom[k] = 12'd1339;
                19: zeta_rom[k] = 12'd1476;
                20: zeta_rom[k] = 12'd3046;
                21: zeta_rom[k] = 12'd56;
                22: zeta_rom[k] = 12'd2240;
                23: zeta_rom[k] = 12'd1333;
                24: zeta_rom[k] = 12'd1426;
                25: zeta_rom[k] = 12'd2094;
                26: zeta_rom[k] = 12'd535;
                27: zeta_rom[k] = 12'd2882;
                28: zeta_rom[k] = 12'd2393;
                29: zeta_rom[k] = 12'd2879;
                30: zeta_rom[k] = 12'd1974;
                31: zeta_rom[k] = 12'd821;
                32: zeta_rom[k] = 12'd289;
                33: zeta_rom[k] = 12'd331;
                34: zeta_rom[k] = 12'd3253;
                35: zeta_rom[k] = 12'd1756;
                36: zeta_rom[k] = 12'd1197;
                37: zeta_rom[k] = 12'd2304;
                38: zeta_rom[k] = 12'd2277;
                39: zeta_rom[k] = 12'd2055;
                40: zeta_rom[k] = 12'd650;
                41: zeta_rom[k] = 12'd1977;
                42: zeta_rom[k] = 12'd2513;
                43: zeta_rom[k] = 12'd632;
                44: zeta_rom[k] = 12'd2865;
                45: zeta_rom[k] = 12'd33;
                46: zeta_rom[k] = 12'd1320;
                47: zeta_rom[k] = 12'd1915;
                48: zeta_rom[k] = 12'd2319;
                49: zeta_rom[k] = 12'd1435;
                50: zeta_rom[k] = 12'd807;
                51: zeta_rom[k] = 12'd452;
                52: zeta_rom[k] = 12'd1438;
                53: zeta_rom[k] = 12'd2868;
                54: zeta_rom[k] = 12'd1534;
                55: zeta_rom[k] = 12'd2402;
                56: zeta_rom[k] = 12'd2647;
                57: zeta_rom[k] = 12'd2617;
                58: zeta_rom[k] = 12'd1481;
                59: zeta_rom[k] = 12'd648;
                60: zeta_rom[k] = 12'd2474;
                61: zeta_rom[k] = 12'd3110;
                62: zeta_rom[k] = 12'd1227;
                63: zeta_rom[k] = 12'd910;
                64: zeta_rom[k] = 12'd17;
                65: zeta_rom[k] = 12'd2761;
                66: zeta_rom[k] = 12'd583;
                67: zeta_rom[k] = 12'd2649;
                68: zeta_rom[k] = 12'd1637;
                69: zeta_rom[k] = 12'd723;
                70: zeta_rom[k] = 12'd2288;
                71: zeta_rom[k] = 12'd1100;
                72: zeta_rom[k] = 12'd1409;
                73: zeta_rom[k] = 12'd2662;
                74: zeta_rom[k] = 12'd3281;
                75: zeta_rom[k] = 12'd233;
                76: zeta_rom[k] = 12'd756;
                77: zeta_rom[k] = 12'd2156;
                78: zeta_rom[k] = 12'd3015;
                79: zeta_rom[k] = 12'd3050;
                80: zeta_rom[k] = 12'd1703;
                81: zeta_rom[k] = 12'd1651;
                82: zeta_rom[k] = 12'd2789;
                83: zeta_rom[k] = 12'd1789;
                84: zeta_rom[k] = 12'd1847;
                85: zeta_rom[k] = 12'd952;
                86: zeta_rom[k] = 12'd1461;
                87: zeta_rom[k] = 12'd2687;
                88: zeta_rom[k] = 12'd939;
                89: zeta_rom[k] = 12'd2308;
                90: zeta_rom[k] = 12'd2437;
                91: zeta_rom[k] = 12'd2388;
                92: zeta_rom[k] = 12'd733;
                93: zeta_rom[k] = 12'd2337;
                94: zeta_rom[k] = 12'd268;
                95: zeta_rom[k] = 12'd641;
                96: zeta_rom[k] = 12'd1584;
                97: zeta_rom[k] = 12'd2298;
                98: zeta_rom[k] = 12'd2037;
                99: zeta_rom[k] = 12'd3220;
                100: zeta_rom[k] = 12'd375;
                101: zeta_rom[k] = 12'd2549;
                102: zeta_rom[k] = 12'd2090;
                103: zeta_rom[k] = 12'd1645;
                104: zeta_rom[k] = 12'd1063;
                105: zeta_rom[k] = 12'd319;
                106: zeta_rom[k] = 12'd2773;
                107: zeta_rom[k] = 12'd757;
                108: zeta_rom[k] = 12'd2099;
                109: zeta_rom[k] = 12'd561;
                110: zeta_rom[k] = 12'd2466;
                111: zeta_rom[k] = 12'd2594;
                112: zeta_rom[k] = 12'd2804;
                113: zeta_rom[k] = 12'd1092;
                114: zeta_rom[k] = 12'd403;
                115: zeta_rom[k] = 12'd1026;
                116: zeta_rom[k] = 12'd1143;
                117: zeta_rom[k] = 12'd2150;
                118: zeta_rom[k] = 12'd2775;
                119: zeta_rom[k] = 12'd886;
                120: zeta_rom[k] = 12'd1722;
                121: zeta_rom[k] = 12'd1212;
                122: zeta_rom[k] = 12'd1874;
                123: zeta_rom[k] = 12'd1029;
                124: zeta_rom[k] = 12'd2110;
                125: zeta_rom[k] = 12'd2935;
                126: zeta_rom[k] = 12'd885;
                default: zeta_rom[k] = 12'd2154;
            endcase
        end
    end

    wire [3:0] len_idx = {1'b0, p[9:7]};
    wire [3:0] len_log = 4'd7 - len_idx;
    wire [8:0] len = 9'd128 >> len_idx;
    wire [8:0] len_m1 = len - 9'd1;
    wire [6:0] j = p[6:0] & len_m1[6:0];
    wire [6:0] gg = p[6:0] >> len_log;
    wire [8:0] st = {2'b0, gg} << (len_log + 1);
    wire [8:0] u = {2'b0, j} + st;
    wire [8:0] u_len = u + len;
    wire [8:0] zidx9 = (9'd128 >> len_log) + {2'b0, gg};

    wire [11:0] rv = r[u_len[7:0]];
    wire [23:0] prod = {12'd0, zeta_rom[zidx9[6:0]]} * {12'd0, rv};
    wire [38:0] m39 = {15'd0, prod} * 15'd20158;
    wire [12:0] m = m39[38:26];
    wire [25:0] mq = {13'd0, m} * {13'd0, Q};
    wire [25:0] rr = {2'b0, prod} - mq;
    wire [25:0] rr1 = (rr >= {13'd0, Q}) ? rr - {13'd0, Q} : rr;
    wire [11:0] t = rr1[11:0];

    wire [12:0] nu = {1'b0, r[u[7:0]]} + {1'b0, t};
    wire signed [13:0] nd_s = $signed({1'b0, r[u[7:0]]}) - $signed({1'b0, t});
    wire [12:0] nu_r = (nu >= Q) ? nu - Q : nu;
    wire [13:0] nd_r = (nd_s < 0) ? nd_s + Q : nd_s;

    genvar g;
    generate
        for (g = 0; g < 256; g = g + 1) begin : out_map
            assign coeffs_out[12*g +: 12] = r[g];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            p <= 10'd0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        for (k = 0; k < 256; k = k + 1)
                            r[k] = coeffs_in[12*k +: 12];
                        p <= 10'd0;
                        busy <= 1'b1;
                        phase <= PHASE_RUN;
                    end
                end
                PHASE_RUN: begin
                    r[u[7:0]] <= nu_r[11:0];
                    r[u_len[7:0]] <= nd_r[11:0];
                    if (p == 10'd895) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        phase <= PHASE_IDLE;
                    end else begin
                        p <= p + 10'd1;
                    end
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end
endmodule
