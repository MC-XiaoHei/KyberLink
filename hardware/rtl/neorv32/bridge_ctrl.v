module bridge_ctrl (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] xbus_adr_i,
    input  wire [31:0] xbus_dat_i,
    input  wire        xbus_we_i,
    input  wire        xbus_stb_i,
    input  wire        xbus_cyc_i,
    output reg  [31:0] xbus_dat_o,
    output reg         xbus_ack_o,
    output reg         xbus_err_o,
    output reg  [255:0] cfg_key,
    output reg          cfg_sa_en,
    output reg          cfg_cmd_start,
    input  wire         data_sa_active,
    input  wire [31:0]  data_count_tx,
    input  wire [31:0]  data_count_rx
);

    reg [7:0] reg_sel_d;
    wire xbus_active = xbus_stb_i && xbus_cyc_i && (xbus_adr_i[31:8] == 24'hF00001);
    reg [3:0] key_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_key <= 256'd0;
            cfg_sa_en <= 1'b0;
            cfg_cmd_start <= 1'b0;
            xbus_dat_o <= 32'd0;
            xbus_ack_o <= 1'b0;
            xbus_err_o <= 1'b0;
        end else begin
            xbus_ack_o <= 1'b0;
            xbus_err_o <= 1'b0;
            cfg_cmd_start <= 1'b0;
            if (xbus_active && xbus_we_i) begin
                case (xbus_adr_i[7:0])
                    8'h00: cfg_key[31:0]    <= xbus_dat_i;
                    8'h04: cfg_key[63:32]   <= xbus_dat_i;
                    8'h08: cfg_key[95:64]   <= xbus_dat_i;
                    8'h0C: cfg_key[127:96]  <= xbus_dat_i;
                    8'h10: cfg_key[159:128] <= xbus_dat_i;
                    8'h14: cfg_key[191:160] <= xbus_dat_i;
                    8'h18: cfg_key[223:192] <= xbus_dat_i;
                    8'h1C: cfg_key[255:224] <= xbus_dat_i;
                    8'h20: begin
                        cfg_sa_en <= xbus_dat_i[0];
                        cfg_cmd_start <= xbus_dat_i[1];
                    end
                    default: xbus_err_o <= 1'b1;
                endcase
                xbus_ack_o <= 1'b1;
            end else if (xbus_active && !xbus_we_i) begin
                case (xbus_adr_i[7:0])
                    8'h00: xbus_dat_o <= cfg_key[31:0];
                    8'h04: xbus_dat_o <= cfg_key[63:32];
                    8'h08: xbus_dat_o <= cfg_key[95:64];
                    8'h0C: xbus_dat_o <= cfg_key[127:96];
                    8'h10: xbus_dat_o <= cfg_key[159:128];
                    8'h14: xbus_dat_o <= cfg_key[191:160];
                    8'h18: xbus_dat_o <= cfg_key[223:192];
                    8'h1C: xbus_dat_o <= cfg_key[255:224];
                    8'h24: xbus_dat_o <= {30'd0, 1'b0, data_sa_active};
                    8'h28: xbus_dat_o <= data_count_tx;
                    8'h2C: xbus_dat_o <= data_count_rx;
                    default: begin
                        xbus_dat_o <= 32'd0;
                        xbus_err_o <= 1'b1;
                    end
                endcase
                xbus_ack_o <= 1'b1;
            end
        end
    end
endmodule
