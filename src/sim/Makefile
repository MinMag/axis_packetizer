# Define the default simulator (Icarus Verilog is standard and lightweight)
SIM ?= verilator
TOPLEVEL_LANG = verilog

# Paths to your SystemVerilog source files
VERILOG_SOURCES += $(PWD)/../hdl/crc32_parallel.sv
VERILOG_SOURCES += $(PWD)/../hdl/axis_packetizer.sv
# The name of your top-level SystemVerilog module
TOPLEVEL = axis_packetizer

# The name of your Python test file (without the .py extension)
MODULE = test_axis_packetizer

# Verilator specific flags: Enable SystemVerilog parsing and bypass style checks
EXTRA_ARGS += -Wall --timing

# Include Cocotb's automated build rules
include $(shell cocotb-config --makefiles)/Makefile.sim