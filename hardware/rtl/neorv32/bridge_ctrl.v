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
    output reg  [255:0] enc_key,
    output reg  [255:0] dec_key,
    output reg  [31:0]  enc_spi,
    output reg  [95:0]  enc_salt,
    output reg  [31:0]  enc_seq0,
    output reg  [31:0]  dec_spi,
    output reg  [95:0]  dec_salt,
    output reg  [31:0]  dec_seq0,
    output reg  [31:0]  cfg_src_ip,
    output reg  [31:0]  cfg_dst_ip,
    output reg  [15:0]  cfg_src_port,
    output reg  [15:0]  cfg_dst_port,
    output reg  [47:0]  cfg_src_mac,
    output reg  [47:0]  cfg_dst_mac,
    output reg  [1:0]   cfg_sa_en,
    output reg          cfg_cmd_start,
    input  wire         data_sa_active,
    input  wire [31:0]  data_count_tx,
    input  wire [31:0]  data_count_rx,
    input  wire [31:0]  data_seq_out
);

    wire xbus_active = xbus_stb_i && xbus_cyc_i && (xbus_adr_i[31:8] == 24'hF00001);
    reg [3:0] key_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enc_key <= 256'd0;
            dec_key <= 256'd0;
            enc_spi <= 32'd0;
            enc_salt <= 96'd0;
            enc_seq0 <= 32'd0;
            dec_spi <= 32'd0;
            dec_salt <= 96'd0;
            dec_seq0 <= 32'd0;
            cfg_src_ip <= 32'd0;
            cfg_dst_ip <= 32'd0;
            cfg_src_port <= 16'd0;
            cfg_dst_port <= 16'd0;
            cfg_src_mac <= 48'd0;
            cfg_dst_mac <= 48'd0;
            cfg_sa_en <= 2'b00;
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
                    8'h00: enc_key[31:0]    <= xbus_dat_i;
                    8'h04: enc_key[63:32]   <= xbus_dat_i;
                    8'h08: enc_key[95:64]   <= xbus_dat_i;
                    8'h0C: enc_key[127:96]  <= xbus_dat_i;
                    8'h10: enc_key[159:128] <= xbus_dat_i;
                    8'h14: enc_key[191:160] <= xbus_dat_i;
                    8'h18: enc_key[223:192] <= xbus_dat_i;
                    8'h1C: enc_key[255:224] <= xbus_dat_i;
                    8'h20: begin
                        cfg_sa_en <= xbus_dat_i[1:0];
                        cfg_cmd_start <= xbus_dat_i[2];
                    end
                    8'h30: enc_spi <= xbus_dat_i;
                    8'h34: enc_salt[31:0]   <= xbus_dat_i;
                    8'h38: enc_salt[63:32]  <= xbus_dat_i;
                    8'h3C: enc_salt[95:64]  <= xbus_dat_i;
                    8'h40: enc_seq0 <= xbus_dat_i;
                    8'h44: cfg_src_ip <= xbus_dat_i;
                    8'h48: cfg_dst_ip <= xbus_dat_i;
                    8'h4C: cfg_src_port <= xbus_dat_i[15:0];
                    8'h50: cfg_dst_port <= xbus_dat_i[15:0];
                    8'h54: cfg_src_mac[47:16] <= xbus_dat_i;
                    8'h58: cfg_src_mac[15:0]  <= xbus_dat_i[15:0];
                    8'h5C: cfg_dst_mac[47:16] <= xbus_dat_i;
                    8'h60: cfg_dst_mac[15:0]  <= xbus_dat_i[15:0];
                    8'h80: dec_key[31:0]    <= xbus_dat_i;
                    8'h84: dec_key[63:32]   <= xbus_dat_i;
                    8'h88: dec_key[95:64]   <= xbus_dat_i;
                    8'h8C: dec_key[127:96]  <= xbus_dat_i;
                    8'h90: dec_key[159:128] <= xbus_dat_i;
                    8'h94: dec_key[191:160] <= xbus_dat_i;
                    8'h98: dec_key[223:192] <= xbus_dat_i;
                    8'h9C: dec_key[255:224] <= xbus_dat_i;
                    8'hA0: dec_spi <= xbus_dat_i;
                    8'hA4: dec_salt[31:0]   <= xbus_dat_i;
                    8'hA8: dec_salt[63:32]  <= xbus_dat_i;
                    8'hAC: dec_salt[95:64]  <= xbus_dat_i;
                    8'hB0: dec_seq0 <= xbus_dat_i;
                    default: xbus_err_o <= 1'b1;
                endcase
                xbus_ack_o <= 1'b1;
            end else if (xbus_active && !xbus_we_i) begin
                case (xbus_adr_i[7:0])
                    8'h00: xbus_dat_o <= enc_key[31:0];
                    8'h04: xbus_dat_o <= enc_key[63:32];
                    8'h08: xbus_dat_o <= enc_key[95:64];
                    8'h0C: xbus_dat_o <= enc_key[127:96];
                    8'h10: xbus_dat_o <= enc_key[159:128];
                    8'h14: xbus_dat_o <= enc_key[191:160];
                    8'h18: xbus_dat_o <= enc_key[223:192];
                    8'h1C: xbus_dat_o <= enc_key[255:224];
                    8'h20: xbus_dat_o <= {30'd0, cfg_sa_en};
                    8'h24: xbus_dat_o <= data_sa_active;
                    8'h28: xbus_dat_o <= data_count_tx;
                    8'h2C: xbus_dat_o <= data_count_rx;
                    8'h30: xbus_dat_o <= enc_spi;
                    8'h34: xbus_dat_o <= enc_salt[31:0];
                    8'h38: xbus_dat_o <= enc_salt[63:32];
                    8'h3C: xbus_dat_o <= enc_salt[95:64];
                    8'h40: xbus_dat_o <= enc_seq0;
                    8'h44: xbus_dat_o <= cfg_src_ip;
                    8'h48: xbus_dat_o <= cfg_dst_ip;
                    8'h4C: xbus_dat_o <= {16'd0, cfg_src_port};
                    8'h50: xbus_dat_o <= {16'd0, cfg_dst_port};
                    8'h54: xbus_dat_o <= cfg_src_mac[47:16];
                    8'h58: xbus_dat_o <= {16'd0, cfg_src_mac[15:0]};
                    8'h5C: xbus_dat_o <= cfg_dst_mac[47:16];
                    8'h60: xbus_dat_o <= {16'd0, cfg_dst_mac[15:0]};
                    8'h64: xbus_dat_o <= data_seq_out;
                    8'h80: xbus_dat_o <= dec_key[31:0];
                    8'h84: xbus_dat_o <= dec_key[63:32];
                    8'h88: xbus_dat_o <= dec_key[95:64];
                    8'h8C: xbus_dat_o <= dec_key[127:96];
                    8'h90: xbus_dat_o <= dec_key[159:128];
                    8'h94: xbus_dat_o <= dec_key[191:160];
                    8'h98: xbus_dat_o <= dec_key[223:192];
                    8'h9C: xbus_dat_o <= dec_key[255:224];
                    8'hA0: xbus_dat_o <= dec_spi;
                    8'hA4: xbus_dat_o <= dec_salt[31:0];
                    8'hA8: xbus_dat_o <= dec_salt[63:32];
                    8'hAC: xbus_dat_o <= dec_salt[95:64];
                    8'hB0: xbus_dat_o <= dec_seq0;
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