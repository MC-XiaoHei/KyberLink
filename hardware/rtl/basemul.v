module basemul (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [3071:0] coeffs_a,
    input  wire [3071:0] coeffs_b,
    output reg          busy,
    output reg          done,
    output wire [3071:0] coeffs_out
);
    localparam Q = 13'd3329;
    localparam PHASE_IDLE = 1'b0;
    localparam PHASE_RUN  = 1'b1;

    reg        phase;
    reg [6:0]  p;
    reg [11:0] ra [0:255];
    reg [11:0] rb [0:255];
    reg [11:0] rc [0:255];
    reg [11:0] gamma_rom [0:127];

    integer k;
    initial begin
        for (k = 0; k < 128; k = k + 1) begin
            case (k)
                0: gamma_rom[k] = 12'd17;
                1: gamma_rom[k] = 12'd3312;
                2: gamma_rom[k] = 12'd2761;
                3: gamma_rom[k] = 12'd568;
                4: gamma_rom[k] = 12'd583;
                5: gamma_rom[k] = 12'd2746;
                6: gamma_rom[k] = 12'd2649;
                7: gamma_rom[k] = 12'd680;
                8: gamma_rom[k] = 12'd1637;
                9: gamma_rom[k] = 12'd1692;
                10: gamma_rom[k] = 12'd723;
                11: gamma_rom[k] = 12'd2606;
                12: gamma_rom[k] = 12'd2288;
                13: gamma_rom[k] = 12'd1041;
                14: gamma_rom[k] = 12'd1100;
                15: gamma_rom[k] = 12'd2229;
                16: gamma_rom[k] = 12'd1409;
                17: gamma_rom[k] = 12'd1920;
                18: gamma_rom[k] = 12'd2662;
                19: gamma_rom[k] = 12'd667;
                20: gamma_rom[k] = 12'd3281;
                21: gamma_rom[k] = 12'd48;
                22: gamma_rom[k] = 12'd233;
                23: gamma_rom[k] = 12'd3096;
                24: gamma_rom[k] = 12'd756;
                25: gamma_rom[k] = 12'd2573;
                26: gamma_rom[k] = 12'd2156;
                27: gamma_rom[k] = 12'd1173;
                28: gamma_rom[k] = 12'd3015;
                29: gamma_rom[k] = 12'd314;
                30: gamma_rom[k] = 12'd3050;
                31: gamma_rom[k] = 12'd279;
                32: gamma_rom[k] = 12'd1703;
                33: gamma_rom[k] = 12'd1626;
                34: gamma_rom[k] = 12'd1651;
                35: gamma_rom[k] = 12'd1678;
                36: gamma_rom[k] = 12'd2789;
                37: gamma_rom[k] = 12'd540;
                38: gamma_rom[k] = 12'd1789;
                39: gamma_rom[k] = 12'd1540;
                40: gamma_rom[k] = 12'd1847;
                41: gamma_rom[k] = 12'd1482;
                42: gamma_rom[k] = 12'd952;
                43: gamma_rom[k] = 12'd2377;
                44: gamma_rom[k] = 12'd1461;
                45: gamma_rom[k] = 12'd1868;
                46: gamma_rom[k] = 12'd2687;
                47: gamma_rom[k] = 12'd642;
                48: gamma_rom[k] = 12'd939;
                49: gamma_rom[k] = 12'd2390;
                50: gamma_rom[k] = 12'd2308;
                51: gamma_rom[k] = 12'd1021;
                52: gamma_rom[k] = 12'd2437;
                53: gamma_rom[k] = 12'd892;
                54: gamma_rom[k] = 12'd2388;
                55: gamma_rom[k] = 12'd941;
                56: gamma_rom[k] = 12'd733;
                57: gamma_rom[k] = 12'd2596;
                58: gamma_rom[k] = 12'd2337;
                59: gamma_rom[k] = 12'd992;
                60: gamma_rom[k] = 12'd268;
                61: gamma_rom[k] = 12'd3061;
                62: gamma_rom[k] = 12'd641;
                63: gamma_rom[k] = 12'd2688;
                64: gamma_rom[k] = 12'd1584;
                65: gamma_rom[k] = 12'd1745;
                66: gamma_rom[k] = 12'd2298;
                67: gamma_rom[k] = 12'd1031;
                68: gamma_rom[k] = 12'd2037;
                69: gamma_rom[k] = 12'd1292;
                70: gamma_rom[k] = 12'd3220;
                71: gamma_rom[k] = 12'd109;
                72: gamma_rom[k] = 12'd375;
                73: gamma_rom[k] = 12'd2954;
                74: gamma_rom[k] = 12'd2549;
                75: gamma_rom[k] = 12'd780;
                76: gamma_rom[k] = 12'd2090;
                77: gamma_rom[k] = 12'd1239;
                78: gamma_rom[k] = 12'd1645;
                79: gamma_rom[k] = 12'd1684;
                80: gamma_rom[k] = 12'd1063;
                81: gamma_rom[k] = 12'd2266;
                82: gamma_rom[k] = 12'd319;
                83: gamma_rom[k] = 12'd3010;
                84: gamma_rom[k] = 12'd2773;
                85: gamma_rom[k] = 12'd556;
                86: gamma_rom[k] = 12'd757;
                87: gamma_rom[k] = 12'd2572;
                88: gamma_rom[k] = 12'd2099;
                89: gamma_rom[k] = 12'd1230;
                90: gamma_rom[k] = 12'd561;
                91: gamma_rom[k] = 12'd2768;
                92: gamma_rom[k] = 12'd2466;
                93: gamma_rom[k] = 12'd863;
                94: gamma_rom[k] = 12'd2594;
                95: gamma_rom[k] = 12'd735;
                96: gamma_rom[k] = 12'd2804;
                97: gamma_rom[k] = 12'd525;
                98: gamma_rom[k] = 12'd1092;
                99: gamma_rom[k] = 12'd2237;
                100: gamma_rom[k] = 12'd403;
                101: gamma_rom[k] = 12'd2926;
                102: gamma_rom[k] = 12'd1026;
                103: gamma_rom[k] = 12'd2303;
                104: gamma_rom[k] = 12'd1143;
                105: gamma_rom[k] = 12'd2186;
                106: gamma_rom[k] = 12'd2150;
                107: gamma_rom[k] = 12'd1179;
                108: gamma_rom[k] = 12'd2775;
                109: gamma_rom[k] = 12'd554;
                110: gamma_rom[k] = 12'd886;
                111: gamma_rom[k] = 12'd2443;
                112: gamma_rom[k] = 12'd1722;
                113: gamma_rom[k] = 12'd1607;
                114: gamma_rom[k] = 12'd1212;
                115: gamma_rom[k] = 12'd2117;
                116: gamma_rom[k] = 12'd1874;
                117: gamma_rom[k] = 12'd1455;
                118: gamma_rom[k] = 12'd1029;
                119: gamma_rom[k] = 12'd2300;
                120: gamma_rom[k] = 12'd2110;
                121: gamma_rom[k] = 12'd1219;
                122: gamma_rom[k] = 12'd2935;
                123: gamma_rom[k] = 12'd394;
                124: gamma_rom[k] = 12'd885;
                125: gamma_rom[k] = 12'd2444;
                126: gamma_rom[k] = 12'd2154;
                default: gamma_rom[k] = 12'd1175;
            endcase
        end
    end

    wire [7:0] i2 = {p, 1'b0};
    wire [11:0] a0 = ra[i2[7:0]];
    wire [11:0] a1 = ra[i2[7:0] + 8'd1];
    wire [11:0] b0 = rb[i2[7:0]];
    wire [11:0] b1 = rb[i2[7:0] + 8'd1];

    function [11:0] barrett;
        input [23:0] x;
        reg [38:0] m39;
        reg [25:0] r2;
        reg [25:0] r3;
        begin
            m39 = {15'd0, x} * 15'd20158;
            r2 = {2'b0, x} - {13'd0, m39[38:26]} * {13'd0, Q};
            r3 = (r2 >= {13'd0, Q}) ? r2 - {13'd0, Q} : r2;
            barrett = r3[11:0];
        end
    endfunction

    wire [11:0] t0 = barrett({12'd0, a0} * {12'd0, b0});
    wire [11:0] t1 = barrett({12'd0, a1} * {12'd0, b1});
    wire [11:0] t1g = barrett({12'd0, t1} * {12'd0, gamma_rom[p]});
    wire [11:0] t2 = barrett({12'd0, a0} * {12'd0, b1});
    wire [11:0] t3 = barrett({12'd0, a1} * {12'd0, b0});

    wire [12:0] c0s = {1'b0, t0} + {1'b0, t1g};
    wire [12:0] c1s = {1'b0, t2} + {1'b0, t3};
    wire [12:0] c0r = (c0s >= Q) ? c0s - Q : c0s;
    wire [12:0] c1r = (c1s >= Q) ? c1s - Q : c1s;
    wire [11:0] c0 = c0r[11:0];
    wire [11:0] c1 = c1r[11:0];

    genvar g;
    generate
        for (g = 0; g < 256; g = g + 1) begin : out_map
            assign coeffs_out[12*g +: 12] = rc[g];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            p <= 7'd0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        for (k = 0; k < 256; k = k + 1) begin
                            ra[k] = coeffs_a[12*k +: 12];
                            rb[k] = coeffs_b[12*k +: 12];
                        end
                        p <= 7'd0;
                        busy <= 1'b1;
                        phase <= PHASE_RUN;
                    end
                end
                PHASE_RUN: begin
                    rc[i2[7:0]] <= c0;
                    rc[i2[7:0] + 8'd1] <= c1;
                    if (p == 7'd127) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        phase <= PHASE_IDLE;
                    end else begin
                        p <= p + 7'd1;
                    end
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end
endmodule
