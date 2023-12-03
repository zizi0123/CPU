`include "../define.v"

module MC (
    //sys
    input wire Sys_clk,
    input wire Sys_rst,
    input wire Sys_rdy,

    //ram
    input  wire [ 7:0] RAMMC_data,     // data input bus
    output reg  [ 7:0] MCRAM_data,     // data output bus
    output reg  [31:0] MCRAM_addr,     // address bus (only 17:0 is used)
    output reg         MCRAM_wr,       // write/read signal (1 for write)
    input  wire        io_buffer_full, // 1 if uart buffer is full

    //ICache
    input  wire                ICMC_en,
    input  wire [        31:0] ICMC_addr,
    output reg                 MCIC_en,
    output reg  [`BLOCK_RANGE] MCIC_block,

    //LSB
    input  wire        LSBMC_en,
    input  wire        LSBMC_wr,          // write/read signal (1 for write)
    input  wire [ 1:0] LSBMC_data_width,  //0:byte,1:hw,2:w
    input  wire [ 7:0] LSBMC_data,
    input  wire [31:0] LSBMC_addr,
    output reg         MCLSB_en,
    output reg  [ 7:0] MCLSB_data
);

  parameter LSB = 0, ICACHE = 1,  //last_serve
  IDLE = 0, READ = 1, WRITE = 2;  //working_state


  reg [              2:0 ] working_state;
  reg [`BLOCK_SIZE_RANGE]  remain_byte_num;
  reg                      last_serve;

  always @(posedge Sys_clk) begin
    if (Sys_rst) begin
      working_state <= IDLE;
      remain_byte_num <= 0;
      last_serve <= 0;
      remain_byte_num <= 0;
      MCLSB_en <= 0;
      MCIC_en <= 0;
      MCRAM_data <= 0;
      MCRAM_wr <= 0;
      MCRAM_addr <= 0;  //write 0x00 is ignored
      //check
    end else if (!Sys_rdy || io_buffer_full) begin  //explore io_buffer_full??
      //do nothing 
    end else begin
      if (working_state == IDLE) begin
        if (ICMC_en && (!LSBMC_en || last_serve == LSB)) begin  //serve for instruction cache
          working_state <= READ;
          remain_byte_num <= `BLOCK_SIZE;
          last_serve <= ICACHE;
          MCLSB_en <= 0;
          MCIC_en <= 0;
          MCRAM_addr <= ICMC_addr;
          MCRAM_wr <= 0;  //read
          MCRAM_data <= 0;
        end else if (LSBMC_en) begin
          work_state <= LSBMC_wr ? WRITE : READ;
          remain_byte_num <= LSBMC_data_width;
          last_serve <= LSB;
          MCLSB_en <= 0;
          MCIC_en <= 0;
          MCRAM_addr <= LSBMC_addr;
          MCRAM_wr <= LSBMC_wr;
          MCRAM_data <= LSBMC_wr ? LSBMC_data : 0;
        end
      end else if (working_state == READ) begin
        if ((!LSBMC_en && last_serve == LSB) || (!ICMC_en && last_serve == IC)) begin
          working_state   <= IDLE;
          remain_byte_num <= 0;
          if (last_serve == LSB) begin
            MCLSB_en <= 0;
          end else begin
            MCIC_en <= 0;
          end
          //explore why interruption ?
        end else begin
          if (remain_byte_num > 1) begin
            remain_byte_num <= remain_byte_num - 1;
            MCRAM_addr <= MCRAM_addr + 1;
            if (last_serve == IC) begin
              MCIC_block[(remain_byte_num-1)*8-1 : (remain_byte_num-1)*8-8] <= RAMMC_data;
            end else begin
              MCLSB_data[(remain_byte_num-1)*8-1 : (remain_byte_num-1)*8-8] <= RAMMC_data;
            end
          end else if (remain_byte_num == 1) begin
            MCRAM_wr   <= 0;
            MCRAM_addr <= 0;  //write 0x00 is ignored
            if (last_serve == IC) begin
              MCIC_en <= 1;
            end else begin
              MCLSB_en <= 1;
            end
            remain_byte_num <= 0;
            working_state   <= IDLE;
            //check 是否需要多留一个周期，把 MCLSB_en/MCIC_en 改成0?
          end
        end
      end else if (working_state == WRITE && !io_buffer_full) begin
        if (!LSBMC_en) begin
          working_state <= IDLE;
          remain_byte_num <= 0;
          MCLSB_en <= 0;
          //explore why interruption ?
        end else begin
          if (remain_byte_num > 1) begin
            remain_byte_num <= remain_byte_num - 1;
            MCRAM_addr <= MCRAM_addr + 1;
            MCRAM_data <= LSBMC_data[(remain_byte_num-1)*8-1 : (remain_byte_num-1)*8-8];
          end else if (remain_byte_num == 1) begin
            MCRAM_wr <= 0;
            MCRAM_addr <= 0;  //write 0x00 is ignored
            MCLSB_en <= 1;
            remain_byte_num <= 0;
            working_state <= IDLE;
            //check 是否需要多留一个周期，把 MCLSB_en 改成0?
          end
        end
      end
    end
  end

endmodule
