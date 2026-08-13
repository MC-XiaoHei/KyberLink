module compress (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire mode,
    input wire [3:0] d,
    input wire [3071:0] x_in,
    output reg busy,
    output reg done,
    output wire [3071:0] y_out
);
    reg [11:0] y_arr [0:255];

    localparam PHASE_IDLE = 1'b0;
    localparam PHASE_RUN = 1'b1;

    reg phase;
    reg [8:0] i;
    reg mode_r;
    reg [3:0] d_r;

    wire [11:0] xs = x_in[12 * i +: 12];
    wire [23:0] ca = ({12'd0, xs} << d_r) + 24'd1665;
    wire [46:0] cp = ca * 47'd5160669;
    wire [46:0] cps = cp >> 34;
    wire [24:0] dn = {13'd0, xs} * 25'd3329 + (25'd1 << (d_r - 1));
    wire [24:0] dns = dn >> d_r;
    wire [11:0] cmask = ({12'd1 << d_r}) - 12'd1;
    wire [12:0] yc = {1'b0, (cps[11:0] & cmask)};
    wire [12:0] yd = dns[12:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            i <= 9'd0;
            mode_r <= 1'b0;
            d_r <= 4'd0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        mode_r <= mode;
                        d_r <= d;
                        i <= 9'd0;
                        busy <= 1'b1;
                        phase <= PHASE_RUN;
                    end
                end
                PHASE_RUN: begin
                    y_arr[i[7:0]] <= (mode_r == 1'b0) ? yc[11:0] : yd[11:0];
                    if (i == 9'd255) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        phase <= PHASE_IDLE;
                    end else begin
                        i <= i + 9'd1;
                    end
                end
            endcase
        end
    end

    genvar gi;
    generate
        for (gi = 0; gi < 256; gi = gi + 1) begin : g_y
            assign y_out[12 * gi +: 12] = y_arr[gi];
        end
    endgenerate
endmodule
