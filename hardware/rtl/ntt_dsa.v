module ntt_dsa (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [5887:0] coeffs_in,
    output reg          busy,
    output reg          done,
    output wire [5887:0] coeffs_out
);
    localparam Q = 23'd8380417;
    localparam PHASE_IDLE = 1'b0;
    localparam PHASE_RUN  = 1'b1;

    reg        phase;
    reg [9:0]  p;
    reg [22:0] r [0:255];
    reg [22:0] zeta_rom [0:255];

    integer k;
    initial begin
        for (k = 0; k < 256; k = k + 1) begin
            case (k)
                0: zeta_rom[k] = 23'd1;
                1: zeta_rom[k] = 23'd4808194;
                2: zeta_rom[k] = 23'd3765607;
                3: zeta_rom[k] = 23'd3761513;
                4: zeta_rom[k] = 23'd5178923;
                5: zeta_rom[k] = 23'd5496691;
                6: zeta_rom[k] = 23'd5234739;
                7: zeta_rom[k] = 23'd5178987;
                8: zeta_rom[k] = 23'd7778734;
                9: zeta_rom[k] = 23'd3542485;
                10: zeta_rom[k] = 23'd2682288;
                11: zeta_rom[k] = 23'd2129892;
                12: zeta_rom[k] = 23'd3764867;
                13: zeta_rom[k] = 23'd7375178;
                14: zeta_rom[k] = 23'd557458;
                15: zeta_rom[k] = 23'd7159240;
                16: zeta_rom[k] = 23'd5010068;
                17: zeta_rom[k] = 23'd4317364;
                18: zeta_rom[k] = 23'd2663378;
                19: zeta_rom[k] = 23'd6705802;
                20: zeta_rom[k] = 23'd4855975;
                21: zeta_rom[k] = 23'd7946292;
                22: zeta_rom[k] = 23'd676590;
                23: zeta_rom[k] = 23'd7044481;
                24: zeta_rom[k] = 23'd5152541;
                25: zeta_rom[k] = 23'd1714295;
                26: zeta_rom[k] = 23'd2453983;
                27: zeta_rom[k] = 23'd1460718;
                28: zeta_rom[k] = 23'd7737789;
                29: zeta_rom[k] = 23'd4795319;
                30: zeta_rom[k] = 23'd2815639;
                31: zeta_rom[k] = 23'd2283733;
                32: zeta_rom[k] = 23'd3602218;
                33: zeta_rom[k] = 23'd3182878;
                34: zeta_rom[k] = 23'd2740543;
                35: zeta_rom[k] = 23'd4793971;
                36: zeta_rom[k] = 23'd5269599;
                37: zeta_rom[k] = 23'd2101410;
                38: zeta_rom[k] = 23'd3704823;
                39: zeta_rom[k] = 23'd1159875;
                40: zeta_rom[k] = 23'd394148;
                41: zeta_rom[k] = 23'd928749;
                42: zeta_rom[k] = 23'd1095468;
                43: zeta_rom[k] = 23'd4874037;
                44: zeta_rom[k] = 23'd2071829;
                45: zeta_rom[k] = 23'd4361428;
                46: zeta_rom[k] = 23'd3241972;
                47: zeta_rom[k] = 23'd2156050;
                48: zeta_rom[k] = 23'd3415069;
                49: zeta_rom[k] = 23'd1759347;
                50: zeta_rom[k] = 23'd7562881;
                51: zeta_rom[k] = 23'd4805951;
                52: zeta_rom[k] = 23'd3756790;
                53: zeta_rom[k] = 23'd6444618;
                54: zeta_rom[k] = 23'd6663429;
                55: zeta_rom[k] = 23'd4430364;
                56: zeta_rom[k] = 23'd5483103;
                57: zeta_rom[k] = 23'd3192354;
                58: zeta_rom[k] = 23'd556856;
                59: zeta_rom[k] = 23'd3870317;
                60: zeta_rom[k] = 23'd2917338;
                61: zeta_rom[k] = 23'd1853806;
                62: zeta_rom[k] = 23'd3345963;
                63: zeta_rom[k] = 23'd1858416;
                64: zeta_rom[k] = 23'd3073009;
                65: zeta_rom[k] = 23'd1277625;
                66: zeta_rom[k] = 23'd5744944;
                67: zeta_rom[k] = 23'd3852015;
                68: zeta_rom[k] = 23'd4183372;
                69: zeta_rom[k] = 23'd5157610;
                70: zeta_rom[k] = 23'd5258977;
                71: zeta_rom[k] = 23'd8106357;
                72: zeta_rom[k] = 23'd2508980;
                73: zeta_rom[k] = 23'd2028118;
                74: zeta_rom[k] = 23'd1937570;
                75: zeta_rom[k] = 23'd4564692;
                76: zeta_rom[k] = 23'd2811291;
                77: zeta_rom[k] = 23'd5396636;
                78: zeta_rom[k] = 23'd7270901;
                79: zeta_rom[k] = 23'd4158088;
                80: zeta_rom[k] = 23'd1528066;
                81: zeta_rom[k] = 23'd482649;
                82: zeta_rom[k] = 23'd1148858;
                83: zeta_rom[k] = 23'd5418153;
                84: zeta_rom[k] = 23'd7814814;
                85: zeta_rom[k] = 23'd169688;
                86: zeta_rom[k] = 23'd2462444;
                87: zeta_rom[k] = 23'd5046034;
                88: zeta_rom[k] = 23'd4213992;
                89: zeta_rom[k] = 23'd4892034;
                90: zeta_rom[k] = 23'd1987814;
                91: zeta_rom[k] = 23'd5183169;
                92: zeta_rom[k] = 23'd1736313;
                93: zeta_rom[k] = 23'd235407;
                94: zeta_rom[k] = 23'd5130263;
                95: zeta_rom[k] = 23'd3258457;
                96: zeta_rom[k] = 23'd5801164;
                97: zeta_rom[k] = 23'd1787943;
                98: zeta_rom[k] = 23'd5989328;
                99: zeta_rom[k] = 23'd6125690;
                100: zeta_rom[k] = 23'd3482206;
                101: zeta_rom[k] = 23'd4197502;
                102: zeta_rom[k] = 23'd7080401;
                103: zeta_rom[k] = 23'd6018354;
                104: zeta_rom[k] = 23'd7062739;
                105: zeta_rom[k] = 23'd2461387;
                106: zeta_rom[k] = 23'd3035980;
                107: zeta_rom[k] = 23'd621164;
                108: zeta_rom[k] = 23'd3901472;
                109: zeta_rom[k] = 23'd7153756;
                110: zeta_rom[k] = 23'd2925816;
                111: zeta_rom[k] = 23'd3374250;
                112: zeta_rom[k] = 23'd1356448;
                113: zeta_rom[k] = 23'd5604662;
                114: zeta_rom[k] = 23'd2683270;
                115: zeta_rom[k] = 23'd5601629;
                116: zeta_rom[k] = 23'd4912752;
                117: zeta_rom[k] = 23'd2312838;
                118: zeta_rom[k] = 23'd7727142;
                119: zeta_rom[k] = 23'd7921254;
                120: zeta_rom[k] = 23'd348812;
                121: zeta_rom[k] = 23'd8052569;
                122: zeta_rom[k] = 23'd1011223;
                123: zeta_rom[k] = 23'd6026202;
                124: zeta_rom[k] = 23'd4561790;
                125: zeta_rom[k] = 23'd6458164;
                126: zeta_rom[k] = 23'd6143691;
                127: zeta_rom[k] = 23'd1744507;
                128: zeta_rom[k] = 23'd1753;
                129: zeta_rom[k] = 23'd6444997;
                130: zeta_rom[k] = 23'd5720892;
                131: zeta_rom[k] = 23'd6924527;
                132: zeta_rom[k] = 23'd2660408;
                133: zeta_rom[k] = 23'd6600190;
                134: zeta_rom[k] = 23'd8321269;
                135: zeta_rom[k] = 23'd2772600;
                136: zeta_rom[k] = 23'd1182243;
                137: zeta_rom[k] = 23'd87208;
                138: zeta_rom[k] = 23'd636927;
                139: zeta_rom[k] = 23'd4415111;
                140: zeta_rom[k] = 23'd4423672;
                141: zeta_rom[k] = 23'd6084020;
                142: zeta_rom[k] = 23'd5095502;
                143: zeta_rom[k] = 23'd4663471;
                144: zeta_rom[k] = 23'd8352605;
                145: zeta_rom[k] = 23'd822541;
                146: zeta_rom[k] = 23'd1009365;
                147: zeta_rom[k] = 23'd5926272;
                148: zeta_rom[k] = 23'd6400920;
                149: zeta_rom[k] = 23'd1596822;
                150: zeta_rom[k] = 23'd4423473;
                151: zeta_rom[k] = 23'd4620952;
                152: zeta_rom[k] = 23'd6695264;
                153: zeta_rom[k] = 23'd4969849;
                154: zeta_rom[k] = 23'd2678278;
                155: zeta_rom[k] = 23'd4611469;
                156: zeta_rom[k] = 23'd4829411;
                157: zeta_rom[k] = 23'd635956;
                158: zeta_rom[k] = 23'd8129971;
                159: zeta_rom[k] = 23'd5925040;
                160: zeta_rom[k] = 23'd4234153;
                161: zeta_rom[k] = 23'd6607829;
                162: zeta_rom[k] = 23'd2192938;
                163: zeta_rom[k] = 23'd6653329;
                164: zeta_rom[k] = 23'd2387513;
                165: zeta_rom[k] = 23'd4768667;
                166: zeta_rom[k] = 23'd8111961;
                167: zeta_rom[k] = 23'd5199961;
                168: zeta_rom[k] = 23'd3747250;
                169: zeta_rom[k] = 23'd2296099;
                170: zeta_rom[k] = 23'd1239911;
                171: zeta_rom[k] = 23'd4541938;
                172: zeta_rom[k] = 23'd3195676;
                173: zeta_rom[k] = 23'd2642980;
                174: zeta_rom[k] = 23'd1254190;
                175: zeta_rom[k] = 23'd8368000;
                176: zeta_rom[k] = 23'd2998219;
                177: zeta_rom[k] = 23'd141835;
                178: zeta_rom[k] = 23'd8291116;
                179: zeta_rom[k] = 23'd2513018;
                180: zeta_rom[k] = 23'd7025525;
                181: zeta_rom[k] = 23'd613238;
                182: zeta_rom[k] = 23'd7070156;
                183: zeta_rom[k] = 23'd6161950;
                184: zeta_rom[k] = 23'd7921677;
                185: zeta_rom[k] = 23'd6458423;
                186: zeta_rom[k] = 23'd4040196;
                187: zeta_rom[k] = 23'd4908348;
                188: zeta_rom[k] = 23'd2039144;
                189: zeta_rom[k] = 23'd6500539;
                190: zeta_rom[k] = 23'd7561656;
                191: zeta_rom[k] = 23'd6201452;
                192: zeta_rom[k] = 23'd6757063;
                193: zeta_rom[k] = 23'd2105286;
                194: zeta_rom[k] = 23'd6006015;
                195: zeta_rom[k] = 23'd6346610;
                196: zeta_rom[k] = 23'd586241;
                197: zeta_rom[k] = 23'd7200804;
                198: zeta_rom[k] = 23'd527981;
                199: zeta_rom[k] = 23'd5637006;
                200: zeta_rom[k] = 23'd6903432;
                201: zeta_rom[k] = 23'd1994046;
                202: zeta_rom[k] = 23'd2491325;
                203: zeta_rom[k] = 23'd6987258;
                204: zeta_rom[k] = 23'd507927;
                205: zeta_rom[k] = 23'd7192532;
                206: zeta_rom[k] = 23'd7655613;
                207: zeta_rom[k] = 23'd6545891;
                208: zeta_rom[k] = 23'd5346675;
                209: zeta_rom[k] = 23'd8041997;
                210: zeta_rom[k] = 23'd2647994;
                211: zeta_rom[k] = 23'd3009748;
                212: zeta_rom[k] = 23'd5767564;
                213: zeta_rom[k] = 23'd4148469;
                214: zeta_rom[k] = 23'd749577;
                215: zeta_rom[k] = 23'd4357667;
                216: zeta_rom[k] = 23'd3980599;
                217: zeta_rom[k] = 23'd2569011;
                218: zeta_rom[k] = 23'd6764887;
                219: zeta_rom[k] = 23'd1723229;
                220: zeta_rom[k] = 23'd1665318;
                221: zeta_rom[k] = 23'd2028038;
                222: zeta_rom[k] = 23'd1163598;
                223: zeta_rom[k] = 23'd5011144;
                224: zeta_rom[k] = 23'd3994671;
                225: zeta_rom[k] = 23'd8368538;
                226: zeta_rom[k] = 23'd7009900;
                227: zeta_rom[k] = 23'd3020393;
                228: zeta_rom[k] = 23'd3363542;
                229: zeta_rom[k] = 23'd214880;
                230: zeta_rom[k] = 23'd545376;
                231: zeta_rom[k] = 23'd7609976;
                232: zeta_rom[k] = 23'd3105558;
                233: zeta_rom[k] = 23'd7277073;
                234: zeta_rom[k] = 23'd508145;
                235: zeta_rom[k] = 23'd7826699;
                236: zeta_rom[k] = 23'd860144;
                237: zeta_rom[k] = 23'd3430436;
                238: zeta_rom[k] = 23'd140244;
                239: zeta_rom[k] = 23'd6866265;
                240: zeta_rom[k] = 23'd6195333;
                241: zeta_rom[k] = 23'd3123762;
                242: zeta_rom[k] = 23'd2358373;
                243: zeta_rom[k] = 23'd6187330;
                244: zeta_rom[k] = 23'd5365997;
                245: zeta_rom[k] = 23'd6663603;
                246: zeta_rom[k] = 23'd2926054;
                247: zeta_rom[k] = 23'd7987710;
                248: zeta_rom[k] = 23'd8077412;
                249: zeta_rom[k] = 23'd3531229;
                250: zeta_rom[k] = 23'd4405932;
                251: zeta_rom[k] = 23'd4606686;
                252: zeta_rom[k] = 23'd1900052;
                253: zeta_rom[k] = 23'd7598542;
                254: zeta_rom[k] = 23'd1054478;
                default: zeta_rom[k] = 23'd7648983;
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
    wire [8:0] zidx9 = (9'd1 << len_idx) + {2'b0, gg};

    wire [22:0] rv = r[u_len[7:0]];
    wire [45:0] prod = zeta_rom[zidx9[7:0]] * rv;
    wire [71:0] m72 = prod * 26'd33587228;
    wire [23:0] m = m72[71:48];
    wire [46:0] mq = m * {24'd0, Q};
    wire [46:0] rr = {1'b0, prod} - mq;
    wire [46:0] rr1 = (rr >= {24'd0, Q}) ? rr - {24'd0, Q} : rr;
    wire [46:0] rr2 = (rr1 >= {24'd0, Q}) ? rr1 - {24'd0, Q} : rr1;
    wire [22:0] t = rr2[22:0];

    wire [23:0] nu = {1'b0, r[u[7:0]]} + {1'b0, t};
    wire [23:0] nu_r = (nu >= {1'b0, Q}) ? nu - {1'b0, Q} : nu;
    wire [23:0] nd = {1'b0, r[u[7:0]]} + {1'b0, Q} - {1'b0, t};
    wire [23:0] nd_r = (nd >= {1'b0, Q}) ? nd - {1'b0, Q} : nd;

    genvar g;
    generate
        for (g = 0; g < 256; g = g + 1) begin : out_map
            assign coeffs_out[23*g +: 23] = r[g];
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
                            r[k] = coeffs_in[23*k +: 23];
                        p <= 10'd0;
                        busy <= 1'b1;
                        phase <= PHASE_RUN;
                    end
                end
                PHASE_RUN: begin
                    r[u[7:0]] <= nu_r[22:0];
                    r[u_len[7:0]] <= nd_r[22:0];
                    if (p == 10'd1023) begin
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
