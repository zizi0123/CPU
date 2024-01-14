module Decoder #(
    parameter ADDR_WIDTH = 32,
    parameter REG_WIDTH = 5,
    parameter lui = 7'd1,
    parameter auipc = 7'd2,
    parameter jal = 7'd3,
    parameter jalr = 7'd4,
    parameter beq = 7'd5,
    parameter bne = 7'd6,
    parameter blt = 7'd7,
    parameter bge = 7'd8,
    parameter bltu = 7'd9,
    parameter bgeu = 7'd10,
    parameter lb = 7'd11,
    parameter lh = 7'd12,
    parameter lw = 7'd13,
    parameter lbu = 7'd14,
    parameter lhu = 7'd15,
    parameter sb = 7'd16,
    parameter sh = 7'd17,
    parameter sw = 7'd18,
    parameter addi = 7'd19,
    parameter slti = 7'd20,
    parameter sltiu = 7'd21,
    parameter xori = 7'd22,
    parameter ori = 7'd23,
    parameter andi = 7'd24,
    parameter slli = 7'd25,
    parameter srli = 7'd26,
    parameter srai = 7'd27,
    parameter add = 7'd28,
    parameter sub = 7'd29,
    parameter sll = 7'd30,
    parameter slt = 7'd31,
    parameter sltu = 7'd32,
    parameter xorr = 7'd33,
    parameter srl = 7'd34,
    parameter sra = 7'd35,
    parameter orr = 7'd36,
    parameter andd = 7'd37
) (
    //instruction fetcher
    input wire IFDC_en,
    input wire [ADDR_WIDTH - 1:0] IFDC_pc,
    input wire [6:0] IFDC_opcode,
    input wire [31:7] IFDC_remain_inst,
    input wire IFDC_predict_result,  //0: not taken, 1: taken
    output wire DCIF_ask_IF,  //ask IF to fetch a new instruction

    //dispatcher
    input wire DPDC_ask_IF,  //ask IF to fetch a new instruction
    output wire DCDP_en,
    output wire [ADDR_WIDTH - 1:0] DCDP_pc,
    output wire [6:0] DCDP_opcode,
    output wire [REG_WIDTH - 1:0] DCDP_rs1,
    output wire [REG_WIDTH - 1:0] DCDP_rs2,
    output wire [REG_WIDTH - 1:0] DCDP_rd,
    output wire [31:0] DCDP_imm,
    output wire DCDP_predict_result  //0: not taken, 1: taken
);

  assign DCDP_en = IFDC_en;
  assign DCDP_pc = IFDC_pc;
  assign DCDP_predict_result = IFDC_predict_result;
  assign DCDP_opcode = (IFDC_opcode == 7'b0110111) ? lui :
                         (IFDC_opcode == 7'b0010111) ? auipc :
                         (IFDC_opcode == 7'b1101111) ? jal :  
                         (IFDC_opcode == 7'b1100111) ? jalr :   
                         (IFDC_opcode == 7'b1100011) ? ((IFDC_remain_inst[14:12] == 3'b000) ? beq :
                                                        (IFDC_remain_inst[14:12] == 3'b001) ? bne :
                                                        (IFDC_remain_inst[14:12] == 3'b100) ? blt :
                                                        (IFDC_remain_inst[14:12] == 3'b101) ? bge :
                                                        (IFDC_remain_inst[14:12] == 3'b110) ? bltu :
                                                        bgeu) :
                         (IFDC_opcode == 7'b0000011) ? ((IFDC_remain_inst[14:12] == 3'b000) ? lb :
                                                        (IFDC_remain_inst[14:12] == 3'b001) ? lh :
                                                        (IFDC_remain_inst[14:12] == 3'b010) ? lw :
                                                        (IFDC_remain_inst[14:12] == 3'b100) ? lbu :
                                                        lhu) : 
                         (IFDC_opcode == 7'b0100011) ? ((IFDC_remain_inst[14:12] == 3'b000) ? sb : 
                                                        (IFDC_remain_inst[14:12] == 3'b001) ? sh :
                                                        sw) :
                         (IFDC_opcode == 7'b0010011) ? ((IFDC_remain_inst[14:12] == 3'b000) ? addi :
                                                        (IFDC_remain_inst[14:12] == 3'b010) ? slti :
                                                        (IFDC_remain_inst[14:12] == 3'b011) ? sltiu :
                                                        (IFDC_remain_inst[14:12] == 3'b100) ? xori :
                                                        (IFDC_remain_inst[14:12] == 3'b110) ? ori :
                                                        (IFDC_remain_inst[14:12] == 3'b111) ? andi :
                                                        (IFDC_remain_inst[14:12] == 3'b001) ? slli :
                                                        (IFDC_remain_inst[14:12] == 3'b101 && IFDC_remain_inst[30]) ? srai :
                                                        srli) :
                         (IFDC_opcode == 7'b0110011) ? ((IFDC_remain_inst[14:12] == 3'b000 && !IFDC_remain_inst[30]) ? add :
                                                        (IFDC_remain_inst[14:12] == 3'b000 && IFDC_remain_inst[30]) ? sub :
                                                        (IFDC_remain_inst[14:12] == 3'b001) ? sll :
                                                        (IFDC_remain_inst[14:12] == 3'b010) ? slt :
                                                        (IFDC_remain_inst[14:12] == 3'b011) ? sltu :
                                                        (IFDC_remain_inst[14:12] == 3'b100) ? xorr :
                                                        (IFDC_remain_inst[14:12] == 3'b101 && !IFDC_remain_inst[30]) ? srl :
                                                        (IFDC_remain_inst[14:12] == 3'b101 && IFDC_remain_inst[30]) ? sra :
                                                        (IFDC_remain_inst[14:12] == 3'b110) ? orr :
                                                        andd) : 7'b0;

  assign DCDP_rs1 = IFDC_remain_inst[19:15];
  assign DCDP_rs2 = IFDC_remain_inst[24:20];
  assign DCDP_rd = IFDC_remain_inst[11:7];
  assign DCDP_imm = (DCDP_opcode == lui || DCDP_opcode == auipc) ? {IFDC_remain_inst[31:12],12'b0} :
                      (DCDP_opcode == jal) ? {{12{IFDC_remain_inst[31]}}, IFDC_remain_inst[19:12], IFDC_remain_inst[20], IFDC_remain_inst[30:21],1'b0} :
                      (DCDP_opcode == jalr) ? {{21{IFDC_remain_inst[31]}},IFDC_remain_inst[30:20]} :
                      (DCDP_opcode == beq || DCDP_opcode == bne || DCDP_opcode == blt || DCDP_opcode == bge || DCDP_opcode == bltu || DCDP_opcode == bgeu) ? {{20{IFDC_remain_inst[31]}}, IFDC_remain_inst[7], IFDC_remain_inst[30:25], IFDC_remain_inst[11:8], 1'b0} :
                      (DCDP_opcode == lb || DCDP_opcode == lh || DCDP_opcode == lw || DCDP_opcode == lbu || DCDP_opcode == lhu) ? {{21{IFDC_remain_inst[31]}},IFDC_remain_inst[30:20]} :
                      (DCDP_opcode == sb || DCDP_opcode == sh || DCDP_opcode == sw) ? {{21{IFDC_remain_inst[31]}},IFDC_remain_inst[30:25], IFDC_remain_inst[11:7]} :
                      (DCDP_opcode == addi || DCDP_opcode == slti || DCDP_opcode == sltiu || DCDP_opcode == xori || DCDP_opcode == ori || DCDP_opcode == andi ) ? {{21{IFDC_remain_inst[31]}},IFDC_remain_inst[30:20]} :
                      (DCDP_opcode == slli || DCDP_opcode == srli || DCDP_opcode == srai) ? {{27'b0},IFDC_remain_inst[24:20]} :
                      32'b0;
  assign DCIF_ask_IF = DPDC_ask_IF;

endmodule
