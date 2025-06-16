import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import random

@cocotb.test()
async def test_project(dut):
    # Iniciar reloj (100 MHz)
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset inicial
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await Timer(100, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")
    
    # Verificar estado inicial (tx_out = 1, otros = 0)
    assert dut.uo_out.value == 0x01, f"Estado inicial incorrecto: {dut.uo_out.value} != 0x01"
    
    # Configurar UART para 8N1 (8 bits, sin paridad, 1 stop bit)
    ctrl_word = 0b01011  # [stop=0, parity_disabled=1, data_bits=11(8-bits)]
    dut.ui_in.value = ctrl_word << 3  # Colocar en bits [7:3]
    
    # Habilitar generación de baudios (simulado)
    await Timer(100, units="ns")
    
    # Prueba de transmisión
    test_data = random.randint(0, 255)
    dut.uio_in.value = test_data
    dut.ui_in.value = (ctrl_word << 3) | 0x02  # Activar tx_start (bit 1)
    await RisingEdge(dut.clk)
    
    # Esperar hasta que TX esté ocupado
    while dut.uo_out[1].value != 1:
        await RisingEdge(dut.clk)
    
    # Desactivar tx_start
    dut.ui_in.value = ctrl_word << 3
    
    # Esperar hasta que TX termine
    while dut.uo_out[1].value == 1:
        await RisingEdge(dut.clk)
    
    # Verificar que TX volvió a estado inactivo
    assert dut.uo_out[0].value == 1, "TX no volvió a estado inactivo"
    
    # Prueba de recepción
    test_data = 0xAA
    await cocotb.start(send_serial(dut, test_data))
    
    # Esperar dato recibido
    while dut.uo_out[2].value != 1:
        await RisingEdge(dut.clk)
    
    # Verificar dato recibido
    assert dut.uart_inst.rx_data.value == test_data, f"Dato recibido incorrecto: {dut.uart_inst.rx_data.value} != 0x{test_data:02x}"
    
    dut._log.info("¡Todas las pruebas pasaron!")

async def send_serial(dut, data):
    """Envía un byte serialmente por la línea RX"""
    # Bit de inicio (0)
    dut.ui_in.value = dut.ui_in.value & 0xFE  # Poner bit 0 a 0
    await Timer(160 * 10, units="ns")  # Esperar 1 bit
    
    # Bits de datos (LSB first)
    for i in range(8):
        bit = (data >> i) & 0x01
        dut.ui_in.value = (dut.ui_in.value & 0xFE) | bit
        await Timer(160 * 10, units="ns")
    
    # Bit de parada (1)
    dut.ui_in.value = dut.ui_in.value | 0x01
    await Timer(320 * 10, units="ns")
