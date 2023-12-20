prefix = $(shell pwd) # Current Path
# Folder Path
src = $(prefix)/src
testspace = $(prefix)/testspace

sim_testcase = $(prefix)/testcase/sim
fpga_testcase = $(prefix)/testcase/fpga

sim = $(prefix)/sim
riscv_toolchain = /opt/riscv
riscv_bin = $(riscv_toolchain)/bin
sys = $(prefix)/sys

# Check if name is empty
_no_testcase_name_check:
	@$(if $(strip $(name)),, echo 'Missing Testcase Name') 
	@$(if $(strip $(name)),, exit 1)

# All build result are put at testspace
build_sim:
	@cd $(src) && iverilog -o $(testspace)/test $(sim)/testbench.v $(src)/common/block_ram/*.v $(src)/common/fifo/*.v $(src)/common/uart/*.v $(src)/*.vh $(src)/*.v 

# build_sim_test: _no_testcase_name_check
# # Compile rom.s to rom.o
# 	@$(riscv_bin)/riscv32-unknown-elf-as -o $(sys)/rom.o -march=rv32i $(sys)/rom.s 
# # Copy test case from testcase to testspace, and rename it to test.c
# 	@cp $(sim_testcase)/*$(name)*.c $(testspace)/test.c 
# # 将test.c文件编译为适用于RISC-V 32位架构的目标文件，使用基本整数指令集并启用优化，并对编译过程中的问题进行警告
# 	@$(riscv_bin)/riscv32-unknown-elf-gcc -o $(testspace)/test.o -I $(sys) -c $(testspace)/test.c -O2 -march=rv32i -mabi=ilp32 -Wall
# # 将rom.o和test.o链接为test.om，使用memory.ld文件中的链接脚本，链接时使用RISC-V工具链中的库文件
# 	@$(riscv_bin)/riscv32-unknown-elf-ld -T $(sys)/memory.ld $(sys)/rom.o $(testspace)/test.o -L $(riscv_toolchain)/riscv32-unknown-elf/lib/ -L $(riscv_toolchain)/lib/gcc/riscv32-unknown-elf/10.1.0/ -lc -lgcc -lm -lnosys -o $(testspace)/test.om
# # 将test.om转换为test.data，使用verilog格式	
# 	@$(riscv_bin)/riscv32-unknown-elf-objcopy -O verilog $(testspace)/test.om $(testspace)/test.data
# # 对输出文件test.om进行反汇编，并将反汇编结果保存为test.dump文件,包含了test.om的汇编代码表示形式
# 	@$(riscv_bin)/riscv32-unknown-elf-objdump -D $(testspace)/test.om > $(testspace)/test.dump

# run_sim:
# 	@cd $(testspace) && ./test

# clear:
# 	@rm $(sys)/rom.o $(testspace)/test*

# test_sim: build_sim build_sim_test run_sim

# .PHONY: _no_testcase_name_check build_sim build_sim_test run_sim clear test_sim
