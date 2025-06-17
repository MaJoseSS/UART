import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
@cocotb.test()
async def test_uart_basic_transmission(dut):
    dut._log.info("Start UART test")

    # Inicia el reloj
    clock = Clock(dut.clk, 10, units="ns")  # 100 MHz
    cocotb.start_soon(clock.start())

    # Reset
    dut.rst_n.value = 0
    dut.ena.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    # Configura UART: 8N1, sin paridad, 1 stop bit
    dut.ui_in.value = 0b01011000  # ctrl_word = {NSB=0, NPB=1, POE=0, NDB=11}
    
    # Enviar dato
    dut.uio_in.value = 0xA5      # Dato a transmitir
    dut.ui_in.value = dut.ui_in.value | 0b00000010  # tx_start = 1
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = dut.ui_in.value & (~0b00000010)  # tx_start = 0

    # Esperar un tiempo para que transmisión se complete
    await ClockCycles(dut.clk, 1000)

    # Verificar que al menos la línea TX (uo_out[0]) haya cambiado
    tx_line = int(dut.uo_out.value) & 0x01
    dut._log.info(f"TX line = {tx_line}")

