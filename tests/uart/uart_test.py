import logging
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.result import TestFailure
from cocotbext.uart import UartSource, UartSink
from cocotbext.axi import AxiLiteBus, AxiLiteMaster

async def _reset(dut, cycles: int = 2):
    dut.rst.value = 1
    await Timer(50, units="ns")
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)

def _as_bytes(x):
    return x if isinstance(x, (bytes, bytearray)) else x.encode("utf-8")

# Quick and dirty test requiring manual inspection of the output
# Not an extensive test, just meant for debugging
@cocotb.test()
async def uart_test(dut):
    """
    Two aligned writes within the same 128B line; read back in aligned beats.
    """
    log = logging.getLogger("cocotb.tb")
    log.setLevel(logging.DEBUG)
    uart_source = UartSource(dut.uart.rx, baud=9600, bits=8)
    uart_sink = UartSink(dut.uart.tx, baud=9600, bits=8)
    cocotb.start_soon(Clock(dut.clk, 83, units="ns").start())
    await _reset(dut)

    axi = AxiLiteMaster(AxiLiteBus.from_entity(dut.combus), dut.clk, dut.rst)
    
    output = await axi.read_dword(0xFFFFFFFFFFFFF000)
    print(output)

    output2 = await axi.read_dword(0xFFFFFFFFFFFFF000)
    print(output2)

    await uart_source.write(b'Hello World!')
    await uart_source.wait()

    output3 = await axi.read_dword(0xFFFFFFFFFFFFF000)
    print(output3)
    # Read out those twelve bytes
    output4 = await axi.read(0xFFFFFFFFFFFFF008, 8)
    print(output4.data)
    output4t = await axi.read(0xFFFFFFFFFFFFF008, 8)
    print(output4t.data)
    output5 = await axi.read_dword(0xFFFFFFFFFFFFF000)
    print(output5)
    await uart_source.write(b'AB')
    await uart_source.wait()
    output6 = await axi.read_dword(0xFFFFFFFFFFFFF000)
    print(output6)
    output7 = await axi.read(0xFFFFFFFFFFFFF008, 8)
    print(output7.data)

    await axi.write(0xFFFFFFFFFFFFF018, b'Hello from pytho')
    await axi.write(0xFFFFFFFFFFFFF018, b'n!')
    await uart_source.write(b'SOMETHING REALLY LONG TO KILL TIME')
    await uart_source.wait()
    output9 = await uart_sink.read()
    print(output9)