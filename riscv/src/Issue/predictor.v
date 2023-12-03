`include "./two-bit_saturated_counter.v"

module predictor(
    //sys
    input wire Sys_clk,
    input wire Sys_rst,
    input wire Sys_rdy,
    //attention not considering reset signal

    //instruction fetcher
    input  wire IFPD_predict_en, //ask for prediction
    input  wire [ADDR_WIDTH - 1:0] IFPD_pc, //pc of branch instruction
    input  wire IFPD_feedback_en, //feedback the result of branch instruction
    input  wire IFPD_branch_result, //0: not taken, 1: taken
    input  wire [ADDR_WIDTH - 1:0] IFPD_feedback_pc, //the pc of the branch instruction 
    output reg  PDIF_en,
    output reg  PDIF_predict_result //0: not taken, 1: taken
);
    parameter ADDR_WIDTH = 32;
    parameter K = 4; //hash length
    parameter HISTORY_LENGTH = 4; //history length

    wire [K - 1:0] hash_num_prediction;
    wire [HISTORY_LENGTH - 1:0] BHR_prediction;
    wire [K - 1:0] hash_num_feedback;
    wire [HISTORY_LENGTH - 1:0] BHR_feedback;
    reg  [HISTORY_LENGTH - 1:0] BHRs [K - 1:0];


    assign hash_num_prediction = IFPD_pc[K - 1 + 2:2];
    assign BHR_prediction = BHRs[hash_num_prediction];
    assign hash_num_feedback = IFPD_feedback_pc[K - 1 + 2:2];
    assign BHR_feedback = BHRs[hash_num_feedback];
    SaturatedCounter pattern_history_table [K - 1:0][HISTORY_LENGTH - 1:0];

    always @(*)begin
       //attention not considering reset signal     
       if(IFPD_predict_en)begin //ask for prediction
           PDIF_en <= 1;
           PDIF_predict_result = pattern_history_table[hash_num_prediction][BHR_prediction].predict_result;
       end
       else if(IFPD_feedback_en)begin //feedback the result of branch instruction
           PDIF_en <= 0;
           BHRs[hash_num_feedback] <= {BHRs[hash_num_feedback][HISTORY_LENGTH - 2:0],IFPD_branch_result}; //update BHR
           pattern_history_table[hash_num_feedback][BHR_feedback].branch_result = IFPD_branch_result;
       end
       else begin
           PDIF_en <= 0;
       end
    end


endmodule