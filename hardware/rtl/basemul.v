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
    localparam PHASE_IDLE = 1'b0;
    localparam PHASE_RUN  = 1'b1;

    reg        phase;
    reg [6:0]  p;
    reg [11:0] ra [0:255];
    reg [11:0] rb [0:255];
    reg [11:0] rc [0:255];

    integer k;
    wire [7:0] i2 = {p, 1'b0};
    wire [11:0] a0 = ra[i2[7:0]];
    wire [11:0] a1 = ra[i2[7:0] + 8'd1];
    wire [11:0] b0 = rb[i2[7:0]];
    wire [11:0] b1 = rb[i2[7:0] + 8'd1];

    wire [11:0] gv;
    gamma_rom u_gamma (
        .idx(p),
        .gamma(gv)
    );

    wire [11:0] c0;
    wire [11:0] c1;
    basemul_core u_core (
        .a0(a0),
        .a1(a1),
        .b0(b0),
        .b1(b1),
        .gamma(gv),
        .c0(c0),
        .c1(c1)
    );

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
