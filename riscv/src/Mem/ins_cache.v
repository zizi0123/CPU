
module ICache #(
    parameter BLOCK_WIDTH = 1,
    parameter BLOCK_SIZE = 1 << BLOCK_WIDTH,  //a block has BLOCK_SIZE instructions
    parameter CACHE_WIDTH = 8,
    parameter CACHE_SIZE = 1 << CACHE_WIDTH,  //a cache has CACHE_SIZE blocks
    parameter BLOCK_NUM = 1 << CACHE_WIDTH,
    parameter ADDR_WIDTH = 32,
    parameter NORMAL = 0,
    WAITING = 1  //waiting: waiting for memory controller
) (
    //sys
    input wire Sys_clk,
    input wire Sys_rst,
    input wire Sys_rdy,

    //Mem Controller
    input  wire                         MCIC_en,
    input  wire [32 * BLOCK_SIZE - 1:0] MCIC_block,  //a instruction has 32 bits
    output reg                          ICMC_en,
    output reg  [     ADDR_WIDTH - 1:0] ICMC_addr,

    //Instruction fetcher
    input  wire                    IFIC_en,
    input  wire [ADDR_WIDTH - 1:0] IFIC_addr,
    output reg                     ICIF_en,
    output reg  [            31:0] ICIF_data,

    //Reorder Buffer
    input wire RoBIC_pre_judge
);

  reg state;  //WAITING or NORMAL
  reg discard; //the next instruction get from memory controller should be discarded,because pc has changed since waiting for memory controller (wrong prediction)
  reg block_valid[CACHE_SIZE - 1:0];
  reg [31:0] block_data[CACHE_SIZE - 1:0][BLOCK_SIZE - 1:0];
  reg [ADDR_WIDTH - 1:BLOCK_WIDTH + 2 + CACHE_WIDTH] block_tag[CACHE_SIZE - 1:0];

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





  integer i, j;

  always @(*) begin
    if (ICMC_en && MCIC_en) begin
      ICMC_en <= 0;  //disable ICMC_en immediately. 
    end
  end

  always @(posedge Sys_clk) begin
    if (Sys_rst) begin
      //invalid all blocks
      for (i = 0; i < CACHE_SIZE; i = i + 1) begin
        block_valid[i] <= 0;
      end
      state   <= NORMAL;
      ICMC_en <= 0;
      ICIF_en <= 0;
      discard <= 0;
    end else if (!RoBIC_pre_judge) begin
      ICMC_en <= 0;
      ICIF_en <= 0;
      if (state == WAITING) begin
        discard <= 1;
      end
    end else if (Sys_rdy) begin
      if (ICIF_en) begin  //instruction fetcher need one cycle to update.
        ICIF_en <= 0;
      end else begin
        if (IFIC_en && state == NORMAL) begin
          if (block_tag[IFIC_index] == IFIC_tag && block_valid[IFIC_index]) begin  //hit
            ICIF_en   <= 1;
            ICIF_data <= block_data[IFIC_index][IFIC_block_offset];
          end else begin  //miss
            state <= WAITING;  //begin waiting for memory controller
            ICIF_en <= 0;
            ICMC_en <= 1;
            ICMC_addr <= IFIC_addr - (IFIC_block_offset << 2); //ICMC addr maybe not the start of a block
          end
        end
        if (MCIC_en) begin : update
          state <= NORMAL;
          block_valid[ICMC_index] <= 1;
          block_tag[ICMC_index] <= ICMC_tag;
          // for (j = 0; j < BLOCK_SIZE; j = j + 1) begin
          //   block_data[ICMC_index][j] <= MCIC_block[j*32+31:j*32];   
          // end
          //attention if BLOCK_WIDTH changed, the following code should be changed
          block_data[ICMC_index][0] <= MCIC_block[31:0];
          block_data[ICMC_index][1] <= MCIC_block[63:32];
          if (!discard) begin  //don't need this instruction any more
            ICIF_en <= 1;
            // ICIF_data   <= MCIC_block[IFIC_block_offset*32+31:IFIC_block_offset*32];
            //attention if BLOCK_WIDTH changed, the following code should be changed
            if (IFIC_block_offset == 0) begin
              ICIF_data <= MCIC_block[31:0];
            end
            if (IFIC_block_offset == 1) begin
              ICIF_data <= MCIC_block[63:32];
            end
          end else begin
            discard <= 0;  //restore discard signal
          end
        end
      end
    end
  end
endmodule
