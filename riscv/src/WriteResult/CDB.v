module CDB #(
    parameter ADDR_WIDTH = 32,
    parameter REG_WIDTH = 5,
    parameter EX_REG_WIDTH = 6,  //extra one bit for empty reg
    parameter NON_REG = 1 << REG_WIDTH,
    parameter RoB_WIDTH = 4,
    parameter EX_RoB_WIDTH = 5,
    parameter RS_WIDTH = 3,
    parameter EX_RS_WIDTH = 4,
    parameter RS_SIZE = 1 << RS_WIDTH,
    parameter NON_DEP = 1 << RoB_WIDTH  //no dependency
) (
    //RS
    input wire RSCDB_en,
    input wire [RoB_WIDTH - 1:0] RSCDB_RoB_index,
    input wire [31:0] RSCDB_value,
    input wire [ADDR_WIDTH - 1:0] RSCDB_next_pc,
    output wire CDBRS_LSB_en,
    output wire [RoB_WIDTH - 1:0] CDBRS_LSB_RoB_index,
    output wire [31:0] CDBRS_LSB_value,

    //LSB
    input wire LSBCDB_en,
    input wire [RoB_WIDTH - 1:0] LSBCDB_RoB_index,
    input wire [31:0] LSBCDB_value,
    output wire CDBLSB_RS_en,
    output wire [RoB_WIDTH - 1:0] CDBLSB_RS_RoB_index,
    output wire [31:0] CDBLSB_RS_value,

    //RoB
    output wire CDBRoB_RS_en,
    output wire [RoB_WIDTH - 1:0] CDBRoB_RS_RoB_index,
    output wire [31:0] CDBRoB_RS_value,
    output wire [ADDR_WIDTH - 1:0] CDBRoB_RS_next_pc,
    output wire CDBRoB_LSB_en,
    output wire [RoB_WIDTH - 1:0] CDBRoB_LSB_RoB_index,
    output wire [31:0] CDBRoB_LSB_value,

    //Dispatcher
    output wire CDBDP_RS_en,
    output wire [RoB_WIDTH - 1:0] CDBDP_RS_RoB_index,
    output wire [31:0] CDBDP_RS_value,
    output wire CDBDP_LSB_en,
    output wire [RoB_WIDTH - 1:0] CDBDP_LSB_RoB_index,
    output wire [31:0] CDBDP_LSB_value
);

  assign CDBRS_LSB_en = LSBCDB_en,
      CDBRS_LSB_RoB_index = LSBCDB_RoB_index,
      CDBRS_LSB_value = LSBCDB_value,
      CDBRoB_LSB_en = LSBCDB_en,
      CDBRoB_LSB_RoB_index = LSBCDB_RoB_index,
      CDBRoB_LSB_value = LSBCDB_value;

  assign CDBLSB_RS_en = RSCDB_en,
      CDBLSB_RS_RoB_index = RSCDB_RoB_index,
      CDBLSB_RS_value = RSCDB_value,
      CDBRoB_RS_en = RSCDB_en,
      CDBRoB_RS_RoB_index = RSCDB_RoB_index,
      CDBRoB_RS_value = RSCDB_value,
      CDBRoB_RS_next_pc = RSCDB_next_pc;

  assign CDBDP_RS_en = RSCDB_en,
      CDBDP_RS_RoB_index = RSCDB_RoB_index,
      CDBDP_RS_value = RSCDB_value,
      CDBDP_LSB_en = LSBCDB_en,
      CDBDP_LSB_RoB_index = LSBCDB_RoB_index,
      CDBDP_LSB_value = LSBCDB_value;

endmodule
