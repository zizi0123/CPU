module MemController #(
    parameter BLOCK_WIDTH = 1,  //a block has 2^1 instructions
    parameter BLOCK_SIZE = 1 << BLOCK_WIDTH,
    parameter CACHE_WIDTH = 8,  //a cache has 2^8 blocks
    parameter BLOCK_NUM = 1 << CACHE_WIDTH,
    parameter ADDR_WIDTH = 32,
    parameter REG_WIDTH = 5,
    parameter EX_REG_WIDTH = 6,  //extra one bit for empty reg
    parameter NON_REG = 6'b100000,
    parameter RoB_WIDTH = 4,
    parameter EX_RoB_WIDTH = 5,
    parameter LSB_WIDTH = 3,
    parameter EX_LSB_WIDTH = 4,
    parameter LSB_SIZE = 1 << LSB_WIDTH,
    parameter NON_DEP = 1 << RoB_WIDTH,  //no dependency
    parameter LSB = 0,
    ICACHE = 1,  //last_serve
    parameter IDLE = 0,
    READ = 1,
    WRITE = 2  //MC_state
) (
    //sys
    input wire Sys_clk,
    input wire Sys_rst,
    input wire Sys_rdy,

    //ram
    input wire [7:0] RAMMC_data,  // data from ram
    input wire io_buffer_full,  // 1 if uart buffer is full. can't write/read to 0x30000 now.
    output reg [7:0] MCRAM_data,  // data output bus
    output reg [ADDR_WIDTH - 1:0] MCRAM_addr,  // address bus (only 17:0 is used)
    output reg MCRAM_wr,  // write/read signal (1 for write)

    //ICache
    input  wire                         ICMC_en,
    input  wire [     ADDR_WIDTH - 1:0] ICMC_addr,
    output reg                          MCIC_en,
    output reg  [32 * BLOCK_SIZE - 1:0] MCIC_block,

    //LSB
    input  wire                    LSBMC_en,
    input  wire                    LSBMC_wr,          // 0:read,1:write
    input  wire [             2:0] LSBMC_data_width,  //0:byte,1:hw,2:w
    input  wire [            31:0] LSBMC_data,
    input  wire [ADDR_WIDTH - 1:0] LSBMC_addr,
    output reg                     MCLSB_r_en,
    output reg                     MCLSB_w_en,
    output reg  [            31:0] MCLSB_data
);

  reg [1:0] MC_state;  //IDLE,READ,WRITE
  reg [3 + BLOCK_WIDTH - 1:0] r_byte_num;  //a block has 4*BLOCK_SIZE bytes
  reg [2:0] w_byte_num;  //write byte num
  reg last_serve;  //LSB or ICACHE
  wire stop_write = 0;  // 1 if uart buffer is full write to address 0x30000 or 0x30004.

  // assign stop_write = io_buffer_full && LSBMC_en && LSBMC_wr && (LSBMC_addr == 32'h30000 || LSBMC_addr == 32'h30004);

  always @(posedge Sys_clk) begin
    if (Sys_rst) begin
      MC_state <= IDLE;
      last_serve <= LSB;
      r_byte_num <= 0;
      w_byte_num <= 0;
      MCLSB_r_en <= 0;
      MCLSB_w_en <= 0;
      MCIC_en <= 0;
      MCRAM_data <= 0;
      MCRAM_wr <= 0;
      MCRAM_addr <= 0;
      //check
    end else if (Sys_rdy) begin
      if (MC_state == IDLE) begin
        MCLSB_r_en <= 0;
        MCLSB_w_en <= 0;
        MCIC_en <= 0;
        if (ICMC_en && !MCIC_en && (!LSBMC_en || last_serve == LSB)) begin  //serve for icache
          MC_state   <= READ;
          r_byte_num <= 0;
          last_serve <= ICACHE;
          MCRAM_addr <= ICMC_addr;
          MCRAM_wr   <= 0;  //read
        end else if (LSBMC_en &&((LSBMC_wr && !MCLSB_w_en)||(!LSBMC_wr && !MCLSB_r_en)) && !stop_write) begin  //serve for LSB
          MC_state   <= LSBMC_wr ? WRITE : READ;
          last_serve <= LSB;
          MCRAM_addr <= LSBMC_addr;
          MCRAM_wr   <= LSBMC_wr ? 1 : 0;
          if (LSBMC_wr) begin  //write
            w_byte_num <= 1;
            MCRAM_data <= LSBMC_data[7:0];
          end else begin  //read
            r_byte_num <= 0;  //read result will be returned in the next cycle! so the next posedge Ram start to read, and one more posedge Ram finish reading the first byte
          end
        end
      end else if (MC_state == READ) begin
        // if ((!LSBMC_en && last_serve == LSB) || (!ICMC_en && last_serve == IC)) begin
        //   MC_state   <= IDLE;
        //   r_byte_num <= 0;
        //   if (last_serve == LSB) begin
        //     MCLSB_en <= 0;
        //   end else begin
        //     MCIC_en <= 0;
        //   end
        //   attention why interruption ?
        // end else begin
        //attention if BLOCK_WIDTH changed, the following code should be changed
        // MCIC_block[r_byte_num*8+7 : r_byte_num*8] <= RAMMC_data; 
        if (last_serve == ICACHE) begin
          case (r_byte_num)
            1: MCIC_block[7:0] <= RAMMC_data;
            2: MCIC_block[15:8] <= RAMMC_data;
            3: MCIC_block[23:16] <= RAMMC_data;
            4: MCIC_block[31:24] <= RAMMC_data;
            5: MCIC_block[39:32] <= RAMMC_data;
            6: MCIC_block[47:40] <= RAMMC_data;
            7: MCIC_block[55:48] <= RAMMC_data;
            8: MCIC_block[63:56] <= RAMMC_data;
          endcase
        end else begin
          case (r_byte_num)
            1: MCLSB_data[7:0] <= RAMMC_data;
            2: MCLSB_data[15:8] <= RAMMC_data;
            3: MCLSB_data[23:16] <= RAMMC_data;
            4: MCLSB_data[31:24] <= RAMMC_data;
          endcase
        end
        if((last_serve == ICACHE && r_byte_num < 4 * BLOCK_SIZE) || (last_serve == LSB && r_byte_num < LSBMC_data_width)) begin
          r_byte_num <= r_byte_num + 1;
          MCRAM_addr <= MCRAM_addr + 1;
        end else begin  //read finished
          MC_state   <= IDLE;
          MCRAM_wr   <= 0;
          MCRAM_addr <= 0;
          r_byte_num <= 0;
          if (last_serve == ICACHE) begin
            MCIC_en <= 1;
          end else begin
            MCLSB_r_en <= 1;
          end
        end
      end else if (MC_state == WRITE && !stop_write) begin
        // if (!LSBMC_en) begin
        //   MC_state <= IDLE;
        //   w_byte_num <= 0;
        //   MCLSB_en <= 0;
        //explore why interruption ?
        // end else begin
        if (w_byte_num < LSBMC_data_width) begin
          w_byte_num <= w_byte_num + 1;
          MCRAM_addr <= MCRAM_addr + 1;
          case (w_byte_num)
            1: MCRAM_data <= LSBMC_data[15:8];
            2: MCRAM_data <= LSBMC_data[23:16];
            3: MCRAM_data <= LSBMC_data[31:24];
          endcase
        end else begin  //remain byte num == 0, write finished
          MC_state   <= IDLE;
          MCRAM_wr   <= 0;
          MCRAM_addr <= 0;
          MCLSB_w_en <= 1;
          w_byte_num <= 0;
        end
      end
    end
  end

endmodule
