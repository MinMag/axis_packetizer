# Define the default simulator (Icarus Verilog is standard and lightweight)
SIM ?= verilator
TOPLEVEL_LANG = verilog

# Paths to your SystemVerilog source files
VERILOG_SOURCES += $(PWD)/../hdl/crc32_parallel.sv
VERILOG_SOURCES += $(PWD)/../hdl/axis_packetizer.sv
VERILOG_SOURCES += $(PWD)/mock_primitives/ODDRE1.v
# The name of your top-level SystemVerilog module
TOPLEVEL = axis_packetizer

# The name of your Python test file (without the .py extension)
MODULE = test_axis_packetizer

# Verilator specific flags: Enable SystemVerilog parsing and bypass style checks
EXTRA_ARGS += -Wall --timing -CFLAGS "-I$(CONDA_PREFIX)/include"

# Include Cocotb's automated build rules
include $(shell cocotb-config --makefiles)/Makefile.sim

# --- Custom Waveform Target ---
.PHONY: waves
waves:
	@echo "Running simulation with waveform dumping enabled..."
	@if [ "$(SIM)" = "verilator" ]; then \
		EXTRA_ARGS="-Wall --timing --trace --trace-fst --trace-structs -CFLAGS \"-I$(CONDA_PREFIX)/include\"" $(MAKE) clean sim; \
	elif [ "$(SIM)" = "icarus" ]; then \
		WAVES=1 $(MAKE) clean sim; \
	else \
		echo "Simulator $(SIM) not explicitly configured for wave targets."; \
	\
	fi