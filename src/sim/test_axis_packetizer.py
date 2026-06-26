import cocotb
import random
import zlib
from asyncio import Queue
from cocotb.triggers import Timer, RisingEdge
from cocotb.clock import Clock
from cocotbext.axi import AxiStreamFrame, AxiStreamSource, AxiStreamSink, AxiStreamBus
import itertools
import numpy as np

PACKET_OVERHEAD = 12
HEADER_SIZE = 8
MAGIC_NUM = 0x63DF

TEST_TIMEOUT_US = 2000

MAX_RUNS = 100
PAUSE_PATTERN_LEN = 10
MAX_TRANSFER_LEN = 100

def looping_pause_generator(pattern):
    """Generates an infinite cycle-by-cycle pause profile from a list pattern"""

    if (0 not in pattern): 
        cocotb.log.info("No-0 busy pattern!, replacing with [0,1] pattern")
        return itertools.cycle([0,1])
    
    return itertools.cycle(pattern)

async def setup_reset(dut):
    """Helper routine to handle the initial hardware reset"""
    dut.RST_N.value = 0
    await Timer(10, unit="ns")
    await RisingEdge(dut.CLK)
    dut.RST_N.value = 1
    await RisingEdge(dut.CLK)

def validate_output_packet(in_data, in_len, transfer_num, out_data, check_crc=False) -> bool:

    cocotb.log.info("input_len: %d out_data len: %d", in_len, len(out_data))
    for i in range (8):
        cocotb.log.info("%x", out_data[i])

    if int.from_bytes(out_data[0:2], byteorder='little') != MAGIC_NUM:
        cocotb.log.warning("magic number wrong")
        return False

    if len(out_data) != int.from_bytes(out_data[4:6], byteorder='little') + PACKET_OVERHEAD:
        cocotb.log.warning("%x", int.from_bytes(out_data[4:6], byteorder='little'))
        cocotb.log.warning("Packet length does not match payload_len field! %d, %d", len(out_data),  int.from_bytes(out_data[4:6], byteorder='little') + PACKET_OVERHEAD)
        return False

    if len(out_data) != in_len + PACKET_OVERHEAD:
        return False

    # for (idx, val) in in_data:
    cocotb.log.info("out_data len: %d", len(out_data))
    cocotb.log.info("in_data %x. out_data %x", int.from_bytes(in_data, byteorder='little'), int.from_bytes(out_data[8:8+in_len], byteorder='little'))
    if in_data != out_data[8:8+in_len]:
        return False

    if transfer_num != int.from_bytes(out_data[2:4], byteorder='little'):
        cocotb.log.warning("transfer num mismatch")
        return False
    
    if check_crc:
        # canonical CRC over payload as-is
        correct_crc = zlib.crc32(in_data)

        cocotb.log.info("expected crc: %x", correct_crc)

        # Compare against received CRC (4 bytes at end of packet)
        rx_crc_bytes = out_data[8+in_len:8+in_len+4]
        rx_crc_le = int.from_bytes(rx_crc_bytes, byteorder='little')

        cocotb.log.info("RX CRC bytes: %s => LE: 0x%08x", rx_crc_bytes.hex(), rx_crc_le)

        if correct_crc != rx_crc_le:
            cocotb.log.warning("CRC mismatch! Expected: %x Received: %x", correct_crc, rx_crc_le)
            return False
        
    return True



async def drive_sideband_len(dut, length_queue, num_packets):
    packets_done = 0
    while packets_done != num_packets:
        await RisingEdge(dut.CLK)
        # Only update the length if the bus is idle OR on the cycle after TLAST is accepted
        if packets_done == 0 or (dut.S_AXIS_TVALID.value == 1 and dut.S_AXIS_TREADY.value == 1 and dut.S_AXIS_TLAST.value == 1):
            if not length_queue.empty():
                dut.S_PAYLOAD_LEN.value = length_queue.get_nowait()
                packets_done += 1

async def send_payload(dut, axis_source, data, transfer_num):

    input_frame = AxiStreamFrame(data)
    dut._log.info(f"Transmitting Payload #{transfer_num} packet of length {len(data)} bytes")

    await axis_source.send(input_frame)

async def packet_producer(dut, axis_source, num_packets, expectation_queue):
    length_queue = Queue()
    payload_len_handle = cocotb.start_soon(drive_sideband_len(dut, length_queue, num_packets))
    for packet_id in range(num_packets):
        num_transfers = random.randint(1,MAX_TRANSFER_LEN)
        num_bytes = num_transfers * 4
        test_data = random.randbytes(num_bytes)
        metadata = {
                    "in_data": test_data,
                    "in_len": num_bytes,
                    "transfer_num": packet_id
                }
        await expectation_queue.put(metadata)
        await length_queue.put(num_bytes)
        await send_payload(dut, axis_source, test_data, packet_id)

    await payload_len_handle


