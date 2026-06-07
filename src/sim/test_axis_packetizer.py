import cocotb
from cocotb.triggers import Timer, RisingEdge
from cocotb.clock import Clock
from cocotbext.axi import AxiStreamFrame, AxiStreamSource, AxiStreamSink, AxiStreamBus

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

@cocotb.test(timeout_time=10, timeout_unit="us")
async def test_no_axis_violations(dut):
    """Test that there are no AXI-Stream protocol violations under normal operation"""

    # 1. Start a 250 MHz clock domain (4.0 ns period)
    cocotb.start_soon(Clock(dut.CLK, 4.0, unit="ns").start())
    
    # 2. Initialize sideband configurations
    dut.S_PAYLOAD_LEN.value = 12  # 12 bytes = 3 words of payload

    axis_source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "S_AXIS"), dut.CLK, dut.RST_N, reset_active_level=False)
    axis_sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "M_AXIS"), dut.CLK, dut.RST_N,reset_active_level=False)

    await setup_reset(dut)
    await RisingEdge(dut.CLK)

    test_data = bytes([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC])
    input_frame = AxiStreamFrame(test_data)

    # 6. Inject the frame into the slave interface non-blocking
    dut._log.info("Injecting 12-byte payload into s_axis...")
    await axis_source.send(input_frame)
    
    # 7. Wait for the out-of-context master interface to capture the fully processed frame
    dut._log.info("Awaiting formatted packet from m_axis...")
    output_frame = await axis_sink.recv()
    
    # 8. Log the captured frame results
    dut._log.info(f"Captured Output Frame Hex: {output_frame.tdata.hex().upper()}")
    dut._log.info(f"Captured Output Frame Byte Count: {len(output_frame.tdata)}")
