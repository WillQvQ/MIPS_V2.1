`timescale 1ns / 1ps

module mips#(parameter N = 64)(
    input   logic       clk, reset,
    output  logic[N-1:0]dataadr, writedata,
    output  logic [1:0] memwrite,
    output  logic       dword,
    input   logic[N-1:0]readdata,
    output  logic [7:0] pclow,
    output  logic [4:0] state,
    input   logic [4:0] checka,
    output  logic [N-1:0]check
);
    logic       pcen, irwrite, iord, lbu;
    logic       memtoreg, regdst, regwrite, zero;
    logic       alusrca;    
    logic [2:0] alusrcb;    
    logic [3:0] alucontrol;
    logic [1:0] pcsrc;
    logic [2:0] readtype;         
    logic [5:0] op, funct;
    assign dword = readtype[2];
    controller controller(clk, reset, op, funct, zero,
                        pcen, memwrite, irwrite, regwrite,
                        iord, memtoreg, regdst, alusrca,
                        alusrcb, pcsrc, alucontrol, readtype, state);
    datapath datapath(clk, reset, pcen, irwrite, regwrite,
                    iord, memtoreg, regdst, alusrca, alusrcb, 
                    pcsrc, alucontrol, readtype, op, funct,
                    zero, dataadr, writedata, readdata, pclow,
                    checka,check);
endmodule