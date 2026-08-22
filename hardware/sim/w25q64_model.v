// W25Q64-style SPI flash model for XIP simulation.
// 0x03 read: cmd(8) + addr(24), then stream data while CS low.
`timescale 1ns/1ps
module w25q64_model (
    input  wire        sck,     // SPI clock (from SMC)
    input  wire        csn,     // chip select, active low (bit 0)
    input  wire        sdo,     // SPI data out (host -> flash)
    output reg         sdi      // SPI data in  (flash -> host)
);

    reg [7:0] mem [0:8388607];  // 8 MB
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
                // capture cmd byte (MSB first)
                cmd = {cmd[6:0], sdo};
            end else if (bitcnt < 32) begin
                // capture addr (24 bits)
                addr = {addr[22:0], sdo};
            end
            bitcnt = bitcnt + 1;
        end
    end

    always @(negedge sck) begin
        if (csn == 1'b0) begin
            if (bitcnt >= 32) begin
                // output data: flash[addr], MSB first
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
