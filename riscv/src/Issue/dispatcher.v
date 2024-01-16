module Dispatcher #(
    parameter ADDR_WIDTH = 32,
    parameter REG_WIDTH = 5,
    parameter EX_REG_WIDTH = 6,  //extra one bit for empty reg
    parameter NON_REG = 6'b100000,
    parameter RoB_WIDTH = 8,
    parameter EX_RoB_WIDTH = 9,
    parameter NON_DEP = 9'b100000000,  //no dependency
    parameter IDLE = 0,
    WAITING_INS = 1,

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
    output wire [EX_REG_WIDTH - 1:0] DPRF_rs1,
    output wire [EX_REG_WIDTH - 1:0] DPRF_rs2,
    output reg DPRF_en,  //attention rd to regfile is ready
    output reg [RoB_WIDTH - 1:0] DPRF_RoB_index,  //the dependency RoB# of rd
    output reg [EX_REG_WIDTH - 1:0] DPRF_rd,

    //Reservation Station
    input wire RSDP_full,
    output reg DPRS_en,  //send a new instruction to RS
    output reg [ADDR_WIDTH - 1:0] DPRS_pc,
    output reg [EX_RoB_WIDTH - 1:0] DPRS_Qj,
    output reg [EX_RoB_WIDTH - 1:0] DPRS_Qk,
    output reg [31:0] DPRS_Vj,
    output reg [31:0] DPRS_Vk,
    output reg [31:0] DPRS_imm,
    output reg [6:0] DPRS_opcode,
    output reg [RoB_WIDTH - 1:0] DPRS_RoB_index,

    //Load Store Buffer
    input wire LSBDP_full,
    output reg DPLSB_en,  //send a new instruction to LSB
    output reg [EX_RoB_WIDTH - 1:0] DPLSB_Qj,
    output reg [EX_RoB_WIDTH - 1:0] DPLSB_Qk,
    output reg [31:0] DPLSB_Vj,
    output reg [31:0] DPLSB_Vk,
    output reg [31:0] DPLSB_imm,
    output reg [6:0] DPLSB_opcode,
    output reg [RoB_WIDTH - 1:0] DPLSB_RoB_index,

    //Reorder Buffer 
    input wire RoBDP_full,
    input wire [RoB_WIDTH - 1:0] RoBDP_RoB_index,
    input wire RoBDP_pre_judge,  //0:mispredict 1:correct
    input wire RoBDP_Qj_ready,  //RoB item Qj is ready in RoB
    input wire RoBDP_Qk_ready,  //RoB item Qk is ready in RoB
    input wire [31:0] RoBDP_Vj,
    input wire [31:0] RoBDP_Vk,
    output wire [EX_RoB_WIDTH - 1:0] DPRoB_Qj,  //prefetch:ask if Qj is ready in RoB
    output wire [EX_RoB_WIDTH - 1:0] DPRoB_Qk,  //prefetch:ask if Qk is ready in RoB
    output reg DPRoB_en,  //send a new instruction to RoB
    output reg [ADDR_WIDTH - 1:0] DPRoB_pc,
    output reg DPRoB_predict_result,
    output reg [6:0] DPRoB_opcode,
    output reg [EX_REG_WIDTH - 1:0] DPRoB_rd,

    //CDB
    input wire CDBDP_RS_en,
    input wire [RoB_WIDTH - 1:0] CDBDP_RS_RoB_index,
    input wire [31:0] CDBDP_RS_value,
    input wire CDBDP_LSB_en,
    input wire [RoB_WIDTH - 1:0] CDBDP_LSB_RoB_index,
    input wire [31:0] CDBDP_LSB_value

);

  //RF
  assign DPRF_rs1 = (DCDP_opcode == lui || DCDP_opcode == auipc || DCDP_opcode == jal) ? NON_REG : DCDP_rs1;
  assign DPRF_rs2 = (DCDP_opcode == lui || DCDP_opcode == auipc || DCDP_opcode == jal || DCDP_opcode == jalr ||
                       DCDP_opcode == lb || DCDP_opcode == lh || DCDP_opcode == lw || DCDP_opcode == lbu || DCDP_opcode == lhu ||
                       DCDP_opcode == addi || DCDP_opcode == slti || DCDP_opcode == sltiu || DCDP_opcode == xori || DCDP_opcode == ori || DCDP_opcode == andi ||
                       DCDP_opcode == slli || DCDP_opcode == srli || DCDP_opcode == srai) ? NON_REG : DCDP_rs2;
  //RoB
  assign DPRoB_Qj = RFDP_Qj;
  assign DPRoB_Qk = RFDP_Qk;

  reg [EX_RoB_WIDTH - 1:0] Qj, Qk;
  reg [31:0] Vj, Vk;
  reg  state;  //IDLE, WAITING_INS
  reg  waiting_for_not_full;
  wire isLS;  //is load or store

  assign isLS = (DCDP_opcode == lb || DCDP_opcode == lh || DCDP_opcode == lw || DCDP_opcode == lbu || DCDP_opcode == lhu || DCDP_opcode == sw || DCDP_opcode == sh || DCDP_opcode == sb);


  //check Qj/Qk dependency from :
  //1. RF (and RoB commit at this posedge);
  //2. RoB;
  //3, CDB(RS, LSB);
  always @(*) begin
    if (Sys_rst || !RoBDP_pre_judge) begin
      Qj = NON_DEP;
      Qk = NON_DEP;
      Vj = 0;
      Vk = 0;
    end else if (Sys_rdy) begin
      if (RFDP_Qj != NON_DEP) begin
        if(!RoBDP_Qj_ready && (!CDBDP_RS_en || CDBDP_RS_RoB_index != RFDP_Qj) && (!CDBDP_LSB_en || CDBDP_LSB_RoB_index != RFDP_Qj)) begin
          //Qj is really not ready
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
      end else begin
        Qj = NON_DEP;
        Vj = RFDP_Vj;
      end
      if (RFDP_Qk != NON_DEP) begin
        if(!RoBDP_Qk_ready && (!CDBDP_RS_en || CDBDP_RS_RoB_index != RFDP_Qk) && (!CDBDP_LSB_en || CDBDP_LSB_RoB_index != RFDP_Qk)) begin
          //Qk is really not ready
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
      end else begin
        Qk = NON_DEP;
        Vk = RFDP_Vk;
      end
    end
  end


  //update DPDC_ask_IF immediately
  always @(*) begin
    if (!RoBDP_pre_judge || Sys_rst) begin
      DPDC_ask_IF <= 1;
    end else if (Sys_rdy) begin
      if (RSDP_full || LSBDP_full || RoBDP_full || (state == WAITING_INS && DCDP_en)) begin
        DPDC_ask_IF <= 0;
      end else begin
        DPDC_ask_IF <= 1;
      end
    end
  end



  always @(posedge Sys_clk) begin  //get a new instruction
    if (!RoBDP_pre_judge || Sys_rst) begin : clear
      state <= IDLE;
      DPRF_en <= 0;
      DPRS_en <= 0;
      DPLSB_en <= 0;
      DPRoB_en <= 0;
      waiting_for_not_full <= 0;
    end else if (Sys_rdy) begin
      if (state == IDLE) begin  //ask for a new instruction
        if (waiting_for_not_full && !RoBDP_full && !RSDP_full && !LSBDP_full) begin  //rob is available now, dispatch new instruction
          waiting_for_not_full <= 0;
          DPRF_en <= 1;
          DPRoB_en <= 1;
          if (isLS) begin
            DPLSB_en <= 1;
          end else begin
            DPRS_en <= 1;
          end
        end else begin
          DPRF_en  <= 0;
          DPRoB_en <= 0;
          DPRS_en  <= 0;
          DPLSB_en <= 0;
          if (DPDC_ask_IF == 1) begin  //ask for a new instruction
            state <= WAITING_INS;
          end
        end
      end else begin  //waiting for instruction
        if (DCDP_en) begin  //instruction fetched
          if (RoBDP_full || (isLS && LSBDP_full) || (!isLS && RSDP_full)) begin
            waiting_for_not_full <= 1;
          end else begin
            DPRF_en  <= 1;
            DPRoB_en <= 1;
            if (isLS) begin
              DPLSB_en <= 1;
            end else begin
              DPRS_en <= 1;
            end
          end
          state <= IDLE;
          DPRF_rd <= (DCDP_opcode == beq || DCDP_opcode == bne || DCDP_opcode == blt || DCDP_opcode == bge || DCDP_opcode == bltu || DCDP_opcode == bgeu || DCDP_opcode == sb || DCDP_opcode == sh || DCDP_opcode == sw) ? NON_REG : DCDP_rd;
          DPRF_RoB_index <= RoBDP_RoB_index;
          DPRoB_pc <= DCDP_pc;
          DPRoB_opcode <= DCDP_opcode;
          DPRoB_predict_result <= DCDP_predict_result;
          DPRoB_rd <= (DCDP_opcode == beq || DCDP_opcode == bne || DCDP_opcode == blt || DCDP_opcode == bge || DCDP_opcode == bltu || DCDP_opcode == bgeu || DCDP_opcode == sb || DCDP_opcode == sh || DCDP_opcode == sw) ? NON_REG : DCDP_rd;
          if (isLS) begin
            DPRS_en <= 0;
            DPLSB_RoB_index <= RoBDP_RoB_index;
            DPLSB_Qj <= Qj;
            DPLSB_Qk <= Qk;
            DPLSB_Vj <= Vj;
            DPLSB_Vk <= Vk;
            DPLSB_opcode <= DCDP_opcode;
            DPLSB_imm <= DCDP_imm;
          end else begin
            DPRS_RoB_index <= RoBDP_RoB_index;
            DPRS_pc <= DCDP_pc;
            DPRS_Qj <= Qj;
            DPRS_Qk <= Qk;
            DPRS_Vj <= Vj;
            DPRS_Vk <= Vk;
            DPRS_imm <= DCDP_imm;
            DPRS_opcode <= DCDP_opcode;
          end
        end
      end
    end
  end




endmodule
