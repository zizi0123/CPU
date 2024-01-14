module ReservationStation #(
    parameter ADDR_WIDTH = 32,
    parameter REG_WIDTH = 5,
    parameter EX_REG_WIDTH = 6,  //extra one bit for empty reg
    parameter NON_REG = 6'b100000,
    parameter RoB_WIDTH = 8,
    parameter EX_RoB_WIDTH = 9,
    parameter RS_WIDTH = 3,
    parameter EX_RS_WIDTH = 4,
    parameter RS_SIZE = 1 << RS_WIDTH,
    parameter NON_DEP = 9'b100000000,  //no dependency

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
    //System
    input Sys_clk,
    input Sys_rst,
    input Sys_rdy,

    //dispatcher
    input wire DPRS_en,  //send a new instruction to RS
    input wire [ADDR_WIDTH - 1:0] DPRS_pc,
    input wire [EX_RoB_WIDTH - 1:0] DPRS_Qj,
    input wire [EX_RoB_WIDTH - 1:0] DPRS_Qk,
    input wire [31:0] DPRS_Vj,
    input wire [31:0] DPRS_Vk,
    input wire [31:0] DPRS_imm,
    input wire [6:0] DPRS_opcode,
    input wire [RoB_WIDTH - 1:0] DPRS_RoB_index,
    output wire RSDP_full,  //1:RS is full

    //CDB
    input wire CDBRS_LSB_en,
    input wire [RoB_WIDTH - 1:0] CDBRS_LSB_RoB_index,
    input wire [31:0] CDBRS_LSB_value,
    output reg RSCDB_en,
    output reg [RoB_WIDTH - 1:0] RSCDB_RoB_index,
    output reg [31:0] RSCDB_value,  //rd value or branch result(jump or not)
    output reg [ADDR_WIDTH - 1:0] RSCDB_next_pc,

    //RoB
    input wire RoBRS_pre_judge  //0:mispredict 1:correct
);



  reg [RoB_WIDTH - 1:0] RoB_index[RS_SIZE - 1:0];
  reg busy[RS_SIZE - 1:0];
  reg [6:0] opcode[RS_SIZE - 1:0];
  reg [31:0] Vj[RS_SIZE - 1:0];
  reg [31:0] Vk[RS_SIZE - 1:0];
  reg [EX_RoB_WIDTH - 1:0] Qj[RS_SIZE - 1:0];
  reg [EX_RoB_WIDTH - 1:0] Qk[RS_SIZE - 1:0];
  reg [31:0] imm[RS_SIZE - 1:0];
  reg [ADDR_WIDTH - 1:0] pc[RS_SIZE - 1:0];
  wire ready[RS_SIZE - 1:0];
  wire [EX_RS_WIDTH - 1:0] idle_head;  //the index of the first idle item in RS
  wire [EX_RS_WIDTH - 1:0] ready_head;  //the index of the next ready item in RS


  genvar i;
  generate  //update ready signal immediately
    for (i = 0; i < RS_SIZE; i = i + 1) begin : assign_ready
      assign ready[i] = busy[i] && (Qj[i] == NON_DEP) && (Qk[i] == NON_DEP);
    end
  endgenerate

  assign idle_head = (!busy[0]) ? 0 : (!busy[1]) ? 1 : (!busy[2]) ? 2 : (!busy[3]) ? 3 : (!busy[4]) ? 4 : (!busy[5]) ? 5 : (!busy[6]) ? 6 : (!busy[7]) ? 7 : 8;
  assign ready_head = (ready[0]) ? 0 : (ready[1]) ? 1 : (ready[2]) ? 2 : (ready[3]) ? 3 : (ready[4]) ? 4 : (ready[5]) ? 5 : (ready[6]) ? 6 : (ready[7]) ? 7 : 8;
  assign RSDP_full = idle_head == RS_SIZE;

  integer j;

  always @(*) begin  //update dependency immediately
    if (CDBRS_LSB_en) begin
      for (j = 0; j < RS_SIZE; j = j + 1) begin
        if (Qj[j] == CDBRS_LSB_RoB_index) begin
          Qj[j] <= NON_DEP;
          Vj[j] <= CDBRS_LSB_value;
        end
        if (Qk[j] == CDBRS_LSB_RoB_index) begin
          Qk[j] <= NON_DEP;
          Vk[j] <= CDBRS_LSB_value;
        end
      end
    end
    if (RSCDB_en) begin
      for (j = 0; j < RS_SIZE; j = j + 1) begin
        if (Qj[j] == RSCDB_RoB_index) begin
          Qj[j] <= NON_DEP;
          Vj[j] <= RSCDB_value;
        end
        if (Qk[j] == RSCDB_RoB_index) begin
          Qk[j] <= NON_DEP;
          Vk[j] <= RSCDB_value;
        end
      end
    end
  end

  always @(posedge Sys_clk) begin
    if (Sys_rst || !RoBRS_pre_judge) begin
      for (j = 0; j < RS_SIZE; j = j + 1) begin
        busy[j] <= 0;
      end
      RSCDB_en <= 0;
    end else if (Sys_rdy) begin
      if (DPRS_en && !RSDP_full) begin  //send a new instruction to RS at posedge
        if (DPRS_Qj != NON_DEP) begin
          if (RSCDB_en && RSCDB_RoB_index == DPRS_Qj) begin
            Qj[idle_head] <= NON_DEP;  //check if Qj is ready in RS/LSB at this posedge through CBD
            Vj[idle_head] <= RSCDB_value;
          end else if (CDBRS_LSB_en && CDBRS_LSB_RoB_index == DPRS_Qj) begin
            Qj[idle_head] <= NON_DEP;
            Vj[idle_head] <= CDBRS_LSB_value;
          end else begin
            Qj[idle_head] <= DPRS_Qj;
            Vj[idle_head] <= DPRS_Vj;
          end
        end else begin
          Qj[idle_head] <= NON_DEP;
          Vj[idle_head] <= DPRS_Vj;
        end
        if (DPRS_Qk != NON_DEP) begin
          if (RSCDB_en && RSCDB_RoB_index == DPRS_Qk) begin
            Qk[idle_head] <= NON_DEP;  //check if Qk is ready in RS/LSB at this posedge through CBD
            Vk[idle_head] <= RSCDB_value;
          end else if (CDBRS_LSB_en && CDBRS_LSB_RoB_index == DPRS_Qk) begin
            Qk[idle_head] <= NON_DEP;
            Vk[idle_head] <= CDBRS_LSB_value;
          end else begin
            Qk[idle_head] <= DPRS_Qk;
            Vk[idle_head] <= DPRS_Vk;
          end
        end else begin
          Qk[idle_head] <= NON_DEP;
          Vk[idle_head] <= DPRS_Vk;
        end
        RoB_index[idle_head] <= DPRS_RoB_index;
        opcode[idle_head] <= DPRS_opcode;
        imm[idle_head] <= DPRS_imm;
        busy[idle_head] <= 1;
        pc[idle_head] <= DPRS_pc;
      end
      if (ready_head != RS_SIZE) begin  //send a ready instruction to CDB at posedge
        RSCDB_en <= 1;
        RSCDB_RoB_index <= RoB_index[ready_head];
        busy[ready_head] <= 0;
        case (opcode[ready_head])
          lui: begin
            RSCDB_value <= imm[ready_head];
          end
          auipc: begin
            RSCDB_value <= pc[ready_head] + imm[ready_head];
          end
          jal: begin
            RSCDB_value   <= pc[ready_head] + 4;
            RSCDB_next_pc <= pc[ready_head] + imm[ready_head];
          end
          jalr: begin
            RSCDB_value   <= pc[ready_head] + 4;
            RSCDB_next_pc <= (Vj[ready_head] + imm[ready_head]) & ~1;
          end
          beq: begin
            RSCDB_value <= (Vj[ready_head] == Vk[ready_head]) ? 1 : 0;
            RSCDB_next_pc <= (Vj[ready_head] == Vk[ready_head]) ? pc[ready_head] + imm[ready_head] : pc[ready_head] + 4;
          end
          bne: begin
            RSCDB_value <= (Vj[ready_head] != Vk[ready_head]) ? 1 : 0;
            RSCDB_next_pc <= (Vj[ready_head] != Vk[ready_head]) ? pc[ready_head] + imm[ready_head] : pc[ready_head] + 4;
          end
          blt: begin
            RSCDB_value <= ($signed(Vj[ready_head]) < $signed(Vk[ready_head])) ? 1 : 0;
            RSCDB_next_pc <= ($signed(
                Vj[ready_head]
            ) < $signed(
                Vk[ready_head]
            )) ? pc[ready_head] + imm[ready_head] : pc[ready_head] + 4;
          end
          bge: begin
            RSCDB_value <= ($signed(Vj[ready_head]) >= $signed(Vk[ready_head])) ? 1 : 0;
            RSCDB_next_pc <= ($signed(
                Vj[ready_head]
            ) >= $signed(
                Vk[ready_head]
            )) ? pc[ready_head] + imm[ready_head] : pc[ready_head] + 4;
          end
          bltu: begin
            RSCDB_value <= (Vj[ready_head] < Vk[ready_head]) ? 1 : 0;
            RSCDB_next_pc <= (Vj[ready_head] < Vk[ready_head]) ? pc[ready_head] + imm[ready_head] : pc[ready_head] + 4;
          end
          bgeu: begin
            RSCDB_value <= (Vj[ready_head] >= Vk[ready_head]) ? 1 : 0;
            RSCDB_next_pc <= (Vj[ready_head] >= Vk[ready_head]) ? pc[ready_head] + imm[ready_head] : pc[ready_head] + 4;
          end
          addi: begin
            RSCDB_value <= Vj[ready_head] + imm[ready_head];
          end
          slti: begin
            RSCDB_value <= ($signed(Vj[ready_head]) < $signed(imm[ready_head])) ? 1 : 0;
          end
          sltiu: begin
            RSCDB_value <= (Vj[ready_head] < imm[ready_head]) ? 1 : 0;
          end
          xori: begin
            RSCDB_value <= Vj[ready_head] ^ imm[ready_head];
          end
          ori: begin
            RSCDB_value <= Vj[ready_head] | imm[ready_head];
          end
          andi: begin
            RSCDB_value <= Vj[ready_head] & imm[ready_head];
          end
          slli: begin
            RSCDB_value <= Vj[ready_head] << imm[ready_head][4:0];
          end
          srli: begin
            RSCDB_value <= Vj[ready_head] >> imm[ready_head][4:0];
          end
          srai: begin
            RSCDB_value <= $signed(Vj[ready_head]) >>> imm[ready_head][4:0];
          end
          add: begin
            RSCDB_value <= Vj[ready_head] + Vk[ready_head];
          end
          sub: begin
            RSCDB_value <= Vj[ready_head] - Vk[ready_head];
          end
          sll: begin
            RSCDB_value <= Vj[ready_head] << Vk[ready_head][4:0];
          end
          slt: begin
            RSCDB_value <= ($signed(Vj[ready_head]) < $signed(Vk[ready_head])) ? 1 : 0;
          end
          sltu: begin
            RSCDB_value <= (Vj[ready_head] < Vk[ready_head]) ? 1 : 0;
          end
          xorr: begin
            RSCDB_value <= Vj[ready_head] ^ Vk[ready_head];
          end
          srl: begin
            RSCDB_value <= Vj[ready_head] >> Vk[ready_head][4:0];
          end
          sra: begin
            RSCDB_value <= $signed(Vj[ready_head]) >>> Vk[ready_head][4:0];
          end
          orr: begin
            RSCDB_value <= Vj[ready_head] | Vk[ready_head];
          end
          andd: begin
            RSCDB_value <= Vj[ready_head] & Vk[ready_head];
          end
        endcase
      end else begin
        RSCDB_en <= 0;
      end
    end
  end







endmodule
