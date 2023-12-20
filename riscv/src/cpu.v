// RISCV32I CPU top module
// port modification allowed for debugging purposes

`include "/mnt/d/大二/RISCV-CPU/riscv/src/Mem/mem_controller.v"
`include "/mnt/d/大二/RISCV-CPU/riscv/src/Mem/ins_cache.v"
`include "/mnt/d/大二/RISCV-CPU/riscv/src/Issue/decoder.v"
`include "/mnt/d/大二/RISCV-CPU/riscv/src/Issue/dispatcher.v"
`include "/mnt/d/大二/RISCV-CPU/riscv/src/Issue/instruction_fetcher.v"
`include "/mnt/d/大二/RISCV-CPU/riscv/src/Issue/predictor.v"
`include "/mnt/d/大二/RISCV-CPU/riscv/src/Execute/reservation_station.v"
`include "/mnt/d/大二/RISCV-CPU/riscv/src/Execute/load_store_buffer.v"
`include "/mnt/d/大二/RISCV-CPU/riscv/src/WriteResult/reorder_buffer.v"
`include "/mnt/d/大二/RISCV-CPU/riscv/src/WriteResult/CDB.v"
`include "/mnt/d/大二/RISCV-CPU/riscv/src/Commit/register_file.v"

module cpu (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input  wire [ 7:0] mem_din,   // data input bus
    output wire [ 7:0] mem_dout,  // data output bus
    output wire [31:0] mem_a,     // address bus (only 17:0 is used)
    output wire        mem_wr,    // write/read signal (1 for write)

    input wire io_buffer_full,  // 1 if uart buffer is full

    output wire [31:0] dbgreg_dout  // cpu register output (debugging demo)
);

  // implementation goes here

  // Specifications:
  // - Pause cpu(freeze pc, registers, etc.) when rdy_in is low
  // - Memory read result will be returned in the next cycle. Write takes 1 cycle(no need to wait)
  // - Memory is of size 128KB, with valid address ranging from 0x0 to 0x20000
  // - I/O port is mapped to address higher than 0x30000 (mem_a[17:16]==2'b11)
  // - 0x30000 read: read a byte from input
  // - 0x30000 write: write a byte to output (write 0x00 is ignored)
  // - 0x30004 read: read clocks passed since cpu starts (in dword, 4 bytes)
  // - 0x30004 write: indicates program stop (will output '\0' through uart tx)

  parameter BLOCK_WIDTH = 1;  //a block has 2^1 instructions
  parameter BLOCK_SIZE = 1 << BLOCK_WIDTH;
  parameter CACHE_WIDTH = 8;  //a cache has 2^8 blocks
  parameter BLOCK_NUM = 1 << CACHE_WIDTH;
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
  parameter LSB = 0, ICACHE = 1,  //last_serve
  IDLE = 0, READ = 1, WRITE = 2;  //working_state


  //MemCtrller
  wire MCIC_en;
  wire [32 * BLOCK_SIZE - 1:0] MCIC_block;
  wire MCLSB_en;
  wire [7:0] MCLSB_data;
  wire [1:0] MCLSB_data_number;

  //ICache
  wire ICMC_en;
  wire [ADDR_WIDTH - 1:0] ICMC_addr;
  wire ICIF_en;
  wire [31:0] ICIF_data;

  //Instruction Fetcher
  wire IFIC_en;
  wire [ADDR_WIDTH - 1:0] IFIC_addr;
  wire IFDC_en;
  wire [ADDR_WIDTH - 1:0] IFDC_pc;
  wire [6:0] IFDC_opcode;
  wire [31:7] IFDC_remain_inst;
  wire IFDC_predict_result;
  wire IFPD_predict_en;
  wire [ADDR_WIDTH - 1:0] IFPD_pc;
  wire IFPD_feedback_en;
  wire IFPD_branch_result;
  wire [ADDR_WIDTH - 1:0] IFPD_feedback_pc;

  //Predictor
  wire PDIF_predict_result;

  //Decoder
  wire DCIF_ask_IF;
  wire DCDP_en;
  wire [ADDR_WIDTH - 1:0] DCDP_pc;
  wire [6:0] DCDP_opcode;
  wire [REG_WIDTH - 1:0] DCDP_rs1;
  wire [REG_WIDTH - 1:0] DCDP_rs2;
  wire [REG_WIDTH - 1:0] DCDP_rd;
  wire [31:0] DCDP_imm;
  wire DCDP_predict_result;

  //Dispatcher
  wire DPDC_ask_IF;  //ask IF to fetch a new instruction
  wire DPRF_en;  //attention rd to regfile is ready
  wire [EX_REG_WIDTH - 1:0] DPRF_rs1;
  wire [EX_REG_WIDTH - 1:0] DPRF_rs2;
  wire [RoB_WIDTH - 1:0] DPRF_RoB_index;  //the dependency RoB# of rd
  wire [EX_REG_WIDTH - 1:0] DPRF_rd;
  wire DPRS_en;  //send a new instruction to RS
  wire [ADDR_WIDTH - 1:0] DPRS_pc;
  wire [EX_RoB_WIDTH - 1:0] DPRS_Qj;
  wire [EX_RoB_WIDTH - 1:0] DPRS_Qk;
  wire [31:0] DPRS_Vj;
  wire [31:0] DPRS_Vk;
  wire [31:0] DPRS_imm;
  wire [6:0] DPRS_opcode;
  wire [RoB_WIDTH - 1:0] DPRS_RoB_index;
  wire DPLSB_en;  //send a new instruction to LSB
  wire [EX_RoB_WIDTH - 1:0] DPLSB_Qj;
  wire [EX_RoB_WIDTH - 1:0] DPLSB_Qk;
  wire [31:0] DPLSB_Vj;
  wire [31:0] DPLSB_Vk;
  wire [31:0] DPLSB_imm;
  wire [6:0] DPLSB_opcode;
  wire [RoB_WIDTH - 1:0] DPLSB_RoB_index;
  wire [EX_RoB_WIDTH - 1:0] DPRoB_Qj;  //prefetch:ask if Qj is ready in RoB
  wire [EX_RoB_WIDTH - 1:0] DPRoB_Qk;  //prefetch:ask if Qk is ready in RoB
  wire DPRoB_en;  //send a new instruction to RoB
  wire [ADDR_WIDTH - 1:0] DPRoB_pc;
  wire [31:0] DPRoB_imm;
  wire DPRoB_predict_result;
  wire [6:0] DPRoB_opcode;
  wire [EX_REG_WIDTH - 1:0] DPRoB_rd;

  //Reservation Station
  wire RSDP_full;  //1:RS is full
  wire RSCDB_en;
  wire [RoB_WIDTH - 1:0] RSCDB_RoB_index;
  wire [31:0] RSCDB_value;  //rd value or branch result(jump or not)
  wire [ADDR_WIDTH - 1:0] RSCDB_next_pc;

  //Load Store Buffer
  wire LSBDP_full;
  wire LSBMC_en;
  wire LSBMC_wr;  //0:read 1:write
  wire [2:0] LSBMC_data_width;
  wire [31:0] LSBMC_data;
  wire [31:0] LSBMC_addr;
  wire LSBCDB_en;
  wire [RoB_WIDTH - 1:0] LSBCDB_RoB_index;
  wire [31:0] LSBCDB_value;
  wire [RoB_WIDTH - 1:0] LSBRoB_commit_index;  //the last committed store instructi

  //Reorder Buffer
  wire RoBDP_full;
  wire [RoB_WIDTH - 1:0] RoBDP_RoB_index;
  wire RoBDP_pre_judge;  //0:mispredict 1:correct
  wire RoBDP_Qj_ready;  //RoB item Qj is ready in RoB
  wire RoBDP_Qk_ready;  //RoB item Qk is ready in RoB
  wire [31:0] RoBDP_Vj;
  wire [31:0] RoBDP_Vk;
  wire RoBIF_jalr_en;
  wire RoBIF_branch_en;
  wire RoBIF_pre_judge; //the result of the branch instruction; 0:wrong prediction; 1:correct prediction
  wire RoBIF_branch_result;  //the result of the branch instruction; 0: not taken; 1: taken
  wire [ADDR_WIDTH - 1:0] RoBIF_branch_pc;  //the pc of the branch instruction
  wire [ADDR_WIDTH - 1:0] RoBIF_next_pc;  //the pc of the next instruction for jalr/wrong prediction
  wire RoBRS_pre_judge;
  wire RoBLSB_pre_judge;
  wire RoBLSB_commit_index;
  wire RoBRF_pre_judge;
  wire RoBRF_en;  //commit a new instruction; RoB index;rd;value is valid now!
  wire [RoB_WIDTH - 1:0] RoBRF_RoB_index;
  wire [EX_REG_WIDTH - 1:0] RoBRF_rd;
  wire [31:0] RoBRF_value;

  //Register File
  wire [EX_REG_WIDTH - 1:0] RFDP_Qj;
  wire [EX_REG_WIDTH - 1:0] RFDP_Qk;
  wire [31:0] RFDP_Vj;
  wire [31:0] RFDP_Vk;

  //CDB
  wire CDBRS_LSB_en;
  wire [RoB_WIDTH - 1:0] CDBRS_LSB_RoB_index;
  wire [31:0] CDBRS_LSB_value;

  wire CDBLSB_RS_en;
  wire [RoB_WIDTH - 1:0] CDBLSB_RS_RoB_index;
  wire [31:0] CDBLSB_RS_value;

  wire CDBRoB_RS_en;
  wire [RoB_WIDTH - 1:0] CDBRoB_RS_RoB_index;
  wire [31:0] CDBRoB_RS_value;  
  wire [ADDR_WIDTH - 1:0] CDBRoB_RS_next_pc;
  wire CDBRoB_LSB_en;
  wire [RoB_WIDTH - 1:0] CDBRoB_LSB_RoB_index;
  wire [31:0] CDBRoB_LSB_value;

  wire CDBDP_RS_en;
  wire [RoB_WIDTH - 1:0] CDBDP_RS_RoB_index;
  wire [31:0] CDBDP_RS_value;
  wire CDBDP_LSB_en;
  wire [RoB_WIDTH - 1:0] CDBDP_LSB_RoB_index;
  wire [31:0] CDBDP_LSB_value;

  //MemCtrl
  MemController mem_controller(
    .Sys_clk(clk_in),
    .Sys_rst(rst_in),
    .Sys_rdy(rdy_in),

    .RAMMC_data(mem_din),
    .io_buffer_full(io_buffer_full),
    .MCRAM_data(mem_dout),
    .MCRAM_addr(mem_a),
    .MCRAM_wr(mem_wr),

    .ICMC_en(ICMC_en),
    .ICMC_addr(ICMC_addr),
    .MCIC_en(MCIC_en),
    .MCIC_block(MCIC_block),

    .LSBMC_en(LSBMC_en),
    .LSBMC_wr(LSBMC_wr),
    .LSBMC_data_width(LSBMC_data_width),
    .LSBMC_data(LSBMC_data),
    .LSBMC_addr(LSBMC_addr),
    .MCLSB_en(MCLSB_en),
    .MCLSB_data(MCLSB_data),
    .MCLSB_data_number(MCLSB_data_number)
  );

  //ICache
  ICache ins_cache(
    .Sys_clk(clk_in),
    .Sys_rst(rst_in),
    .Sys_rdy(rdy_in),

    .MCIC_en(MCIC_en),
    .MCIC_block(MCIC_block),
    .ICMC_en(ICMC_en),
    .ICMC_addr(ICMC_addr),

    .IFIC_en(IFIC_en),
    .IFIC_addr(IFIC_addr),
    .ICIF_en(ICIF_en),
    .ICIF_data(ICIF_data)
  );

  //Instruction Fetcher
  InstructionFetcher instruction_fetcher(
    .Sys_clk(clk_in),
    .Sys_rst(rst_in),
    .Sys_rdy(rdy_in),

    .ICIF_en(ICIF_en),
    .ICIF_data(ICIF_data),
    .IFIC_en(IFIC_en),
    .IFIC_addr(IFIC_addr),

    .DCIF_ask_IF(DCIF_ask_IF),
    .IFDC_en(IFDC_en),
    .IFDC_pc(IFDC_pc),
    .IFDC_opcode(IFDC_opcode),
    .IFDC_remain_inst(IFDC_remain_inst),
    .IFDC_predict_result(IFDC_predict_result),

    .PDIF_predict_result(PDIF_predict_result),
    .IFPD_predict_en(IFPD_predict_en),
    .IFPD_pc(IFPD_pc),
    .IFPD_feedback_en(IFPD_feedback_en),
    .IFPD_branch_result(IFPD_branch_result),
    .IFPD_feedback_pc(IFPD_feedback_pc),

    .RoBIF_jalr_en(RoBIF_jalr_en),
    .RoBIF_branch_en(RoBIF_branch_en),
    .RoBIF_pre_judge(RoBIF_pre_judge),
    .RoBIF_branch_result(RoBIF_branch_result),
    .RoBIF_branch_pc(RoBIF_branch_pc),
    .RoBIF_next_pc(RoBIF_next_pc)
  );


  //Predictor
  Predictor predictor(
    .Sys_clk(clk_in),
    .Sys_rst(rst_in),
    .Sys_rdy(rdy_in),

    .IFPD_predict_en(IFPD_predict_en),
    .IFPD_pc(IFPD_pc),
    .IFPD_feedback_en(IFPD_feedback_en),
    .IFPD_branch_result(IFPD_branch_result),
    .IFPD_feedback_pc(IFPD_feedback_pc),
    .PDIF_predict_result(PDIF_predict_result)
  );

  //Decoder
  Decoder decoder(
    .IFDC_en(IFDC_en),
    .IFDC_pc(IFDC_pc),
    .IFDC_opcode(IFDC_opcode),
    .IFDC_remain_inst(IFDC_remain_inst),
    .IFDC_predict_result(IFDC_predict_result),
    .DCIF_ask_IF(DCIF_ask_IF),

    .DPDC_ask_IF(DPDC_ask_IF),
    .DCDP_en(DCDP_en),
    .DCDP_pc(DCDP_pc),
    .DCDP_opcode(DCDP_opcode),
    .DCDP_rs1(DCDP_rs1),
    .DCDP_rs2(DCDP_rs2),
    .DCDP_rd(DCDP_rd),
    .DCDP_imm(DCDP_imm),
    .DCDP_predict_result(DCDP_predict_result)
  );

  //Dispatcher
  Dispatcher dispatcher(
    .Sys_clk(clk_in),
    .Sys_rst(rst_in),
    .Sys_rdy(rdy_in),

    .DCDP_en(DCDP_en),
    .DCDP_pc(DCDP_pc),
    .DCDP_opcode(DCDP_opcode),
    .DCDP_rs1(DCDP_rs1),
    .DCDP_rs2(DCDP_rs2),
    .DCDP_rd(DCDP_rd),
    .DCDP_imm(DCDP_imm),
    .DCDP_predict_result(DCDP_predict_result),

    .CDBDP_RS_en(CDBDP_RS_en),
    .CDBDP_RS_RoB_index(CDBDP_RS_RoB_index),
    .CDBDP_RS_value(CDBDP_RS_value),
    .CDBDP_LSB_en(CDBDP_LSB_en),
    .CDBDP_LSB_RoB_index(CDBDP_LSB_RoB_index),
    .CDBDP_LSB_value(CDBDP_LSB_value)
  );

  //Register File
  RegisterFile register_file(
    .Sys_clk(clk_in),
    .Sys_rst(rst_in),
    .Sys_rdy(rdy_in),

    .DPRF_en(DPRF_en),
    .DPRF_rs1(DPRF_rs1),
    .DPRF_rs2(DPRF_rs2),
    .DPRF_RoB_index(DPRF_RoB_index),
    .DPRF_rd(DPRF_rd),
    .RFDP_Qj(RFDP_Qj),
    .RFDP_Qk(RFDP_Qk),
    .RFDP_Vj(RFDP_Vj),
    .RFDP_Vk(RFDP_Vk),

    .RoBRF_pre_judge(RoBRF_pre_judge),
    .RoBRF_en(RoBRF_en),
    .RoBRF_RoB_index(RoBRF_RoB_index),
    .RoBRF_rd(RoBRF_rd),
    .RoBRF_value(RoBRF_value)
  );

  //Reservation Station
  ReservationStation reservation_station(
    .Sys_clk(clk_in),
    .Sys_rst(rst_in),
    .Sys_rdy(rdy_in),

    .DPRS_en(DPRS_en),
    .DPRS_pc(DPRS_pc),
    .DPRS_Qj(DPRS_Qj),
    .DPRS_Qk(DPRS_Qk),
    .DPRS_Vj(DPRS_Vj),
    .DPRS_Vk(DPRS_Vk),
    .DPRS_imm(DPRS_imm),
    .DPRS_opcode(DPRS_opcode),
    .DPRS_RoB_index(DPRS_RoB_index),
    .RSDP_full(RSDP_full),

    .CDBRS_LSB_en(CDBRS_LSB_en),
    .CDBRS_LSB_RoB_index(CDBRS_LSB_RoB_index),
    .CDBRS_LSB_value(CDBRS_LSB_value),
    .RSCDB_en(RSCDB_en),
    .RSCDB_RoB_index(RSCDB_RoB_index),
    .RSCDB_value(RSCDB_value),
    .RSCDB_next_pc(RSCDB_next_pc),

    .RoBRS_pre_judge(RoBRS_pre_judge)
  );

  //Reorder Buffer
  ReorderBuffer reorder_buffer(
    .Sys_clk(clk_in),
    .Sys_rst(rst_in),
    .Sys_rdy(rdy_in),

    .DPRoB_Qj(DPRoB_Qj),
    .DPRoB_Qk(DPRoB_Qk),
    .DPRoB_en(DPRoB_en),
    .DPRoB_pc(DPRoB_pc),
    .DPRoB_predict_result(DPRoB_predict_result),
    .DPRoB_opcode(DPRoB_opcode),
    .DPRoB_rd(DPRoB_rd),
    .RoBDP_full(DPRP_full),
    .RoBDP_RoB_index(RoBDP_RoB_index),
    .RoBDP_pre_judge(RoBDP_pre_judge),
    .RoBDP_Qj_ready(RoBDP_Qj_ready),
    .RoBDP_Qk_ready(RoBDP_Qk_ready),
    .RoBDP_Vj(RoBDP_Vj),
    .RoBDP_Vk(RoBDP_Vk),

    .RoBIF_jalr_en(RoBIF_jalr_en),
    .RoBIF_branch_en(RoBIF_branch_en),
    .RoBIF_pre_judge(RoBIF_pre_judge),
    .RoBIF_branch_result(RoBIF_branch_result),
    .RoBIF_branch_pc(RoBIF_branch_pc),
    .RoBIF_next_pc(RoBIF_next_pc),

    .RoBRS_pre_judge(RoBRS_pre_judge),

    .LSBRoB_commit_index(LSBRoB_commit_index),
    .RoBLSB_pre_judge(RoBLSB_pre_judge),
    .RoBLSB_commit_index(RoBLSB_commit_index),

    .CDBRoB_RS_en(CDBRoB_RS_en),
    .CDBRoB_RS_RoB_index(CDBRoB_RS_RoB_index),
    .CDBRoB_RS_value(CDBRoB_RS_value),
    .CDBRoB_RS_next_pc(CDBRoB_RS_next_pc),
    .CDBRoB_LSB_en(CDBRoB_LSB_en),
    .CDBRoB_LSB_RoB_index(CDBRoB_LSB_RoB_index),
    .CDBRoB_LSB_value(CDBRoB_LSB_value),

    .RoBRF_pre_judge(RoBRF_pre_judge),
    .RoBRF_en(RoBRF_en),
    .RoBRF_RoB_index(RoBRF_RoB_index),
    .RoBRF_rd(RoBRF_rd),
    .RoBRF_value(RoBRF_value)
  );


  //Load Store Buffer
  LoadStoreBuffer load_store_buffer(
    .Sys_clk(clk_in),
    .Sys_rst(rst_in),
    .Sys_rdy(rdy_in),

    .DPLSB_en(DPLSB_en),
    .DPLSB_Qj(DPLSB_Qj),
    .DPLSB_Qk(DPLSB_Qk),
    .DPLSB_Vj(DPLSB_Vj),
    .DPLSB_Vk(DPLSB_Vk),
    .DPLSB_imm(DPLSB_imm),
    .DPLSB_opcode(DPLSB_opcode),
    .DPLSB_RoB_index(DPLSB_RoB_index),
    .LSBDP_full(LSBDP_full),

    .MCLSB_en(MCLSB_en),
    .MCLSB_data(MCLSB_data),
    .MCLSB_data_number(MCLSB_data_number),
    .LSBMC_en(LSBMC_en),
    .LSBMC_wr(LSBMC_wr),
    .LSBMC_data_width(LSBMC_data_width),
    .LSBMC_data(LSBMC_data),
    .LSBMC_addr(LSBMC_addr),

    .CDBLSB_RS_en(CDBLSB_RS_en),
    .CDBLSB_RS_RoB_index(CDBLSB_RS_RoB_index),
    .CDBLSB_RS_value(CDBLSB_RS_value),
    .LSBCDB_en(LSBCDB_en),
    .LSBCDB_RoB_index(LSBCDB_RoB_index),
    .LSBCDB_value(LSBCDB_value),

    .RoBLSB_pre_judge(RoBLSB_pre_judge),
    .RoBLSB_commit_index(RoBLSB_commit_index),
    .LSBRoB_commit_index(LSBRoB_commit_index)
  );

  //CDB
  CDB cdb(
    .RSCDB_en(RSCDB_en),
    .RSCDB_RoB_index(RSCDB_RoB_index),
    .RSCDB_value(RSCDB_value),
    .RSCDB_next_pc(RSCDB_next_pc),
    .CDBRS_LSB_en(CDBRS_LSB_en),
    .CDBRS_LSB_RoB_index(CDBRS_LSB_RoB_index),
    .CDBRS_LSB_value(CDBRS_LSB_value),

    .LSBCDB_en(LSBCDB_en),
    .LSBCDB_RoB_index(LSBCDB_RoB_index),
    .LSBCDB_value(LSBCDB_value),
    .CDBLSB_RS_en(CDBLSB_RS_en),
    .CDBLSB_RS_RoB_index(CDBLSB_RS_RoB_index),
    .CDBLSB_RS_value(CDBLSB_RS_value),

    .CDBRoB_RS_en(CDBRoB_RS_en),
    .CDBRoB_RS_RoB_index(CDBRoB_RS_RoB_index),
    .CDBRoB_RS_value(CDBRoB_RS_value),
    .CDBRoB_RS_next_pc(CDBRoB_RS_next_pc),
    .CDBRoB_LSB_en(CDBRoB_LSB_en),
    .CDBRoB_LSB_RoB_index(CDBRoB_LSB_RoB_index),
    .CDBRoB_LSB_value(CDBRoB_LSB_value)
  );


  always @(posedge clk_in) begin
    if (rst_in) begin

    end else
    if (!rdy_in) begin

    end else begin

    end
  end


  //MemCtrl 


endmodule
