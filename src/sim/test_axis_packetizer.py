import cocotb
import random
from asyncio import Queue
from cocotb.triggers import Timer, RisingEdge
from cocotb.clock import Clock
from cocotbext.axi import AxiStreamFrame, AxiStreamSource, AxiStreamSink, AxiStreamBus
import itertools

PACKET_OVERHEAD = 12
HEADER_SIZE = 8

def looping_pause_generator(pattern):
    """Generates an infinite cycle-by-cycle pause profile from a list pattern"""
    return itertools.cycle(pattern)

async def setup_reset(dut):
    """Helper routine to handle the initial hardware reset"""
    dut.RST_N.value = 0
    await Timer(10, unit="ns")
    await RisingEdge(dut.CLK)
    dut.RST_N.value = 1
    await RisingEdge(dut.CLK)

def validate_output_packet(in_data, in_len, transfer_num, out_data) -> bool:

    cocotb.log.info("input_len: %d out_data len: %d", in_len, len(out_data))
    if len(out_data) != in_len + PACKET_OVERHEAD:
        return False

    # for (idx, val) in in_data:
    cocotb.log.info("out_data len: %d", len(out_data))
    cocotb.log.info("in_data %x. out_data %x", int.from_bytes(in_data, byteorder='big'), int.from_bytes(out_data[8:8+in_len], byteorder='big'))
    if in_data != out_data[8:8+in_len]:
        return False

    if transfer_num != int.from_bytes(out_data[0:+1], byteorder='big'):
        return False


async def send_payload(dut, axis_source, data, transfer_num):
    dut.S_PAYLOAD_LEN.value = len(data)

    input_frame = AxiStreamFrame(data)
    dut._log.info(f"Transmitting Payload #{transfer_num} packet of length {len(data)} bytes")

    await axis_source.send(input_frame)

async def packet_producer(dut, axis_source, num_packets, expectation_queue):
    for packet_id in range(num_packets):
        num_transfers = random.randint(1,64)
        num_bytes = num_transfers * 4
        test_data = random.randbytes(num_bytes)
        metadata = {
                    "in_data": test_data,
                    "in_len": num_bytes,
                    "transfer_num": packet_id
                }
        await expectation_queue.put(metadata)
        await send_payload(dut, axis_source, test_data, packet_id)


# Unified Test Runner

async def run_packetizer_regression(dut, num_packets=50, sink_pause_gen=None, source_pause_gen=None):

    # init environment 
    # 1. Start a 250 MHz clock domain (4.0 ns period)
    cocotb.start_soon(Clock(dut.CLK, 4.0, unit="ns").start())
    

    axis_source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "S_AXIS"), dut.CLK, dut.RST_N, reset_active_level=False)
    axis_sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "M_AXIS"), dut.M_AXIS_ACLK, dut.RST_N,reset_active_level=False)

    if sink_pause_gen is not None:
        axis_sink.set_pause_generator(sink_pause_gen)
    if source_pause_gen is not None:
        axis_source.set_pause_generator(source_pause_gen)

    await setup_reset(dut)
    await RisingEdge(dut.CLK)

    failures = []
    expectation_queue = Queue()

    producer_handle = cocotb.start_soon(packet_producer(dut, axis_source, num_packets, expectation_queue))

    for packet_id in range(num_packets):

        dut._log.info("Awaiting formatted packet from m_axis...")
        output_frame = await axis_sink.recv()
        expected = await expectation_queue.get()
        test_data = expected["in_data"]
        num_bytes = expected["in_len"]
        if validate_output_packet(test_data, num_bytes, packet_id, output_frame.tdata) == False:
            msg = f"[Packet {packet_id}] MISMATCH! Input data: {test_data.hex().upper()} Output Packet: {output_frame.tdata.hex().upper()}"

            dut._log.error(msg)
            failures.append(msg)
        else: 
            dut._log.info(f"[Packet {packet_id}] Passed Cleanly.")

    await producer_handle

    assert len(failures) == 0, (
        f"\n\n!!! TEST FAILED !!!\n"
        f"Total Failures: {len(failures)} out of {num_packets} runs.\n"
        f"Summary of failures:\n" + "\n".join(failures)
    )




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

@cocotb.test(timeout_time=100, timeout_unit="us")
async def test_data_transfer_no_backpressure(dut):
    """Test that there are no AXI-Stream protocol violations under normal operation"""

    num_runs = random.randint(1,200)

    await run_packetizer_regression(dut, num_packets=num_runs)

@cocotb.test(timeout_time=100, timeout_unit="us")
async def test_data_transfer_receiver_backpressure(dut):
    """Test data transfer with backpressure on the receiving device"""

    num_runs = random.randint(1,20)

    backpressure_pattern = looping_pause_generator([1,0,1,0]) 

    await run_packetizer_regression(dut, num_packets=num_runs, sink_pause_gen=backpressure_pattern)

@cocotb.test(timeout_time=1000, timeout_unit="us")
async def test_data_transfer_no_backpressure_bubbled(dut):
    """Test that there are no AXI-Stream protocol violations under normal operation"""

    # 1. Start a 250 MHz clock domain (4.0 ns period)
    cocotb.start_soon(Clock(dut.CLK, 4.0, unit="ns").start())
    

    axis_source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "S_AXIS"), dut.CLK, dut.RST_N, reset_active_level=False)
    axis_sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "M_AXIS"), dut.M_AXIS_ACLK, dut.RST_N,reset_active_level=False)

    await setup_reset(dut)
    await RisingEdge(dut.CLK)

    
    # 7. Wait for the out-of-context master interface to capture the fully processed frame
    failures = []
    num_runs = random.randint(1,200)

    for packet_id in range(num_runs):
        num_transfers = random.randint(1,64)
        num_bytes = num_transfers * 4
        test_data = random.randbytes(num_bytes)
        await send_payload(dut, axis_source, test_data, packet_id)

        dut._log.info("Awaiting formatted packet from m_axis...")
        output_frame = await axis_sink.recv()
        if validate_output_packet(test_data, num_bytes, packet_id, output_frame.tdata) == False:
            msg = f"[Packet {packet_id}] MISMATCH! Input data: {test_data.hex().upper()} Output Packet: {output_frame.tdata.hex().upper()}"

            dut._log.error(msg)
            failures.append(msg)
        else: 
            dut._log.info(f"[Packet {packet_id}] Passed Cleanly.")

        
    assert len(failures) == 0, (
        f"\n\n!!! TEST FAILED !!!\n"
        f"Total Failures: {len(failures)} out of {num_runs} runs.\n"
        f"Summary of failures:\n" + "\n".join(failures)
    )
