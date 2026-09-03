module DPB (DOA, DOB, DIA, DIB, BLKSELA, BLKSELB, ADA, ADB, WREA, WREB, CLKA, CLKB, CEA, CEB, OCEA, OCEB, RESETA, RESETB);
parameter READ_MODE0 = 1'b0;
parameter READ_MODE1 = 1'b0;
parameter WRITE_MODE0 = 2'b00;
parameter WRITE_MODE1 = 2'b00;
parameter BIT_WIDTH_0 = 16;
parameter BIT_WIDTH_1 = 16;
parameter BLK_SEL_0 = 3'b000;
parameter BLK_SEL_1 = 3'b000;
parameter RESET_MODE = "SYNC";
parameter INIT_RAM_00 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_01 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_02 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_03 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_04 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_05 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_06 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_07 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_08 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_09 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_0A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_0B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_0C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_0D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_0E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_0F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_10 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_11 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_12 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_13 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_14 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_15 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_16 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_17 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_18 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_19 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_1A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_1B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_1C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_1D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_1E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_1F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_20 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_21 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_22 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_23 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_24 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_25 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_26 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_27 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_28 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_29 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_2A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_2B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_2C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_2D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_2E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_2F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_30 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_31 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_32 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_33 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_34 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_35 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_36 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_37 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_38 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_39 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_3A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_3B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_3C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_3D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_3E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_RAM_3F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
input CLKA, CEA, CLKB, CEB;
input OCEA, OCEB;
input RESETA, RESETB;
input WREA, WREB;
input [13:0] ADA, ADB;
input [2:0] BLKSELA, BLKSELB;
input [15:0] DIA, DIB;
output [15:0] DOA, DOB;
reg [15:0] bpa_reg,bpa_reg_async,bpa_reg_sync;
reg [15:0] pla_reg,pla_reg_async,pla_reg_sync;
reg [15:0] bpb_reg, plb_reg,bpb_reg_async,bpb_reg_sync,plb_reg_async,plb_reg_sync;
reg [16383:0] ram_MEM = {INIT_RAM_3F, INIT_RAM_3E, INIT_RAM_3D, INIT_RAM_3C,INIT_RAM_3B, INIT_RAM_3A, INIT_RAM_39, INIT_RAM_38,INIT_RAM_37, INIT_RAM_36, INIT_RAM_35, INIT_RAM_34,INIT_RAM_33, INIT_RAM_32, INIT_RAM_31, INIT_RAM_30,INIT_RAM_2F, INIT_RAM_2E, INIT_RAM_2D, INIT_RAM_2C,INIT_RAM_2B, INIT_RAM_2A, INIT_RAM_29, INIT_RAM_28,INIT_RAM_27, INIT_RAM_26, INIT_RAM_25, INIT_RAM_24,INIT_RAM_23, INIT_RAM_22, INIT_RAM_21, INIT_RAM_20,INIT_RAM_1F, INIT_RAM_1E, INIT_RAM_1D, INIT_RAM_1C,INIT_RAM_1B, INIT_RAM_1A, INIT_RAM_19, INIT_RAM_18,INIT_RAM_17, INIT_RAM_16, INIT_RAM_15, INIT_RAM_14,INIT_RAM_13, INIT_RAM_12, INIT_RAM_11, INIT_RAM_10,INIT_RAM_0F, INIT_RAM_0E, INIT_RAM_0D, INIT_RAM_0C, INIT_RAM_0B, INIT_RAM_0A, INIT_RAM_09, INIT_RAM_08,INIT_RAM_07, INIT_RAM_06, INIT_RAM_05, INIT_RAM_04,INIT_RAM_03, INIT_RAM_02, INIT_RAM_01, INIT_RAM_00} ;
reg [BIT_WIDTH_0-1:0] mem_a;
reg [BIT_WIDTH_1-1:0] mem_b;
reg mc,bs_ena,bs_enb;
wire pcea,pceb;
reg [13:0] addr_a, addr_b;
integer bit_width_d0 = BIT_WIDTH_0;
integer bit_width_d1 = BIT_WIDTH_1;
integer bit_width_a0, bit_width_a1;
wire grstn = 1'b1;
initial begin
    bpa_reg = 0;
    pla_reg = 0;
    bpb_reg = 0;
    plb_reg = 0;
    bpa_reg_async = 0;
    bpa_reg_sync = 0;
    pla_reg_async = 0;
    pla_reg_sync = 0;
    bpb_reg_async = 0;
    bpb_reg_sync = 0;
    plb_reg_async = 0;
    plb_reg_sync = 0;
    mc = 1'b0;
