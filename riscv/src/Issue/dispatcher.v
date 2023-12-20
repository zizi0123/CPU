module Dispatcher (
    //sys
    input wire Sys_clk,
    input wire Sys_rst,
    input wire Sys_rdy,

    //Decoder
    input wire DCDP_en,
    input wire [ADDR_WIDTH - 1:0] DCDP_pc,
    input wire [6:0] DCDP_opcode,
    input wire [REG_WIDTH - 1:0] DCDP_rs1,
    input wire [REG_WIDTH - 1:0] DCDP_rs2,
    input wire [REG_WIDTH - 1:0] DCDP_rd,
    input wire [31:0] DCDP_imm,
    input wire DCDP_predict_result,  //0: not taken, 1: taken
    output reg DPDC_ask_IF,  //ask IF to fetch a new instruction

    //Register File
    input wire [EX_RoB_WIDTH - 1:0] RFDP_Qj,
    input wire [EX_RoB_WIDTH - 1:0] RFDP_Qk,
    input wire [31:0] RFDP_Vj,
    input wire [31:0] RFDP_Vk,
    output reg DPRF_en,  //attention rd to regfile is ready
    output wire [EX_REG_WIDTH - 1:0] DPRF_rs1,
    output wire [EX_REG_WIDTH - 1:0] DPRF_rs2,
    output wire [RoB_WIDTH - 1:0] DPRF_RoB_index,  //the dependency RoB# of rd
    output wire [EX_REG_WIDTH - 1:0] DPRF_rd,

    //Reservation Station
    input wire RSDP_full,
    output reg DPRS_en,  //send a new instruction to RS
    output wire [ADDR_WIDTH - 1:0] DPRS_pc,
    output wire [EX_RoB_WIDTH - 1:0] DPRS_Qj,
    output wire [EX_RoB_WIDTH - 1:0] DPRS_Qk,
    output wire [31:0] DPRS_Vj,
    output wire [31:0] DPRS_Vk,
    output wire [31:0] DPRS_imm,
    output wire [6:0] DPRS_opcode,
    output wire [RoB_WIDTH - 1:0] DPRS_RoB_index,

    //Load Store Buffer
    input wire LSBDP_full,
    output reg DPLSB_en,  //send a new instruction to LSB
    output wire [EX_RoB_WIDTH - 1:0] DPLSB_Qj,
    output wire [EX_RoB_WIDTH - 1:0] DPLSB_Qk,
    output wire [31:0] DPLSB_Vj,
    output wire [31:0] DPLSB_Vk,
    output wire [31:0] DPLSB_imm,
    output wire [6:0] DPLSB_opcode,
    output wire [RoB_WIDTH - 1:0] DPLSB_RoB_index,

    //Reorder Buffer 
    input wire RoBDP_full,
    input wire [RoB_WIDTH - 1:0] RoBDP_RoB_index,
    input wire RoBDP_Qj_ready,  //RoB item Qj is ready in RoB
    input wire RoBDP_Qk_ready,  //RoB item Qk is ready in RoB
    input wire [31:0] RoBDP_Vj,
    input wire [31:0] RoBDP_Vk,
    input wire RoBDP_pre_judge,  //0:mispredict 1:correct
    output wire [EX_RoB_WIDTH - 1:0] DPRoB_Qj,  //prefetch:ask if Qj is ready in RoB
    output wire [EX_RoB_WIDTH - 1:0] DPRoB_Qk,  //prefetch:ask if Qk is ready in RoB
    output reg DPRoB_en,  //send a new instruction to RoB
    output wire [ADDR_WIDTH - 1:0] DPRoB_pc,
    output wire [31:0] DPRoB_imm,
    output wire DPRoB_predict_result,
    output wire [6:0] DPRoB_opcode,
    output wire [EX_REG_WIDTH - 1:0] DPRoB_rd,

    //CDB
    input wire CDBDP_RS_en,
    input wire [RoB_WIDTH - 1:0] CDBDP_RS_RoB_index,
    input wire [31:0] CDBDP_RS_value,
    input wire CDBDP_LSB_en,
    input wire [RoB_WIDTH - 1:0] CDBDP_LSB_RoB_index,
    input wire [31:0] CDBDP_LSB_value

);
  parameter ADDR_WIDTH = 32;
  parameter REG_WIDTH = 5;
  parameter EX_REG_WIDTH = 6;  //extra one bit for empty reg
  parameter NON_REG = 6'b100000;
  parameter RoB_WIDTH = 8;
  parameter EX_RoB_WIDTH = 9;
  parameter NON_DEP = 9'b100000000;  //no dependency
  parameter IDLE = 0, WAITING_INS = 1;


  parameter lui = 7'd1;
  parameter auipc = 7'd2;
  parameter jal = 7'd3;
  parameter jalr = 7'd4;
  parameter beq = 7'd5;
  parameter bne = 7'd6;
  parameter blt = 7'd7;
  parameter bge = 7'd8;
  parameter bltu = 7'd9;
  parameter bgeu = 7'd10;
  parameter lb = 7'd11;
  parameter lh = 7'd12;
  parameter lw = 7'd13;
  parameter lbu = 7'd14;
  parameter lhu = 7'd15;
  parameter sb = 7'd16;
  parameter sh = 7'd17;
  parameter sw = 7'd18;
  parameter addi = 7'd19;
  parameter slti = 7'd20;
  parameter sltiu = 7'd21;
  parameter xori = 7'd22;
  parameter ori = 7'd23;
  parameter andi = 7'd24;
  parameter slli = 7'd25;
  parameter srli = 7'd26;
  parameter srai = 7'd27;
  parameter add = 7'd28;
  parameter sub = 7'd29;
  parameter sll = 7'd30;
  parameter slt = 7'd31;
  parameter sltu = 7'd32;
  parameter xorr = 7'd33;
  parameter srl = 7'd34;
  parameter sra = 7'd35;
  parameter orr = 7'd36;
  parameter andd = 7'd37;

  //RF
  assign DPRF_rs1 = (DCDP_opcode == lui || DCDP_opcode == auipc || DCDP_opcode == jal) ? NON_REG : DCDP_rs1;
  assign DPRF_rs2 = (DCDP_opcode == lui || DCDP_opcode == auipc || DCDP_opcode == jal ||
                       DCDP_opcode == lb || DCDP_opcode == lh || DCDP_opcode == lw || DCDP_opcode == lbu || DCDP_opcode == lhu ||
                       DCDP_opcode == addi || DCDP_opcode == slti || DCDP_opcode == sltiu || DCDP_opcode == xori || DCDP_opcode == ori || DCDP_opcode == andi ||
                       DCDP_opcode == slli || DCDP_opcode == srli || DCDP_opcode == srai) ? NON_REG : DCDP_rs2;
  assign DPRF_rd = (DCDP_opcode == beq || DCDP_opcode == bne || DCDP_opcode == blt || DCDP_opcode == bge || DCDP_opcode == bltu || DCDP_opcode == bgeu || DCDP_opcode == sb || DCDP_opcode == sh || DCDP_opcode == sw) ? NON_REG : DCDP_rd;
  assign DPRF_RoB_index = RoBDP_RoB_index;
  //RoB
  assign DPRoB_Qj = RFDP_Qj;
  assign DPRoB_Qk = RFDP_Qk;
  assign DPRoB_pc = DCDP_pc;
  assign DPRoB_imm = DCDP_imm;
  assign DPRoB_predict_result = DCDP_predict_result;
  assign DPRoB_opcode = DCDP_opcode;
  assign DPRoB_rd = DPRF_rd;
  //RS
  assign DPRS_RoB_index = RoBDP_RoB_index;
  assign DPRS_pc = DCDP_pc;
  assign DPRS_Qj = Qj;
  assign DPRS_Qk = Qk;
  assign DPRS_Vj = Vj;
  assign DPRS_VK = Vk;
  assign DPRS_imm = DCDP_imm;
  assign DPRS_opcode = DCDP_opcode;
  //LSB
  assign DPLSB_RoB_index = RoBDP_RoB_index;
  assign DPLSB_Qj = Qj;
  assign DPLSB_Qk = Qk;
  assign DPLSB_Vj = Vj;
  assign DPLSB_VK = Vk;
  assign DPLSB_opcode = DCDP_opcode;
  assign DPLSB_imm = DCDP_imm;

  reg [EX_RoB_WIDTH - 1:0] Qj, Qk;
  reg [31:0] Vj, Vk;
  reg state; //IDLE, WAITING_INS


  //check Qj/Qk dependency from :
  //1. RF (and RoB commit at this posedge);
  //2. RoB;
  //3, CDB(RS, LSB);
  always @(*) begin  
    if (RFDP_Qj != NON_DEP) begin
      if(!RoBDP_Qj_ready && (!CDBDP_RS_en || CDBDP_RS_RoB_index != RFDP_Qj) && (!CDBDP_LSB_en || CDBDP_LSB_RoB_index != RFDP_Qj)) begin
        //Qj is not ready
        Qj = RFDP_Qj;
        Vj = RFDP_Vj;
      end else begin
        //get Vj from RoB or CDB
        Qj = NON_DEP;
        if (RoBDP_Qj_ready) begin
          Vj = RoBDP_Vj;
        end else if (CDBDP_RS_en && CDBDP_RS_RoB_index == RFDP_Qj) begin
          Vj = CDBDP_RS_value;
        end else begin
          Vj = CDBDP_LSB_value;
        end
      end
    end
    if (RFDP_Qk != NON_DEP) begin
      if(!RoBDP_Qk_ready && (!CDBDP_RS_en || CDBDP_RS_RoB_index != RFDP_Qk) && (!CDBDP_LSB_en || CDBDP_LSB_RoB_index != RFDP_Qk)) begin
        //Qk is not ready
        Qk = RFDP_Qk;
        Vk = RFDP_Vk;
      end else begin
        //get Vk from RoB or CDB
        Qk = NON_DEP;
        if (RoBDP_Qk_ready) begin
          Vk = RoBDP_Vk;
        end else if (CDBDP_RS_en && CDBDP_RS_RoB_index == RFDP_Qk) begin
          Vk = CDBDP_RS_value;
        end else begin
          Vk = CDBDP_LSB_value;
        end
      end
    end
  end



  always @(posedge Sys_clk) begin  //get a new instruction
    if (!RoBDP_pre_judge || Sys_rst) begin : clear
      state <= IDLE;
      DPDC_ask_IF <= 0;
      DPRF_en <= 0;
      DPRS_en <= 0;
      DPLSB_en <= 0;
      DPRoB_en <= 0;
      Qj <= NON_DEP;
      Qk <= NON_DEP;
      Vj <= 0;
      Vk <= 0;
    end else if (Sys_rdy) begin
      if (state == IDLE) begin  //ask for a new instruction
        DPRF_en  <= 0;
        DPRoB_en <= 0;
        DPRS_en  <= 0;
        DPLSB_en <= 0;
        if (RSDP_full || LSBDP_full || RoBDP_full) begin
          DPDC_ask_IF <= 0;
        end else begin
          DPDC_ask_IF <= 1;
          state <= WAITING_INS;
        end
      end else begin  //waiting for instruction
        if (DCDP_en) begin  //instruction fetched
          state <= IDLE;
          DPDC_ask_IF <= 0;
          DPRF_en <= 1;  //rd and RoB index sent to RoB is valid now!
          DPRoB_en <= 1;  //pc, opcode, predict_result, rd sent to RoB is valid now!
          if(DCDP_opcode == lb || DCDP_opcode == lh || DCDP_opcode == lw || DCDP_opcode == lbu || DCDP_opcode == lhu || DCDP_opcode == sw || DCDP_opcode == sh || DCDP_opcode == sb) begin
            DPLSB_en <= 1;  //opcode, imm, Qj, Qk, Vj, Vk sent to LSB is valid now!
            DPRS_en  <= 0;
          end else begin
            DPLSB_en <= 0;
            DPRS_en  <= 1;  //pc, opcode, imm, Qj, Qk, Vj, Vk sent to RS is valid now!
          end
        end
      end
    end
  end




endmodule
