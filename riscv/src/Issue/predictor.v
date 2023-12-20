module predictor (
    //sys
    input wire Sys_clk,
    input wire Sys_rst,
    input wire Sys_rdy,
    //attention not considering reset signal

    //instruction fetcher
    input wire IFPD_predict_en,  //ask for prediction
    input wire [ADDR_WIDTH - 1:0] IFPD_pc,  //pc of branch instruction
    input wire IFPD_feedback_en,  //feedback the result of branch instruction
    input wire IFPD_branch_result,  //0: not taken, 1: taken
    input wire [ADDR_WIDTH - 1:0] IFPD_feedback_pc,  //the pc of the branch instruction 
    output reg PDIF_predict_result  //0: not taken, 1: taken
);
  parameter ADDR_WIDTH = 32;
  parameter HASH_WIDTH = 4;  //hash bit width
  parameter HASH_SIZE = 1 << HASH_WIDTH;  //hash size
  parameter HISTORY_LENGTH = 4;  //history length
  parameter HISTORY_SIZE = 1 << HISTORY_LENGTH;  //history size

  wire [HASH_WIDTH - 1:0] hash_num_prediction;
  wire [HISTORY_LENGTH - 1:0] BHR_prediction;
  wire [HASH_WIDTH - 1:0] hash_num_feedback;
  wire [HISTORY_LENGTH - 1:0] BHR_feedback;
  reg [HISTORY_LENGTH - 1:0] BHRs[HASH_SIZE - 1:0];
  reg [1:0] pattern_history_table[HASH_SIZE - 1:0][HISTORY_SIZE - 1:0];

  assign hash_num_prediction = IFPD_pc[HASH_WIDTH-1+2:2];
  assign BHR_prediction = BHRs[hash_num_prediction];
  assign hash_num_feedback = IFPD_feedback_pc[HASH_WIDTH-1+2:2];
  assign BHR_feedback = BHRs[hash_num_feedback];

  always @(*) begin
    //attention not considering reset signal     
    if (IFPD_predict_en) begin  //ask for prediction
      PDIF_predict_result <= pattern_history_table[hash_num_prediction][BHR_prediction][1];
    end else if (IFPD_feedback_en) begin  //feedback the result of branch instruction
      BHRs[hash_num_feedback] <= {BHRs[hash_num_feedback][HISTORY_LENGTH-1:1], IFPD_branch_result};  //update BHR
      if (IFPD_branch_result == 1) begin
        if (pattern_history_table[hash_num_feedback][BHR_feedback] != 2'b11) begin
          pattern_history_table[hash_num_feedback][BHR_feedback] <= pattern_history_table[hash_num_feedback][BHR_feedback] + 1;
        end
      end else begin
        if (pattern_history_table[hash_num_feedback][BHR_feedback] != 2'b00) begin
          pattern_history_table[hash_num_feedback][BHR_feedback] <= pattern_history_table[hash_num_feedback][BHR_feedback] - 1;
        end
      end
    end
  end


endmodule
