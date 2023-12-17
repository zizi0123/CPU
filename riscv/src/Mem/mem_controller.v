module MemController (
    //sys
    input wire Sys_clk,
    input wire Sys_rst,
    input wire Sys_rdy,

    //ram
    input wire [7:0] RAMMC_data,  // data from ram
    input wire io_buffer_full,  // 1 if uart buffer is full. can't write/read to 0x30000 now.
    output reg [7:0] MCRAM_data,  // data output bus
    output reg [31:0] MCRAM_addr,  // address bus (only 17:0 is used)
    output reg MCRAM_wr,  // write/read signal (1 for write)

    //ICache
    input  wire                         ICMC_en,
    input  wire [                 31:0] ICMC_addr,
    output reg                          MCIC_en,
    output reg  [32 * BLOCK_SIZE - 1:0] MCIC_block,

    //LSB
    input  wire        LSBMC_en,
    input  wire        LSBMC_wr,          // 0:read,1:write
    input  wire [ 2:0] LSBMC_data_width,  //0:byte,1:hw,2:w
    input  wire [31:0] LSBMC_data,
    input  wire [31:0] LSBMC_addr,
    output reg         MCLSB_en,
    output reg  [ 7:0] MCLSB_data,
    output reg  [ 1:0] MCLSB_data_number
);
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


  reg [1:0] working_state;
  reg [2 + BLOCK_WIDTH - 1:0] remain_byte_num;  //a block has 4*BLOCK_SIZE bytes
  reg last_serve;  //LSB or ICACHE
  wire un_io_access;  // 1 if uart buffer is full and address is 0x30000 or 0x30004.

  assign un_io_access = io_buffer_full && (MCRAM_addr == 32'h30000 || MCRAM_addr == 32'h30004);

  always @(posedge Sys_clk) begin
    if (Sys_rst) begin
      working_state <= IDLE;
      last_serve <= LSB;
      remain_byte_num <= 0;
      MCLSB_en <= 0;
      MCIC_en <= 0;
      MCRAM_data <= 0;
      MCRAM_wr <= 1;
      MCRAM_addr <= 0;  //write 0x00 is ignored
      //check
    end else if (Sys_rdy) begin
      if (working_state == IDLE) begin
        MCLSB_en <= 0;
        MCIC_en  <= 0;
        if (ICMC_en && (!LSBMC_en || last_serve == LSB) && !un_io_access) begin  //serve for icache
          working_state <= READ;
          remain_byte_num <= 4 * BLOCK_SIZE - 1;
          last_serve <= ICACHE;
          MCRAM_addr <= ICMC_addr;
          MCRAM_wr <= 0;  //read
        end else if (LSBMC_en && !un_io_access) begin  //serve for LSB
          working_state <= LSBMC_wr ? WRITE : READ;
          remain_byte_num <= LSBMC_data_width - 1;
          last_serve <= LSB;
          MCRAM_addr <= LSBMC_addr;
          MCRAM_wr <= LSBMC_wr;
          if (LSBMC_wr) begin  //write
            case (LSBMC_data_width)
              0: MCRAM_data <= LSBMC_data[7:0];
              1: MCRAM_data <= LSBMC_data[15:8];
              4: MCRAM_data <= LSBMC_data[31:24];
              default: MCRAM_data <= 0;
            endcase
          end
        end
      end else if (working_state == READ) begin
        // if ((!LSBMC_en && last_serve == LSB) || (!ICMC_en && last_serve == IC)) begin
        //   working_state   <= IDLE;
        //   remain_byte_num <= 0;
        //   if (last_serve == LSB) begin
        //     MCLSB_en <= 0;
        //   end else begin
        //     MCIC_en <= 0;
        //   end
        //   attention why interruption ?
        // end else begin
        if (last_serve == ICACHE) begin
          //attention if BLOCK_WIDTH changed, the following code should be changed
          // MCIC_block[remain_byte_num*8+7 : remain_byte_num*8] <= RAMMC_data; 
          case (remain_byte_num)
            7: MCIC_block[63:56] <= RAMMC_data;
            6: MCIC_block[55:48] <= RAMMC_data;
            5: MCIC_block[47:40] <= RAMMC_data;
            4: MCIC_block[39:32] <= RAMMC_data;
            3: MCIC_block[31:24] <= RAMMC_data;
            2: MCIC_block[23:16] <= RAMMC_data;
            1: MCIC_block[15:8] <= RAMMC_data;
            0: MCIC_block[7:0] <= RAMMC_data;
          endcase
        end else begin
          MCLSB_en <= 1;
          MCLSB_data <= RAMMC_data;
          MCLSB_data_number <= remain_byte_num;
        end
        if (remain_byte_num > 0) begin
          remain_byte_num <= remain_byte_num - 1;
          MCRAM_addr <= MCRAM_addr + 1;
        end else begin  //remain_byte_num == 0,read finished
          working_state <= IDLE;
          MCRAM_wr <= 1;
          MCRAM_addr <= 0;  //write 0x00 is ignored
          if (last_serve == ICACHE) begin
            MCIC_en <= 1;
          end
        end
      end else if (working_state == WRITE) begin
        // if (!LSBMC_en) begin
        //   working_state <= IDLE;
        //   remain_byte_num <= 0;
        //   MCLSB_en <= 0;
        //explore why interruption ?
        // end else begin
        if (remain_byte_num > 0) begin
          remain_byte_num <= remain_byte_num - 1;
          MCRAM_addr <= MCRAM_addr + 1;
          case (remain_byte_num)
            3: MCRAM_data <= LSBMC_data[23:16];
            2: MCRAM_data <= LSBMC_data[15:8];
            1: MCRAM_data <= LSBMC_data[7:0];
          endcase
        end else begin  //remain byte num == 0, write finished
          working_state <= IDLE;
          MCRAM_wr <= 1;
          MCRAM_addr <= 0;  //write 0x00 is ignored
          MCLSB_en <= 1;
        end
      end
    end
  end

endmodule
