module RegisterFile #(
    parameter REG_WIDTH = 5,
    parameter EX_REG_WIDTH = 6,
    parameter NON_REG = 6'b100000,
    parameter REG_SIZE = 1 << REG_WIDTH,
    parameter RoB_WIDTH = 8,
    parameter EX_RoB_WIDTH = 9,
    parameter RoB_SIZE = 1 << RoB_WIDTH,
    parameter NON_DEP = 9'b100000000  //no dependency
) (
    //sys
    input wire Sys_clk,
    input wire Sys_rst,
    input wire Sys_rdy,

    //Dispatcher
    input wire DPRF_en,
    input wire [EX_REG_WIDTH - 1:0] DPRF_rs1,
    input wire [EX_REG_WIDTH - 1:0] DPRF_rs2,
    input wire [RoB_WIDTH - 1:0] DPRF_RoB_index,  //the dependency RoB# of rd
    input wire [EX_REG_WIDTH - 1:0] DPRF_rd,
    output wire [EX_RoB_WIDTH - 1:0] RFDP_Qj,
    output wire [EX_RoB_WIDTH - 1:0] RFDP_Qk,
    output wire [31:0] RFDP_Vj,
    output wire [31:0] RFDP_Vk,

    //RoB
    input wire RoBRF_pre_judge,  //this is instant signal 0:mispredict 1:correct if mispredict,
    input wire RoBRF_en,  //commit a new instruction, RoB index,rd,value is valid now!
    input wire [RoB_WIDTH - 1:0] RoBRF_RoB_index,
    input wire [EX_REG_WIDTH - 1:0] RoBRF_rd,
    input wire [31:0] RoBRF_value
);

  reg [31:0] registers[REG_SIZE - 1:0];
  reg [EX_RoB_WIDTH - 1:0] dependency[REG_SIZE - 1:0];

  //output Qj,Qk,Vj,Vk immediately
  assign RFDP_Qj = (!RoBRF_pre_judge || DPRF_rs1 == NON_REG || (RoBRF_en && dependency[DPRF_rs1] == RoBRF_RoB_index)) ? NON_DEP : dependency[DPRF_rs1];
  assign RFDP_Qk = (!RoBRF_pre_judge || DPRF_rs2 == NON_REG || (RoBRF_en && dependency[DPRF_rs2] == RoBRF_RoB_index)) ? NON_DEP : dependency[DPRF_rs2];
  assign RFDP_Vj = (DPRF_rs1 == NON_REG) ? 0 : ((RoBRF_en && dependency[DPRF_rs1] == RoBRF_RoB_index) ? RoBRF_value : ((dependency[DPRF_rs1] == NON_DEP) ? registers[DPRF_rs1] : 0));
  assign RFDP_Vk = (DPRF_rs2 == NON_REG) ? 0 : ((RoBRF_en && dependency[DPRF_rs2] == RoBRF_RoB_index) ? RoBRF_value : ((dependency[DPRF_rs2] == NON_DEP) ? registers[DPRF_rs2] : 0));



`ifdef DEBUG
  integer idx;
  initial begin
    $dumpfile("test.vcd");
    for (idx = 0; idx < REG_SIZE; idx++) begin
      $dumpvars(0, registers[idx], dependency[idx]);
    end
  end
`endif

  integer i;

  //update regsiter value and register dependency at posedge
  always @(posedge Sys_clk) begin
    if (Sys_rst) begin
      for (i = 0; i < REG_SIZE; i = i + 1) begin
        registers[i]  <= 0;
        dependency[i] <= NON_DEP;
      end
    end else if (Sys_rdy) begin
      if (!RoBRF_pre_judge) begin  //if the commit instruction is branch, then there's no rd to commit
        for (i = 0; i < REG_SIZE; i = i + 1) begin
          dependency[i] <= NON_DEP;  //clear dependency
        end
      end else begin
        if (RoBRF_en && RoBRF_rd != NON_REG && RoBRF_rd != 5'b00000) begin  //commit to register file. write to zero is ignored
          registers[RoBRF_rd] <= RoBRF_value;  //update register value
          if ((dependency[RoBRF_rd] == RoBRF_RoB_index) && (!DPRF_en || DPRF_rd != RoBRF_rd)) begin
            dependency[RoBRF_rd] <= NON_DEP;  //clear dependency
          end
        end
        if (DPRF_en && (DPRF_rd != NON_REG) && (DPRF_rd != 5'b00000)) begin  //update dependency
          dependency[DPRF_rd] <= DPRF_RoB_index;
        end
      end
    end
  end



endmodule
