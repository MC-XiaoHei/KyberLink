module gcm_arb (
    input  wire clk,
    input  wire rst_n,
    input  wire enc_req,
    input  wire dec_req,
    input  wire engine_busy,
    output wire enc_grant,
    output wire dec_grant
);
    reg held;
    reg held_enc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            held <= 1'b0;
            held_enc <= 1'b0;
        end else if (!held && !engine_busy) begin
            if (enc_req && (!dec_req || held_enc)) begin
                held <= 1'b1;
                held_enc <= 1'b1;
            end else if (dec_req && (!enc_req || !held_enc)) begin
                held <= 1'b1;
                held_enc <= 1'b0;
            end
        end else if (held && engine_busy) begin
            held <= 1'b0;
        end
    end

    assign enc_grant = held && held_enc;
    assign dec_grant = held && !held_enc;

endmodule