end
initial begin
    case(bit_width_d0)
        1: bit_width_a0 = 14;
        2: bit_width_a0 = 13;
        4: bit_width_a0 = 12;
        8: bit_width_a0 = 11;
        16: bit_width_a0 = 10;
    default: begin
    end
    endcase
    case(bit_width_d1)
        1: bit_width_a1 = 14;
        2: bit_width_a1 = 13;
        4: bit_width_a1 = 12;
        8: bit_width_a1 = 11;
        16: bit_width_a1 = 10;
    default: begin
    end
    endcase
end
assign DOA = (READ_MODE0 == 1'b0)? bpa_reg : pla_reg;
assign DOB = (READ_MODE1 == 1'b0)? bpb_reg : plb_reg;
assign pcea = CEA && bs_ena && grstn;
assign pceb = CEB && bs_enb && grstn;
always @ (BLKSELA, BLKSELB)
begin
    if(BLKSELA == BLK_SEL_0) begin
        bs_ena = 1;
    end else begin
        bs_ena = 0;
    end
    if(BLKSELB == BLK_SEL_1) begin
        bs_enb = 1;
    end else begin
        bs_enb = 0;
    end
end
always@(ADA,ADB,bit_width_a0,bit_width_a1,WREA,WREB,mc)begin
    if(bit_width_a0==14)begin
        addr_a[13:0] = ADA[13:0];
        mem_a[0]=ram_MEM[addr_a];
    end
    else if(bit_width_a0==13)begin
        addr_a[13:0] = {ADA[13:1],1'b0};
        mem_a[1:0]={ ram_MEM[addr_a+1],ram_MEM[addr_a]};
    end
    else if(bit_width_a0==12)begin
        addr_a[13:0] = {ADA[13:2],2'b00};
        mem_a[3:0]={ ram_MEM[addr_a+3],ram_MEM[addr_a+2],ram_MEM[addr_a+1],ram_MEM[addr_a]};
    end
    else if(bit_width_a0==11)begin
        addr_a[13:0] = {ADA[13:3],3'b000};
        mem_a[7:0]={ ram_MEM[addr_a+7],ram_MEM[addr_a+6],ram_MEM[addr_a+5],ram_MEM[addr_a+4],ram_MEM[addr_a+3],ram_MEM[addr_a+2],ram_MEM[addr_a+1],ram_MEM[addr_a]};
    end
    else if(bit_width_a0==10)begin
        addr_a[13:0] = {ADA[13:4],4'b0000};
        mem_a[15:0]={ram_MEM[addr_a+15],ram_MEM[addr_a+14],ram_MEM[addr_a+13],ram_MEM[addr_a+12],ram_MEM[addr_a+11],ram_MEM[addr_a+10],ram_MEM[addr_a+9],ram_MEM[addr_a+8],ram_MEM[addr_a+7],ram_MEM[addr_a+6],ram_MEM[addr_a+5],ram_MEM[addr_a+4],ram_MEM[addr_a+3],ram_MEM[addr_a+2],ram_MEM[addr_a+1],ram_MEM[addr_a]};
    end
    if(bit_width_a1==14)begin
        addr_b[13:0] = ADB[13:0];
        mem_b[0]=ram_MEM[addr_b];
    end
    else if(bit_width_a1==13)begin
        addr_b[13:0] = {ADB[13:1],1'b0};
        mem_b[1:0]={ram_MEM[addr_b+1],ram_MEM[addr_b]};
    end
    else if(bit_width_a1==12)begin
        addr_b[13:0] = {ADB[13:2],2'b00};
        mem_b[3:0]={ ram_MEM[addr_b+3],ram_MEM[addr_b+2],ram_MEM[addr_b+1],ram_MEM[addr_b]};
    end
    else if(bit_width_a1==11)begin
        addr_b[13:0] = {ADB[13:3],3'b000};
        mem_b[7:0]={ ram_MEM[addr_b+7],ram_MEM[addr_b+6],ram_MEM[addr_b+5],ram_MEM[addr_b+4],ram_MEM[addr_b+3],ram_MEM[addr_b+2],ram_MEM[addr_b+1],ram_MEM[addr_b]};
    end
    else if(bit_width_a1==10)begin
        addr_b[13:0] = {ADB[13:4],4'b0000};
        mem_b[15:0]={ram_MEM[addr_b+15],ram_MEM[addr_b+14],ram_MEM[addr_b+13],ram_MEM[addr_b+12],ram_MEM[addr_b+11],ram_MEM[addr_b+10],ram_MEM[addr_b+9],ram_MEM[addr_b+8],ram_MEM[addr_b+7],ram_MEM[addr_b+6],ram_MEM[addr_b+5],ram_MEM[addr_b+4],ram_MEM[addr_b+3],ram_MEM[addr_b+2],ram_MEM[addr_b+1],ram_MEM[addr_b]};
    end
end
always @ (bpa_reg_async or bpa_reg_sync or pla_reg_async or pla_reg_sync or bpb_reg_async or bpb_reg_sync or plb_reg_async or plb_reg_sync) begin
    if(RESET_MODE == "ASYNC") begin
        bpa_reg <= bpa_reg_async;
        pla_reg <= pla_reg_async;
        bpb_reg <= bpb_reg_async;
        plb_reg <= plb_reg_async;
    end
    else begin
        bpa_reg <= bpa_reg_sync;
        pla_reg <= pla_reg_sync;
        bpb_reg <= bpb_reg_sync;
        plb_reg <= plb_reg_sync;
    end
end
always @(posedge CLKA) begin
    if (pcea) begin
        if (WREA) begin
            if(bit_width_d0==1)
                ram_MEM[addr_a] <= DIA[0];
            else if(bit_width_d0==2)
                {ram_MEM[addr_a+1],ram_MEM[addr_a]}<=DIA[BIT_WIDTH_0-1:0];
            else if(bit_width_d0==4)
                {ram_MEM[addr_a+3],ram_MEM[addr_a+2],ram_MEM[addr_a+1],ram_MEM[addr_a]}<=DIA[BIT_WIDTH_0-1:0];
            else if(bit_width_d0==8)
                {ram_MEM[addr_a+7],ram_MEM[addr_a+6],ram_MEM[addr_a+5],ram_MEM[addr_a+4],ram_MEM[addr_a+3],ram_MEM[addr_a+2],ram_MEM[addr_a+1],ram_MEM[addr_a]}<=DIA[BIT_WIDTH_0-1:0];
            else if(bit_width_d0==16) begin
                if(ADA[0] == 1'b1)
                    {ram_MEM[addr_a+7],ram_MEM[addr_a+6],ram_MEM[addr_a+5],ram_MEM[addr_a+4],ram_MEM[addr_a+3],ram_MEM[addr_a+2],ram_MEM[addr_a+1],ram_MEM[addr_a]} <= DIA[7:0];
                if(ADA[1] == 1'b1)
                    {ram_MEM[addr_a+15],ram_MEM[addr_a+14],ram_MEM[addr_a+13],ram_MEM[addr_a+12],ram_MEM[addr_a+11],ram_MEM[addr_a+10],ram_MEM[addr_a+9],ram_MEM[addr_a+8]} <= DIA[15:8];
            end
            mc <= ~mc;
        end
    end
end
always @(posedge CLKA or posedge RESETA or negedge grstn) begin
    if (!grstn) begin
        pla_reg_async <= 0;
        bpa_reg_async <= 0;
    end else if (RESETA) begin
        pla_reg_async <= 0;
        bpa_reg_async <= 0;
    end else begin
        if(OCEA) begin
            pla_reg_async <= bpa_reg;
        end
        if (pcea) begin
            if (WREA) begin
                if (WRITE_MODE0 == 2'b01) begin
                    bpa_reg_async[BIT_WIDTH_0-1:0] <= mem_a[BIT_WIDTH_0-1:0];
                    if(bit_width_d0<=8)
                        bpa_reg_async[BIT_WIDTH_0-1:0] <= DIA[BIT_WIDTH_0-1:0];
                    else if(bit_width_d0==16) begin
                        if(ADA[0] == 1'b1)
                            bpa_reg_async[7:0] <= DIA[7:0];
                        if(ADA[1] == 1'b1)
                            bpa_reg_async[15:8]  <= DIA[15:8];
                    end
                end
                if (WRITE_MODE0 == 2'b10) begin
                    bpa_reg_async[BIT_WIDTH_0-1:0] <= mem_a[BIT_WIDTH_0-1:0];
                end
            end
            else begin
                bpa_reg_async[BIT_WIDTH_0-1:0] <= mem_a[BIT_WIDTH_0-1:0];
            end
        end
    end
end
always @(posedge CLKA or negedge grstn) begin
    if (!grstn) begin
        pla_reg_sync <= 0;
        bpa_reg_sync <= 0;
    end else if (RESETA) begin
        pla_reg_sync <= 0;
        bpa_reg_sync <= 0;
    end else begin
        if(OCEA) begin
            pla_reg_sync <= bpa_reg;
        end
        if (pcea) begin
            if (WREA) begin
                if (WRITE_MODE0 == 2'b01) begin
                    bpa_reg_sync[BIT_WIDTH_0-1:0] <= mem_a[BIT_WIDTH_0-1:0];
                    if(bit_width_d0<=8)
                        bpa_reg_sync[BIT_WIDTH_0-1:0] <= DIA[BIT_WIDTH_0-1:0];
                    else if(bit_width_d0==16) begin
                        if(ADA[0] == 1'b1)
                            bpa_reg_sync[7:0] <= DIA[7:0];
                        if(ADA[1] == 1'b1)
                            bpa_reg_sync[15:8]  <= DIA[15:8];
                    end
                end
                if (WRITE_MODE0 == 2'b10) begin
                    bpa_reg_sync[BIT_WIDTH_0-1:0] <= mem_a[BIT_WIDTH_0-1:0];
                end
            end
            else begin
                bpa_reg_sync[BIT_WIDTH_0-1:0] <= mem_a[BIT_WIDTH_0-1:0];
            end
        end
    end
end
always @(posedge CLKB) begin
    if (pceb) begin
        if (WREB) begin
            if(bit_width_d1==1)
                ram_MEM[addr_b] <= DIB[0];
            else if(bit_width_d1==2)
                {ram_MEM[addr_b+1],ram_MEM[addr_b]}<=DIB[BIT_WIDTH_1-1:0];
            else if(bit_width_d1==4)
                {ram_MEM[addr_b+3],ram_MEM[addr_b+2],ram_MEM[addr_b+1],ram_MEM[addr_b]}<=DIB[BIT_WIDTH_1-1:0];
            else if(bit_width_d1==8)
                {ram_MEM[addr_b+7],ram_MEM[addr_b+6],ram_MEM[addr_b+5],ram_MEM[addr_b+4],ram_MEM[addr_b+3],ram_MEM[addr_b+2],ram_MEM[addr_b+1],ram_MEM[addr_b]}<=DIB[BIT_WIDTH_1-1:0];
            else if(bit_width_d1==16) begin
                if(ADB[0] == 1'b1)
                    {ram_MEM[addr_b+7],ram_MEM[addr_b+6],ram_MEM[addr_b+5],ram_MEM[addr_b+4],ram_MEM[addr_b+3],ram_MEM[addr_b+2],ram_MEM[addr_b+1],ram_MEM[addr_b]} <= DIB[7:0];
                if(ADB[1] == 1'b1)
                    {ram_MEM[addr_b+15],ram_MEM[addr_b+14],ram_MEM[addr_b+13],ram_MEM[addr_b+12],ram_MEM[addr_b+11],ram_MEM[addr_b+10],ram_MEM[addr_b+9],ram_MEM[addr_b+8]} <= DIB[15:8];
            end
            mc <= ~mc;
        end
    end
end
always @(posedge CLKB or posedge RESETB or negedge grstn) begin
    if (!grstn) begin
        plb_reg_async <= 0;
        bpb_reg_async <= 0;
    end else if (RESETB) begin
        plb_reg_async <= 0;
        bpb_reg_async <= 0;
    end else begin
        if(OCEB) begin
            plb_reg_async <= bpb_reg;
        end
        if (pceb) begin
            if (WREB) begin
                if (WRITE_MODE1 == 2'b01) begin
                    bpb_reg_async[BIT_WIDTH_1-1:0] <= mem_b[BIT_WIDTH_1-1:0];
                    if(bit_width_d1<=8)
                        bpb_reg_async[BIT_WIDTH_1-1:0] <= DIB[BIT_WIDTH_1-1:0];
                    else if(bit_width_d1==16) begin
                        if(ADB[0] == 1'b1)
                            bpb_reg_async[7:0] <= DIB[7:0];
                        if(ADB[1] == 1'b1)
                            bpb_reg_async[15:8]  <= DIB[15:8];
                    end
                end
                if (WRITE_MODE1 == 2'b10) begin
                    bpb_reg_async[BIT_WIDTH_1-1:0] <= mem_b[BIT_WIDTH_1-1:0];
                end
            end else begin
                bpb_reg_async[BIT_WIDTH_1-1:0] <= mem_b[BIT_WIDTH_1-1:0];
            end
        end
    end
end
always @(posedge CLKB or negedge grstn) begin
    if (!grstn) begin
        plb_reg_sync <= 0;
        bpb_reg_sync <= 0;
    end else if (RESETB) begin
        plb_reg_sync <= 0;
        bpb_reg_sync <= 0;
    end else begin
        if(OCEB) begin
            plb_reg_sync <= bpb_reg;
        end
        if (pceb) begin
            if (WREB) begin
                if (WRITE_MODE1 == 2'b01) begin
                    bpb_reg_sync[BIT_WIDTH_1-1:0] <= mem_b[BIT_WIDTH_1-1:0];
                    if(bit_width_d1<=8)
                        bpb_reg_sync[BIT_WIDTH_1-1:0] <= DIB[BIT_WIDTH_1-1:0];
                    else if(bit_width_d1==16) begin
                        if(ADB[0] == 1'b1)
                            bpb_reg_sync[7:0] <= DIB[7:0];
                        if(ADB[1] == 1'b1)
                            bpb_reg_sync[15:8]  <= DIB[15:8];
                    end
                end
                if (WRITE_MODE1 == 2'b10) begin
                    bpb_reg_sync[BIT_WIDTH_1-1:0] <= mem_b[BIT_WIDTH_1-1:0];
                end
            end else begin
                bpb_reg_sync[BIT_WIDTH_1-1:0] <= mem_b[BIT_WIDTH_1-1:0];
            end
        end
    end
end
endmodule
