module axis_pipe1 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  s_tdata,
    input  wire        s_tvalid,
    input  wire        s_tlast,
    output wire        s_tready,
    output wire [7:0]  m_tdata,
    output wire        m_tvalid,
    output wire        m_tlast,
    input  wire        m_tready
);

    reg [7:0] d;
    reg       v;
    reg       l;

    assign s_tready = !v;
    assign m_tdata = d;
    assign m_tvalid = v;
    assign m_tlast = l;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d <= 8'd0;
            v <= 1'b0;
            l <= 1'b0;
        end else begin
            if (m_tready) begin
                v <= 1'b0;
            end
            if (s_tvalid && s_tready) begin
                d <= s_tdata;
                l <= s_tlast;
                v <= 1'b1;
            end
        end
    end

endmodule
