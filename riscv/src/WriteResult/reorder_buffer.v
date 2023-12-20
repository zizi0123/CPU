module ReorderBuffer (
    //System
    input Sys_clk,
    input Sys_rst,
    input Sys_rdy,

    //Dispatcher
    input wire [EX_RoB_WIDTH - 1:0] DPRoB_Qj,  //prefetch:ask if Qj is ready in RoB
    input wire [EX_RoB_WIDTH - 1:0] DPRoB_Qk,  //prefetch:ask if Qk is ready in RoB
    input wire DPRoB_en,  //send a new instruction to RoB
    input wire [ADDR_WIDTH - 1:0] DPRoB_pc,
    input wire DPRoB_predict_result,
    input wire [6:0] DPRoB_opcode,
    input wire [EX_REG_WIDTH - 1:0] DPRoB_rd,
    output wire RoBDP_full,
    output wire [RoB_WIDTH - 1:0] RoBDP_RoB_index,
    output wire RoBDP_pre_judge,  //0:mispredict 1:correct
    output wire RoBDP_Qj_ready,  //RoB item Qj is ready in RoB
    output wire RoBDP_Qk_ready,  //RoB item Qk is ready in RoB
    output wire [31:0] RoBDP_Vj,
    output wire [31:0] RoBDP_Vk,

    //Instruction Fetcher
    output reg RoBIF_jalr_en,
    output reg RoBIF_branch_en,
    output wire RoBIF_pre_judge, //the result of the branch instruction, 0:wrong prediction, 1:correct prediction
    output reg RoBIF_branch_result,  //the result of the branch instruction, 0: not taken, 1: taken
    output reg [ADDR_WIDTH - 1:0] RoBIF_branch_pc,  //the pc of the branch instruction
    output reg [ADDR_WIDTH - 1:0] RoBIF_next_pc, //the pc of the next instruction for jalr/wrong prediction

    //ReservationStation
    output wire RoBRS_pre_judge,

    //LoadStoreBuffer
    input wire [RoB_WIDTH - 1:0] LSBRoB_commit_index,  //the last committed store instruction in LSB
    output wire RoBLSB_pre_judge,
    output wire RoBLSB_commit_index,

    //CDB
    input wire CDBRoB_RS_en,
    input wire [RoB_WIDTH - 1:0] CDBRoB_RS_RoB_index,
    input wire [31:0] CDBRoB_RS_value,  //rd value or branch result(jump or not)
    input wire [ADDR_WIDTH - 1:0] CDBRoB_RS_next_pc,
    input wire CDBRoB_LSB_en,
    input wire [RoB_WIDTH - 1:0] CDBRoB_LSB_RoB_index,
    input wire [31:0] CDBRoB_LSB_value,

    //RegisterFile
    output wire RoBRF_pre_judge,
    output reg RoBRF_en,  //commit a new instruction, RoB index,rd,value is valid now!
    output reg [RoB_WIDTH - 1:0] RoBRF_RoB_index,
    output reg [EX_REG_WIDTH - 1:0] RoBRF_rd,
    output reg [31:0] RoBRF_value
);
  parameter ADDR_WIDTH = 32;
  parameter REG_WIDTH = 5;
  parameter EX_REG_WIDTH = 6;  //extra one bit for empty reg
  parameter NON_REG = 6'b100000;
  parameter RoB_WIDTH = 8;
  parameter EX_RoB_WIDTH = 9;
  parameter RoB_SIZE = 1 << RoB_WIDTH;
  parameter LSB_WIDTH = 3;
  parameter EX_LSB_WIDTH = 4;
  parameter LSB_SIZE = 1 << LSB_WIDTH;
  parameter NON_DEP = 9'b100000000;  //no dependency
  parameter OTHER = 0, BRANCH = 1, JALR = 2;
  parameter UNREADY = 0, READY = 1;

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

  reg [RoB_WIDTH - 1:0] RoB_index[RoB_SIZE - 1:0];
  reg [ADDR_WIDTH - 1:0] pc[RoB_SIZE - 1:0];
  reg [6:0] opcode[RoB_SIZE - 1:0];
  reg [EX_REG_WIDTH - 1:0] rd[RoB_SIZE - 1:0];
  reg pre_result[RoB_SIZE - 1:0];  //0: not taken, 1: taken
  reg [31:0] value[RoB_SIZE - 1:0];  //rd value or branch result(jump or not)
  reg [ADDR_WIDTH - 1:0] next_pc[RoB_SIZE - 1:0];
  reg busy[RoB_SIZE - 1:0];
  reg state[RoB_SIZE - 1:0];
  reg [RoB_WIDTH -1 : 0] front;
  reg [RoB_WIDTH -1 : 0] rear;
  reg [RoB_WIDTH -1 : 0] commit_front;  //the last committed instruction in RoB
  reg pre_judge;
  wire front_type;

  assign front_type = (busy[front] && (opcode[front] == beq || opcode[front] == bne || opcode[front] == blt || opcode[front] == bge || opcode[front] == bltu || opcode[front] == bgeu)) ? BRANCH : (busy[front] && opcode[front] == jalr) ? JALR : OTHER;

  //Dispatcher
  assign RoBDP_full = (rear == front);
  assign RoBDP_RoB_index = rear;
  assign RoBDP_pre_judge = pre_judge;
  assign RoBDP_Qj_ready = (DPRoB_Qj == NON_DEP || state[DPRoB_Qj] == READY);
  assign RoBDP_Qk_ready = (DPRoB_Qk == NON_DEP || state[DPRoB_Qk] == READY);
  assign RoBDP_Vj = (DPRoB_Qj == NON_DEP) ? 0 : value[DPRoB_Qj];
  assign RoBDP_Vk = (DPRoB_Qk == NON_DEP) ? 0 : value[DPRoB_Qk];

  //Instruction Fetcher
  assign RoBIF_pre_judge = pre_judge;

  //RS
  assign RoBRS_pre_judge = pre_judge;

  //LSB
  assign RoBLSB_commit_index = commit_front;
  assign RoBLSB_pre_judge = pre_judge;

  //RF
  assign RoBRF_pre_judge = pre_judge;

  integer i;

  always @(posedge Sys_clk) begin
    if (Sys_rst || !pre_judge) begin
      for (i = 0; i < RoB_SIZE; ++i) begin
        RoB_index[i] <= 0;
        pc[i] <= 0;
        opcode[i] <= 0;
        rd[i] <= 0;
        pre_result[i] <= 0;
        value[i] <= 0;
        next_pc[i] <= 0;
        busy[i] <= 0;
        state[i] <= UNREADY;
      end
      front <= 0;
      rear <= 0;
      commit_front <= 0;
      pre_judge <= 1;
    end else if (Sys_rdy) begin
      //Dispatcher
      if (DPRoB_en) begin  //issue an new instruction to RoB
        RoB_index[rear] <= rear;
        pc[rear] <= DPRoB_pc;
        opcode[rear] <= DPRoB_opcode;
        rd[rear] <= DPRoB_rd;
        pre_result[rear] <= DPRoB_predict_result;
        busy[rear] <= 1;
        state[rear] <= UNREADY;
        rear <= (rear + 1) % RoB_SIZE;
      end

      //CDB
      if (CDBRoB_RS_en) begin  //CDB update RoB
        state[CDBRoB_RS_RoB_index]   <= READY;
        value[CDBRoB_RS_RoB_index]   <= CDBRoB_RS_value;
        next_pc[CDBRoB_RS_RoB_index] <= CDBRoB_RS_next_pc;
      end
      if (CDBRoB_LSB_en) begin  //CDB update RoB
        state[CDBRoB_LSB_RoB_index] <= READY;
        value[CDBRoB_LSB_RoB_index] <= CDBRoB_LSB_value;
      end
      
      //LoadStore Buffer
      if (LSBRoB_commit_index == front) begin  //store instruction has been committed to mem in LSB
        busy[front] <= 0;
        state[front] <= UNREADY;
        front <= (front + 1) % RoB_SIZE;
        commit_front <= front;
      end

      //RF
      if (busy[front] && state[front] == READY) begin  //commit an instruction to RF
        RoBRF_en <= 1;
        RoBRF_RoB_index <= front;
        RoBRF_rd <= rd[front];
        RoBRF_value <= value[front];
        busy[front] <= 0;
        state[front] <= UNREADY;
        front <= (front + 1) % RoB_SIZE;
        commit_front <= front;
      end else begin
        RoBRF_en <= 0;
      end

      //Instruction fetcher
      if (CDBRoB_RS_en && opcode[CDBRoB_RS_RoB_index] == jalr) begin
        RoBIF_jalr_en <= 1;
        RoBIF_next_pc <= CDBRoB_RS_next_pc;
      end else begin
        RoBIF_jalr_en <= 0;
      end
      if (busy[front] && front_type == BRANCH && state[front] == READY) begin
        RoBIF_branch_en <= 1;
        pre_judge <= pre_result[front] == value[front];
        RoBIF_branch_result <= value[front];
        RoBIF_branch_pc <= pc[front];
        RoBIF_next_pc <= next_pc[front];
      end else begin
        RoBIF_branch_en <= 0;
        pre_judge <= 0;
      end
    end
  end






endmodule
