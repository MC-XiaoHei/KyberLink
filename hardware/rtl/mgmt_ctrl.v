module mgmt_ctrl (
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

    output wire        req_ren,
    output wire [12:0] req_raddr,
    input  wire [7:0]  req_rdata,
    input  wire        req_pending,
    output wire        req_ack,
    input  wire [12:0] req_len,

    output wire        resp_wen,
    output wire [12:0] resp_waddr,
    output wire [7:0]  resp_wdata,
    output wire        resp_done_p,
    output wire [12:0] resp_len_w,
    output wire [12:0] resp_len_o,
    input  wire        resp_ready,
    input  wire        resp_frame_done
);

    localparam S_IDLE = 2'd0;
    localparam S_RD   = 2'd1;
    localparam S_WR   = 2'd2;

    reg [1:0]  state;
    reg [2:0]  sub;
    reg [31:0] wr_word;
    reg [31:0] rd_word;
    reg [10:0] req_ptr;
    reg [10:0] resp_ptr;
    reg        cmd_req_ack;
    reg        cmd_resp_done;
    reg        resp_frame_sent;
    reg [12:0] rlen;
    reg        xbus_served;

    wire xbus_active = xbus_stb_i && xbus_cyc_i && (xbus_adr_i[31:8] == 24'hF00002);
    wire busy = (state != S_IDLE);

    reg [7:0] req_rdata_r;
    always @(posedge clk) begin
        req_rdata_r <= req_rdata;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            sub <= 3'd0;
            wr_word <= 32'd0;
            rd_word <= 32'd0;
            req_ptr <= 11'd0;
            resp_ptr <= 11'd0;
            cmd_req_ack <= 1'b0;
            cmd_resp_done <= 1'b0;
            resp_frame_sent <= 1'b0;
            rlen <= 13'd0;
            xbus_ack_o <= 1'b0;
            xbus_err_o <= 1'b0;
            xbus_dat_o <= 32'd0;
            xbus_served <= 1'b0;
        end else begin
            cmd_req_ack <= 1'b0;
            cmd_resp_done <= 1'b0;
            xbus_ack_o <= 1'b0;
            xbus_err_o <= 1'b0;
            if (!xbus_active)
                xbus_served <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (xbus_active && !busy && !xbus_served) begin
                        case (xbus_adr_i[7:0])
                            8'h00: begin
                                xbus_dat_o <= {req_pending, resp_ready, resp_frame_sent, req_len, 16'd0};
                                xbus_ack_o <= 1'b1;
                            end
                            8'h04: begin
                                if (!xbus_we_i) begin
                                    rd_word <= 32'd0;
                                    sub <= 3'd0;
                                    state <= S_RD;
                                end else begin
                                    xbus_err_o <= 1'b1;
                                    xbus_ack_o <= 1'b1;
                                end
                            end
                            8'h08: begin
                                if (xbus_we_i) begin
                                    wr_word <= xbus_dat_i;
                                    sub <= 3'd0;
                                    state <= S_WR;
                                end else begin
                                    xbus_err_o <= 1'b1;
                                    xbus_ack_o <= 1'b1;
                                end
                            end
                            8'h0C: begin
                                if (xbus_we_i) begin
                                    if (xbus_dat_i[0])
                                        cmd_req_ack <= 1'b1;
                                    if (xbus_dat_i[1])
                                        cmd_resp_done <= 1'b1;
                                    xbus_ack_o <= 1'b1;
                                end else begin
                                    xbus_err_o <= 1'b1;
                                    xbus_ack_o <= 1'b1;
                                end
                            end
                            8'h10: begin
                                if (xbus_we_i)
                                    rlen <= xbus_dat_i[12:0];
                                xbus_ack_o <= 1'b1;
                            end
                            default: begin
                                xbus_err_o <= 1'b1;
                                xbus_ack_o <= 1'b1;
                            end
                        endcase
                    end
                end
                S_RD: begin
                    if (sub < 3'd7)
                        case (sub[1:0])
                            2'd3: rd_word[31:24] <= req_rdata_r;
                            2'd0: rd_word[23:16] <= req_rdata_r;
                            2'd1: rd_word[15:8]  <= req_rdata_r;
                            2'd2: rd_word[7:0]   <= req_rdata_r;
                        endcase
                    sub <= sub + 3'd1;
                    if (sub == 3'd7) begin
                        xbus_dat_o <= rd_word;
                        xbus_ack_o <= 1'b1;
                        xbus_served <= 1'b1;
                        req_ptr <= req_ptr + 11'd1;
                        state <= S_IDLE;
                    end
                end
                S_WR: begin
                    sub <= sub + 3'd1;
                    if (sub == 3'd4) begin
                        xbus_ack_o <= 1'b1;
                        xbus_served <= 1'b1;
                        resp_ptr <= resp_ptr + 11'd1;
                        state <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
            if (cmd_req_ack)
                req_ptr <= 12'd0;
            if (cmd_resp_done)
                resp_ptr <= 11'd0;
            if (resp_frame_done)
                resp_frame_sent <= 1'b1;
            else if (cmd_resp_done)
                resp_frame_sent <= 1'b0;
        end
    end

    assign req_ren = (state == S_RD) && (sub < 3'd4);
    assign req_raddr = {req_ptr, sub[1:0]};
    assign resp_wen = (state == S_WR) && (sub < 3'd4);
    assign resp_waddr = {resp_ptr, sub[1:0]};
    assign resp_wdata = (sub[1:0] == 2'd0) ? wr_word[31:24] :
                        (sub[1:0] == 2'd1) ? wr_word[23:16] :
                        (sub[1:0] == 2'd2) ? wr_word[15:8] : wr_word[7:0];
    assign req_ack = cmd_req_ack;
    assign resp_done_p = cmd_resp_done;
    assign resp_len_w = rlen;
    assign resp_len_o = rlen;

endmodule