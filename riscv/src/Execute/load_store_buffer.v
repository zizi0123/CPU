module LoadStoreBuffer (
    //System
    input Sys_clk,
    input Sys_rst,
    input Sys_rdy,

    //dispatcher
    input wire DPLSB_en,
    input wire [31:0] DPLSB_Vj,
    input wire [31:0] DPLSB_Vk,
    input wire [EX_RoB_WIDTH - 1:0] DPLSB_Qj,
    input wire [EX_RoB_WIDTH - 1:0] DPLSB_Qk,
    input wire [ADDR_WIDTH - 1:0] DPLSB_imm,
    input wire [6:0] DPLSB_opcode,
    input wire [RoB_WIDTH - 1:0] DPLSB_RoB_index,
    output wire LSBDP_full,

    //Mem controller
    input MCLSB_en,
    input [7:0] MCLSB_data,
    input [1:0] MCLSB_data_number,
    output reg LSBMC_en,
    output reg LSBMC_wr,  //0:read 1:write
    output reg [1:0] LSBMC_data_width,
    output reg [7:0] LSBMC_data,
    output reg [31:0] LSBMC_addr,

    //CDB
    input wire CDBLSB_RS_en,
    input wire [RoB_WIDTH - 1:0] CDBLSB_RS_RoB_index,
    input wire [31:0] CDBLSB_RS_value,
    output reg LSBCDB_en,
    output reg [RoB_WIDTH - 1:0] LSBCDB_RoB_index,
    output reg [31:0] LSBCDB_value,

    //RoB
    input RoBLSB_pre_judge,
    input RoBLSB_commit_index,  //the last committed instruction
    output reg [RoB_WIDTH - 1:0] LSBRoB_commit_index  //the last committed store instruction in LSB
    );


  parameter ADDR_WIDTH = 32;
  parameter REG_WIDTH = 5;
  parameter EX_REG_WIDTH = 6;  //extra one bit for empty reg
  parameter NON_REG = 6'b100000;
  parameter RoB_WIDTH = 8;
  parameter EX_RoB_WIDTH = 9;
  parameter LSB_WIDTH = 3;
  parameter EX_LSB_WIDTH = 4;
  parameter LSB_SIZE = 1 << LSB_WIDTH;
  parameter NON_DEP = 9'b100000000;  //no dependency
  parameter UNSTART = 0,WAITING_MEM = 1,WAITING_COMMIT = 2; //0:unready or ready but haven't interacted with mem 1:waiting for memory controller 2:gotten data from memory controller,waiting for commit
  parameter LOAD = 1, STORE = 0;
  parameter READ = 1, WRITE = 0;

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

  reg [RoB_WIDTH - 1:0] RoB_index;
  reg [6:0] opcode[LSB_SIZE - 1:0];
  reg [31:0] Vj[LSB_SIZE - 1:0];
  reg [31:0] Vk[LSB_SIZE - 1:0]; //used for load data in LOAD instructions
  reg [EX_RoB_WIDTH - 1:0] Qj[LSB_SIZE - 1:0];
  reg [EX_RoB_WIDTH - 1:0] Qk[LSB_SIZE - 1:0];
  reg [31:0] imm[LSB_SIZE - 1:0];
  wire [ADDR_WIDTH - 1:0] address[LSB_SIZE - 1:0];
  reg busy[LSB_SIZE - 1:0];
  wire ready[LSB_SIZE - 1:0];
  wire front_type;  //1:load 0:store
  wire mem_front_type;  //1:load 0:store
  reg [1:0] state[LSB_SIZE - 1:0];  //state of a item in LSB. UNSTART:0,WAITING_MEM:1,WAITING_COMMIT:2
  reg [LSB_WIDTH - 1:0] front;
  reg [LSB_WIDTH - 1:0] rear;
  reg [LSB_WIDTH - 1:0] mem_front;

  //update ready signal immediately
  genvar i;
  generate
    for (i = 0; i < LSB_SIZE; i = i + 1) begin : assign_ready
      assign ready[i] = (Qj[i] == NON_DEP) && (Qk[i] == NON_DEP) && busy[i];
      assign address[i] = imm[i] + Vj[i];  //when ready[i],address[i] is valid
    end
  endgenerate

  assign LSBDP_full = (rear == front);
  assign front_type = (opcode[front] == lb) || (opcode[front] == lh) || (opcode[front] == lw) || (opcode[front] == lbu) || (opcode[front] == lhu);
  assign mem_front_type = (opcode[mem_front] == lb) || (opcode[mem_front] == lh) || (opcode[mem_front] == lw) || (opcode[mem_front] == lbu) || (opcode[mem_front] == lhu) || (opcode[mem_front] == sb) || (opcode[mem_front] == sh) || (opcode[mem_front] == sw);

  integer j;

  always @(CDBLSB_RS_en or CDBLSB_RS_RoB_index or LSBCDB_en or LSBCDB_RoB_index) begin
    if(CDBLSB_RS_en) begin
      for(j = 0; j < LSB_SIZE; ++j) begin
        if(busy[j] && (Qj[j] == CDBLSB_RS_RoB_index)) begin
          Qj[j] <= NON_DEP;
          Vj[j] <= CDBLSB_RS_value;
        end
        if(busy[j] && (Qk[j] == CDBLSB_RS_RoB_index)) begin
          Qk[j] <= NON_DEP;
          Vk[j] <= CDBLSB_RS_value;
        end
      end
    end
    if(LSBCDB_en) begin
      for(j = 0; j < LSB_SIZE; ++j) begin
        if(busy[j] && (Qj[j] == LSBCDB_RoB_index)) begin
          Qj[j] <= NON_DEP;
          Vj[j] <= LSBCDB_value;
        end
        if(busy[j] && (Qk[j] == LSBCDB_RoB_index)) begin
          Qk[j] <= NON_DEP;
          Vk[j] <= LSBCDB_value;
        end
      end
    end
  end

  always @(posedge Sys_clk) begin
    if (Sys_rst || !RoBLSB_pre_judge) begin
      for (j = 0; j < LSB_SIZE; ++j) begin
        busy[j] <= 0;
        state[j] <= 0;
        front <= 0;
        rear <= 0;
        mem_front <= 0;
      end
    end else if (Sys_rdy) begin
      // sent a new instruction to load store buffer at posedge
      if (DPLSB_en && !LSBDP_full) begin
        if (DPLSB_Qj != NON_DEP) begin
          if (LSBCDB_en && (LSBCDB_RoB_index == DPLSB_Qj)) begin
            Qj[rear] <= NON_DEP;
            Vj[rear] <= LSBCDB_value;
          end else if (CDBLSB_RS_en && (CDBLSB_RS_RoB_index == DPLSB_Qj)) begin
            Qj[rear] <= NON_DEP;
            Vj[rear] <= CDBLSB_RS_value;
          end else begin
            Qj[rear] <= DPLSB_Qj;
            Vj[rear] <= DPLSB_Vj;
          end
        end else begin
          Qj[rear] <= NON_DEP;
          Vj[rear] <= DPLSB_Vj;
        end
        if (DPLSB_Qk != NON_DEP) begin
          if (LSBCDB_en && (LSBCDB_RoB_index == DPLSB_Qk)) begin
            Qk[rear] <= NON_DEP;
            Vk[rear] <= LSBCDB_value;
          end else if (CDBLSB_RS_en && (CDBLSB_RS_RoB_index == DPLSB_Qk)) begin
            Qk[rear] <= NON_DEP;
            Vk[rear] <= CDBLSB_RS_value;
          end else begin
            Qk[rear] <= DPLSB_Qk;
            Vk[rear] <= DPLSB_Vk;
          end
        end else begin
          Qk[rear] <= NON_DEP;
          Vk[rear] <= DPLSB_Vk;
        end
        RoB_index[rear] <= DPLSB_RoB_index;
        opcode[rear] <= DPLSB_opcode;
        busy[rear] <= 1;
        imm[rear] <= DPLSB_imm;
        state[rear] <= 0;
        rear <= (rear + 1) % LSB_SIZE;
      end
      if (busy[front]) begin
        if (state[front] == WAITING_COMMIT) begin  //"commit": write to memory or sent to CDB
          if (front_type == LOAD) begin
            LSBCDB_en <= 1;
            LSBCDB_RoB_index <= RoB_index[front];
            LSBCDB_value <= Vk[front];
            busy[front] <= 0;
            state[front] <= 0;
            front <= (front + 1) % LSB_SIZE;
            if(mem_front == front) begin
              mem_front <= (mem_front + 1) % LSB_SIZE;
            end
            end
          end else begin  //front_type == STORE
            LSBCDB_en <= 0;
            if (RoBLSB_commit_index + 1 == RoB_index[front]) begin
              LSBMC_en <= 1;
              LSBMC_wr <= WRITE;
              LSBMC_data_width <= (opcode[front] == sb) ? 1 : (opcode[front] == sh) ? 2 : 4;
              LSBMC_data <= Vk[front];
              LSBMC_addr <= address[front];
              busy[front] <= 0;
              state[front] <= UNSTART;
              LSBRoB_commit_index <= RoB_index[front];
              front <= (front + 1) % LSB_SIZE;
              mem_front <= (mem_front + 1) % LSB_SIZE; //attention assert: mem_front == front at this time
            end
          end
        end else begin
          LSBCDB_en <= 0;
        end
        if(busy[mem_front] && ready[mem_front]) begin
          if(mem_front_type == LOAD) begin
            if(state[mem_front] == UNSTART)begin
              LSBMC_en <= 1;
              LSBMC_wr <= READ;
              LSBMC_data_width <= (opcode[mem_front] == lb || opcode[mem_front] == lbu) ? 1 : (opcode[mem_front] == lh || opcode[mem_front] == lhu) ? 2 : 4;
              LSBMC_addr <= address[mem_front];
              state[mem_front] <= WAITING_MEM;
            end else if(state[mem_front] == WAITING_MEM)begin
              if(MCLSB_en)begin
                case (MCLSB_data_number)
                  2'b00: Vk[mem_front][7:0] <= MCLSB_data;
                  2'b01: Vk[mem_front][15:8] <= MCLSB_data;
                  2'b10: Vk[mem_front][23:16] <= MCLSB_data;
                  default: Vk[mem_front][31:24] <= MCLSB_data;
                endcase
                if(((opcode[mem_front] == lb || opcode[mem_front] == lbu) && MCLSB_data_number == 2'b00) || ((opcode[mem_front] == lh || opcode[mem_front] == lhu) && MCLSB_data_number == 2'b01) || (opcode[mem_front] == lw && MCLSB_data_number == 2'b10))begin
                  state[mem_front] <= WAITING_COMMIT;
                  mem_front <= (mem_front + 1) % LSB_SIZE;
                end
              end
            end
          end else begin //mem_front_type == STORE
            if(state[mem_front] != WAITING_COMMIT) begin
              state[mem_front] <= WAITING_COMMIT;
            end
          end
        end
      end

  end




endmodule
