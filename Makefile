SIM ?= verilator
TOPLEVEL_LANG ?= verilog

VERILOG_SOURCES = $(shell find rtl -type f -name '*.sv')
PYTHON_SOURCES = $(shell find tests -type f -name '*.py')

COCOTB_TOPLEVEL = tp_lvl

COCOTB_TEST_MODULES = tests.CPU.main_tp_lvl_targeted_tests
EXTRA_ARGS += --trace --trace-fst --trace-structs
tp_lvl: 
	$(MAKE) results.xml COCOTB_TEST_MODULES=tests.CPU.main_tp_lvl_targeted_tests
random_no_mem:
	$(MAKE) results.xml COCOTB_TEST_MODULES=tests.CPU.random.random_no_mem
random_mem:
	$(MAKE) results.xml COCOTB_TEST_MODULES=tests.CPU.random.random_with_mem
uart:
	$(MAKE) results.xml TOPLEVEL=uart_tb MODULE=tests.uart.uart_test
all: tp_lvl random_no_mem random_mem
.PHONY: tp_lvl random_no_mem random_mem uart all

 

results.xml: $(VERILOG_SOURCES) $(PYTHON_SOURCES)

include $(shell cocotb-config --makefiles)/Makefile.sim