# Unified Test Runner

async def run_packetizer_regression(dut, num_packets=50, sink_pause_gen=None, source_pause_gen=None, crc_check=False):

    # init environment 
    # 1. Start a 250 MHz clock domain (4.0 ns period)
    cocotb.start_soon(Clock(dut.CLK, 4.0, unit="ns").start())
    await setup_reset(dut);

    axis_source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "S_AXIS"), dut.CLK, dut.RST_N, reset_active_level=False)
    axis_sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "M_AXIS"), dut.CLK, dut.RST_N,reset_active_level=False)

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
        if validate_output_packet(test_data, num_bytes, packet_id, output_frame.tdata, check_crc=crc_check) == False:
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

@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def test_data_transfer_no_backpressure(dut):
    """Test that there are no AXI-Stream protocol viooutput_data_tvalid_q && M_AXIS_TREADYlations under normal operation"""

    num_runs = random.randint(1,MAX_RUNS)

    await run_packetizer_regression(dut, num_packets=num_runs)

@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def test_data_transfer_receiver_backpressure_10_pattern(dut):
    """Test data transfer with backpressure on the receiving device"""

    num_runs = random.randint(1,MAX_RUNS)

    backpressure_pattern = looping_pause_generator([1,0,1,0]) 

    await run_packetizer_regression(dut, num_packets=num_runs, sink_pause_gen=backpressure_pattern)

@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def test_functional_receiver_backpressure_rand(dut):
    """Test data transfer with random receiving backpressure"""

    num_runs = random.randint(1,MAX_RUNS)

    loop_pattern = [random.randint(0,1) for _ in range(10)]

    backpressure_pattern = looping_pause_generator(loop_pattern)

    await run_packetizer_regression(dut, num_packets=num_runs, sink_pause_gen=backpressure_pattern)

@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def test_functional_transmitter_frontpressure_rand(dut):
    """Test data transfer with random transmitter frontpressure"""

    num_runs = random.randint(1,MAX_RUNS)

    loop_pattern = [random.randint(0,1) for _ in range(10)]

    frontpressure_pattern = looping_pause_generator(loop_pattern)

    await run_packetizer_regression(dut, num_packets=num_runs, source_pause_gen=frontpressure_pattern)

@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def functional_transmitter_receiver_backpressure_rand(dut):
    """Test data transfer correctness with random transmitter and receiver throttling"""


    num_runs = random.randint(1,MAX_RUNS)

    loop_pattern_master = [random.randint(0,1) for _ in range(10)]

    loop_pattern_slave = [random.randint(0,1) for _ in range(10)]

    master_pressure_pattern = looping_pause_generator(loop_pattern_master)
    slave_pressure_pattern = looping_pause_generator(loop_pattern_slave)

    await run_packetizer_regression(dut, num_packets=num_runs, sink_pause_gen=slave_pressure_pattern, source_pause_gen=master_pressure_pattern)

@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def functional_basic_crc_check(dut):
    """Check CRC is correct after simple data transfers"""

    num_runs = random.randint(1,MAX_RUNS)

    await run_packetizer_regression(dut, num_packets=num_runs, crc_check=True)

@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def functional_busy_pattern_rand_crc_check(dut):
    """Check CRC is correct with random busyness"""

    num_runs = random.randint(1,MAX_RUNS)

    loop_pattern_master = [random.randint(0,1) for _ in range(10)]

    loop_pattern_slave = [random.randint(0,1) for _ in range(10)]

    master_pressure_pattern = looping_pause_generator(loop_pattern_master)
    slave_pressure_pattern = looping_pause_generator(loop_pattern_slave)

    await run_packetizer_regression(dut, num_packets=num_runs, sink_pause_gen=slave_pressure_pattern, source_pause_gen=master_pressure_pattern, crc_check=True)

@cocotb.test(timeout_time=1000, timeout_unit="us")
async def test_data_transfer_no_backpressure_bubbled(dut):
    """Test that there are no AXI-Stream protocol violations under normal operation"""

    # 1. Start a 250 MHz clock domain (4.0 ns period)
    cocotb.start_soon(Clock(dut.CLK, 4.0, unit="ns").start())
    

    axis_source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "S_AXIS"), dut.CLK, dut.RST_N, reset_active_level=False)
    axis_sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "M_AXIS"), dut.CLK, dut.RST_N,reset_active_level=False)

    await setup_reset(dut)
    await RisingEdge(dut.CLK)

    
    # 7. Wait for the out-of-context master interface to capture the fully processed frame
    failures = []
    num_runs = random.randint(1,MAX_RUNS)

    for packet_id in range(num_runs):
        num_transfers = random.randint(1,64)
        num_bytes = num_transfers * 4
        test_data = random.randbytes(num_bytes)
        dut.S_PAYLOAD_LEN.value = num_bytes
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
