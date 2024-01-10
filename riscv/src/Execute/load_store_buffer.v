module LoadStoreBuffer (
    //System
    input Sys_clk,
    input Sys_rst,
    input Sys_rdy,

    //dispatcher
    input wire DPLSB_en,
    input wire [EX_RoB_WIDTH - 1:0] DPLSB_Qj,
    input wire [EX_RoB_WIDTH - 1:0] DPLSB_Qk,
    input wire [31:0] DPLSB_Vj,
    input wire [31:0] DPLSB_Vk,
    input wire [31:0] DPLSB_imm,
    input wire [6:0] DPLSB_opcode,
    input wire [RoB_WIDTH - 1:0] DPLSB_RoB_index,
    output wire LSBDP_full,

    //Mem controller
    input MCLSB_r_en,
    input MCLSB_w_en,
    input [31:0] MCLSB_data,
    output reg LSBMC_en,
    output reg LSBMC_wr,  //0:read 1:write
    output reg [2:0] LSBMC_data_width,
    output reg [31:0] LSBMC_data,
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
    input [RoB_WIDTH - 1:0] RoBLSB_commit_index,  //the last committed instruction
    output reg [EX_RoB_WIDTH - 1:0] LSBRoB_commit_index  //the last committed store instruction in LSB
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
  parameter UNSTART = 0,WAITING_MEM = 1; //0:unready or ready but haven't interacted with mem 1:waiting for memory controller 
  parameter LOAD = 1, STORE = 0;
  parameter READ = 0, WRITE = 1;

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

`ifdef DEBUG
  parameter FILE_NAME = "./reg.txt";
  integer file_handle = 0;
  initial begin
    file_handle = $fopen(FILE_NAME, "a");
    if (!file_handle) begin
      $display("Could not open File \r");
      $stop;
    end
  end
`endif

  reg [RoB_WIDTH - 1:0] RoB_index[LSB_SIZE - 1:0];
  reg [6:0] opcode[LSB_SIZE - 1:0];
  reg [31:0] Vj[LSB_SIZE - 1:0];
  reg [31:0] Vk[LSB_SIZE - 1:0];  //used for load data in LOAD instructions
  reg [EX_RoB_WIDTH - 1:0] Qj[LSB_SIZE - 1:0];
  reg [EX_RoB_WIDTH - 1:0] Qk[LSB_SIZE - 1:0];
  reg [31:0] imm[LSB_SIZE - 1:0];
  wire [ADDR_WIDTH - 1:0] address[LSB_SIZE - 1:0];
  reg busy[LSB_SIZE - 1:0];
  wire ready[LSB_SIZE - 1:0];
  wire front_type;  //1:load 0:store
  reg LSB_state[LSB_SIZE - 1:0];  //LSB_state of a item in LSB. UNSTART:0,WAITING_MEM:1
  reg [LSB_WIDTH - 1:0] front;
  reg [LSB_WIDTH - 1:0] rear;
  reg discard;  //if prediction is wrong, discard the next data come from memory controller

  //update ready signal immediately
  genvar i;
  generate
    for (i = 0; i < LSB_SIZE; i = i + 1) begin : assign_ready
      assign ready[i]   = (Qj[i] == NON_DEP) && (Qk[i] == NON_DEP) && busy[i];
      assign address[i] = imm[i] + Vj[i];  //when ready[i],address[i] is valid
    end
  endgenerate

  assign LSBDP_full = ((rear + 1) % LSB_SIZE == front);
  assign front_type = ((opcode[front] == lb) || (opcode[front] == lh) || (opcode[front] == lw) || (opcode[front] == lbu) || (opcode[front] == lhu)) ? LOAD : STORE;

  integer j;

  always @(*) begin
    if (CDBLSB_RS_en) begin
      for (j = 0; j < LSB_SIZE; ++j) begin
        if (busy[j] && (Qj[j] == CDBLSB_RS_RoB_index)) begin
          Qj[j] <= NON_DEP;
          Vj[j] <= CDBLSB_RS_value;
        end
        if (busy[j] && (Qk[j] == CDBLSB_RS_RoB_index)) begin
          Qk[j] <= NON_DEP;
          Vk[j] <= CDBLSB_RS_value;
        end
      end
    end
    if (LSBCDB_en) begin
      for (j = 0; j < LSB_SIZE; ++j) begin
        if (busy[j] && (Qj[j] == LSBCDB_RoB_index)) begin
          Qj[j] <= NON_DEP;
          Vj[j] <= LSBCDB_value;
        end
        if (busy[j] && (Qk[j] == LSBCDB_RoB_index)) begin
          Qk[j] <= NON_DEP;
          Vk[j] <= LSBCDB_value;
        end
      end
    end
  end

  always @(*) begin  //update MCLSB_en immediately when memory controller finish a request
    if (!(Sys_rst || !RoBLSB_pre_judge) && LSBMC_en && ((LSBMC_wr == READ && MCLSB_r_en && !discard) || LSBMC_wr == WRITE && MCLSB_w_en)) begin
      LSBMC_en <= 0;
    end
  end

  always @(posedge Sys_clk) begin
    if (Sys_rst || !RoBLSB_pre_judge) begin
      for (j = 0; j < LSB_SIZE; ++j) begin
        busy[j] <= 0;
        LSB_state[j] <= 0;
        front <= 0;
        rear <= 0;
      end
      LSBMC_en <= 0;
      LSBCDB_en <= 0;
      LSBRoB_commit_index <= RoB_SIZE;
      if (!RoBLSB_pre_judge && LSBMC_en && LSBMC_wr == READ && !MCLSB_r_en) begin
        discard <= 1;  //the next data come fron memory controller should be discarded
      end else begin  //reset
        discard <= 0;
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
        LSB_state[rear] <= UNSTART;
        rear <= (rear + 1) % LSB_SIZE;
      end

      //restore discard signal
      if (discard && MCLSB_r_en) begin
        discard <= 0;
      end

      //when the new commit index has received by RoB, update it to empty to prevent conflicts with RoB index in RS
      if (LSBRoB_commit_index != RoB_SIZE && !(busy[front] && LSB_state[front] == WAITING_MEM && MCLSB_w_en)) begin
        LSBRoB_commit_index <= RoB_SIZE;
      end

        // sent to CDB or write to memory
        if (busy[front]) begin
          if (LSB_state[front] == UNSTART) begin
            LSBCDB_en <= 0;
            if (ready[front]) begin
              if (front_type == LOAD) begin
                LSBMC_en <= 1;
                LSBMC_wr <= READ;
                LSBMC_data_width <= (opcode[front] == lb || opcode[front] == lbu) ? 1 : (opcode[front] == lh || opcode[front] == lhu) ? 2 : 4;
                LSBMC_addr <= address[front];
                LSB_state[front] <= WAITING_MEM;
              end else begin  //STORE
                if ((RoBLSB_commit_index + 1) % RoB_SIZE == RoB_index[front] || (RoBLSB_commit_index == 0 && RoB_index[front] == 0)) begin  //wrong prediction and all cleared, store instruction may be the first insturction
                  LSBMC_en <= 1;
                  LSBMC_wr <= WRITE;
                  case (opcode[front])
                    sb: begin
                      LSBMC_data <= Vk[front][7:0];
                      LSBMC_data_width <= 1;
                    end
                    sh: begin
                      LSBMC_data <= Vk[front][15:0];
                      LSBMC_data_width <= 2;
                    end
                    default: begin
                      LSBMC_data <= Vk[front];
                      LSBMC_data_width <= 4;
                    end
                  endcase
                  LSBMC_addr <= address[front];
                  LSB_state[front] <= WAITING_MEM;
                end
              end
            end
          end else if (LSB_state[front] == WAITING_MEM) begin
            if (MCLSB_w_en) begin
`ifdef DEBUG
              // $fdisplay(file_handle, "store value: %h to address: %h", Vk[front], address[front]);
              $display("store value: %h to address: %h", Vk[front], address[front]);
`endif
              busy[front] <= 0;
              LSB_state[front] <= UNSTART;
              LSBRoB_commit_index <= RoB_index[front];
              front <= (front + 1) % LSB_SIZE;
              LSBCDB_en <= 0;
            end else if (MCLSB_r_en && !discard) begin  //load finished
              busy[front] <= 0;
              LSB_state[front] <= UNSTART;
              front <= (front + 1) % LSB_SIZE;
              LSBCDB_en <= 1;
              LSBCDB_RoB_index <= RoB_index[front];
              case (opcode[front])
                lb:  LSBCDB_value <= {{24{MCLSB_data[7]}}, MCLSB_data[7:0]};
                lbu: LSBCDB_value <= {24'b0, MCLSB_data[7:0]};
                lh:  LSBCDB_value <= {{16{MCLSB_data[15]}}, MCLSB_data[15:0]};
                lhu: LSBCDB_value <= {16'b0, MCLSB_data[15:0]};
                lw:  LSBCDB_value <= MCLSB_data;
              endcase
            end else begin
              LSBCDB_en <= 0;
            end
          end
        end
    end
  end
endmodule
