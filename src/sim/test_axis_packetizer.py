import cocotb
from cocotb.triggers import Timer, RisingEdge
from cocotb.clock import Clock
from cocotbext.axi import AxiStreamFrame, AxiStreamSource, AxiStreamSink

async def setup_reset(dut):
    """Helper routine to handle the initial hardware reset"""
    dut.RST_N.value = 0
    await Timer(10, unit="ns")
    await RisingEdge(dut.CLK)
    dut.RST_N.value = 1
    await RisingEdge(dut.CLK)

@cocotb.test()
async def test_baseline_packet(dut):
    """MVP Test: Send a single unaligned packet and verify framing structure"""
    
    # 1. Start a 250 MHz clock domain (4.0 ns period)
    cocotb.start_soon(Clock(dut.CLK, 4.0, unit="ns").start())
    
    # 2. Initialize sideband configurations
    dut.S_PAYLOAD_LEN.value = 12  # 12 bytes = 3 words of payload
    
    # 3. Handle asynchronous active-low reset
    await setup_reset(dut)
    
    # 4. Wait for the module to land in IDLE state
    await RisingEdge(dut.CLK)
    
    # Your injection and scoreboard capture logic will go here!
    dut._log.info("Workspace verification environment successfully initialized!")
    await Timer(20, unit="ns")