
module ICache (
    //sys
    input wire Sys_clk,
    input wire Sys_rst,
    input wire Sys_rdy,

    //Mem Controller
    input  wire                         MCIC_en,
    input  wire [32 * BLOCK_SIZE - 1:0] MCIC_block,  //a instruction has 32 bits
    output wire                         ICMC_en,
    output reg  [     ADDR_WIDTH - 1:0] ICMC_addr,

    //Instruction fetcher
    input  wire                    IFIC_en,
    input  wire [ADDR_WIDTH - 1:0] IFIC_addr,
    output wire                    ICIF_en,
    output reg  [            31:0] ICIF_data
);

  parameter BLOCK_WIDTH = 1;  //a block has 2^1 instructions
  parameter BLOCK_SIZE = 1 << BLOCK_WIDTH;
  parameter CACHE_WIDTH = 8;  //a cache has 2^8 blocks
  parameter BLOCK_NUM = 1 << CACHE_WIDTH;
  parameter ADDR_WIDTH = 32;

  reg block_valid[(1 << CACHE_WIDTH) - 1:0];
  reg [31:0] block_data[(1 << CACHE_WIDTH) - 1:0][BLOCK_SIZE - 1:0];
  reg [ADDR_WIDTH - 1:BLOCK_WIDTH + 2 + CACHE_WIDTH] block_tag[(1 << CACHE_WIDTH) - 1:0];

  wire [BLOCK_WIDTH - 1:0] IFIC_block_offset;
  wire [CACHE_WIDTH - 1:0] IFIC_index;
  wire [ADDR_WIDTH - 1:BLOCK_WIDTH + 2 + CACHE_WIDTH] IFIC_tag;
  wire [BLOCK_WIDTH - 1:0] ICMC_block_offset;
  wire [CACHE_WIDTH - 1:0] ICMC_index;
  wire [ADDR_WIDTH - 1:BLOCK_WIDTH + 2 + CACHE_WIDTH] ICMC_tag;

  assign IFIC_block_offset = IFIC_addr[BLOCK_WIDTH-1+2:2];  //the last 2 bits of  address is 00
  assign IFIC_index = IFIC_addr[BLOCK_WIDTH+2+CACHE_WIDTH-1:BLOCK_WIDTH+2];
  assign IFIC_tag = IFIC_addr[ADDR_WIDTH-1:BLOCK_WIDTH+2+CACHE_WIDTH];
  assign ICMC_block_offset = ICMC_addr[BLOCK_WIDTH-1+2:2];
  assign ICMC_index = ICMC_addr[BLOCK_WIDTH+2+CACHE_WIDTH-1:BLOCK_WIDTH+2];
  assign ICMC_tag = ICMC_addr[ADDR_WIDTH-1:BLOCK_WIDTH+2+CACHE_WIDTH];

  reg ICMC_en_reg;
  reg ICIF_en_reg;
  reg state;  //0:busy, 1:idle

  assign ICMC_en = ICMC_en_reg;
  assign ICIF_en = ICIF_en_reg;

  integer i,j;

  always @(posedge Sys_clk) begin
    if (Sys_rst) begin : reset
      //assign block_valid to 0
      for (i = 0; i < 2 ** CACHE_WIDTH; i = i + 1) begin
        block_valid[i] <= 0;
      end
      state <= 1;
      ICMC_en_reg <= 0;
      ICIF_en_reg <= 0;
    end 
    else if (Sys_rdy) begin : work
      if (MCIC_en) begin : update
        state <= 1;
        block_valid[ICMC_index] <= 1;
        block_tag[ICMC_index] <= ICMC_tag;
        for(j = 0; j < BLOCK_SIZE; j = j + 1) begin
          block_data[ICMC_index][j] <= MCIC_block[j*32+31:j*32];   //attention ??????????????shittttttt
        end
        ICIF_en_reg <= 1;
        ICIF_data <= MCIC_block[IFIC_block_offset*32+31:IFIC_block_offset*32];
      end 
      else if (IFIC_en && state) begin
        if (block_tag[IFIC_index] == IFIC_tag && block_valid[IFIC_index]) begin  //hit
          ICIF_en_reg <= 1;
          ICIF_data   <= block_data[IFIC_index][IFIC_block_offset];
        end 
        else begin
          state <= 0;  //begin waiting for memory controller
          ICIF_en_reg <= 0;
          ICMC_en_reg <= 1;
          ICMC_addr <= IFIC_addr;
        end
      end
    end
  end
  // module implementation here
endmodule
