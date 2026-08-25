`timescale 1ns/1ps
module w25q64_model (
    input  wire        sck,
    input  wire        csn,
    input  wire        sdo,
    output reg         sdi
);

    reg [7:0] mem [0:8388607];
    integer bitcnt;
    reg [7:0] cmd;
    reg [23:0] addr;
    reg [7:0] curbyte;
    integer bitpos;

    initial begin
        sdi = 1'b1;
        bitcnt = 0;
        bitpos = 0;
    end

    always @(posedge sck) begin
        if (csn == 1'b0) begin
            if (bitcnt < 8) begin
                cmd = {cmd[6:0], sdo};
            end else if (bitcnt < 32) begin
                addr = {addr[22:0], sdo};
            end
            bitcnt = bitcnt + 1;
        end
    end

    always @(negedge sck) begin
        if (csn == 1'b0) begin
            if (bitcnt >= 32) begin
                if (bitpos == 0) begin
                    curbyte = mem[addr[22:0]];
                end
                sdi = curbyte[7 - bitpos];
                bitpos = bitpos + 1;
                if (bitpos == 8) begin
                    bitpos = 0;
                    addr = addr + 1;
                end
            end
        end
    end

    always @(negedge csn) begin
        bitcnt = 0;
        bitpos = 0;
    end

endmodule
