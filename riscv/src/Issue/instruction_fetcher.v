module InstructionFetcher (
    //sys
    input wire Sys_clk,
    input wire Sys_rst,
    input wire Sys_rdy,

    //ICache
    input  wire                    ICIF_en,
    input  wire [            31:0] ICIF_data,
    output wire                    IFIC_en,
    output wire [ADDR_WIDTH - 1:0] IFIC_pc,

    //Decoder
    input wire DCIF_ask_IF,  //ask for a new instruction
    output reg IFDC_en,
    output wire [ADDR_WIDTH - 1:0] IFDC_pc,
    output wire [6:0] IFDC_opcode,
    output wire [31:7] IFDC_remain_inst,
    output wire IFDC_predict_result,  //0: not taken, 1: taken

    //predictor
    input wire PDIF_en,
    input wire PDIF_predict_result,  //0: not taken, 1: taken
    output reg IFPD_predict_en,  //ask for prediction
    output wire [ADDR_WIDTH - 1:0] IFPD_pc,  //pc of branch instruction
    output reg IFPD_feedback_en,  //feedback the result of branch instruction
    output wire IFPD_branch_result,  //0: not taken, 1: taken
    output wire [ADDR_WIDTH - 1:0] IFPD_feedback_pc,  //the pc of the branch instruction

    //RoB
    input wire RoBIF_jalr_en,
    input wire RoBIF_branch_en,
    input wire RoBIF_pre_judge, //the result of the branch instruction, 0:wrong prediction, 1:correct prediction
    input wire RoBIF_branch_result,  //the result of the branch instruction, 0: not taken, 1: taken
    input wire [ADDR_WIDTH - 1:0] RoBIF_branch_pc,  //the pc of the branch instruction
    input wire [ADDR_WIDTH - 1:0] RoBIF_next_pc //the pc of the next instruction for jalr/wrong prediction
);
  parameter ADDR_WIDTH = 32;
  parameter NORMAL = 0, WAITING_PREDICT = 1, WAITING_RoB = 2;

  wire [31:0] imm;
  reg [ADDR_WIDTH - 1:0] pc;
  reg [1:0] state;

  assign IFIC_en = DCIF_ask_IF;
  assign IFIC_pc = pc;
  assign IFDC_pc = pc;
  assign IFDC_opcode = ICIF_data[6:0];
  assign IFDC_remain_inst = ICIF_data[31:7];
  assign IFDC_predict_result = PDIF_predict_result;
  assign imm = (IFDC_opcode == 7'b1101111) ? {{12{ICIF_data[31]}},ICIF_data[19:12],ICIF_data[20],ICIF_data[30:21],1'b0}  //jal
      :(IFDC_opcode == 7'b1100011) ? {{20{ICIF_data[31]}},ICIF_data[7],ICIF_data[30:25],ICIF_data[11:8],1'b0}  //branch
      : 32'b0;
  assign IFPD_pc = pc;
  assign IFPD_branch_result = RoBIF_branch_result;
  assign IFPD_feedback_pc = RoBIF_branch_pc;


  always @(posedge Sys_clk) begin
    if (Sys_rst) begin
      pc <= 0;
      state <= NORMAL;
      IFDC_en <= 0;
      IFPD_predict_en <= 0;
      IFPD_feedback_en <= 0;
    end else if (Sys_rdy) begin
      if (!RoBIF_pre_judge) begin  //wrong prediction
        pc <= RoBIF_next_pc;
        state <= NORMAL;
        IFDC_en <= 0;
        IFPD_predict_en <= 0;
        IFPD_feedback_en <= 1;
      end else begin
        if (RoBIF_branch_en) begin  //feedback of correct prediction
          IFPD_feedback_en <= 1;
        end
        if (state == NORMAL && ICIF_en) begin  //get a new instruction
          if (IFDC_opcode == 7'b1101111) begin : jal
            pc <= pc + imm;
            IFDC_en <= 1;
            IFPD_predict_en <= 0;
          end else if (IFDC_opcode == 7'b1100011) begin : branch
            state <= WAITING_PREDICT;
            IFDC_en <= 0;
            IFPD_predict_en <= 1;
          end else if (IFDC_opcode == 7'b1100111) begin : jalr
            state <= WAITING_RoB;
            IFDC_en <= 1;
            IFPD_predict_en <= 0;
          end else begin : other
            pc <= pc + 4;
            IFDC_en <= 1;
            IFPD_predict_en <= 0;
          end
        end else if (state == WAITING_PREDICT && PDIF_en) begin  //result from predictor
          state <= NORMAL;
          pc <= PDIF_predict_result ? pc + imm : pc + 4;
          IFDC_en <= 1;
          IFPD_predict_en <= 0;
        end else if (state == WAITING_RoB && RoBIF_jalr_en) begin  //result of jalr from RoB
          state <= NORMAL;
          pc <= RoBIF_next_pc;
        end
      end
    end
  end


endmodule
