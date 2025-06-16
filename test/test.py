import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
import random

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await Timer(100, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")

async def send_serial(dut, data, baud_period_ns):
    """Envía un byte serialmente por la línea RX"""
    # Bit de inicio (0)
    dut.ui_in.value = dut.ui_in.value & 0xFE  # Poner bit 0 a 0
    await Timer(baud_period_ns, units="ns")
    
    # Bits de datos (LSB first)
    for i in range(8):
        bit = (data >> i) & 0x01
        dut.ui_in.value = (dut.ui_in.value & 0xFE) | bit
        await Timer(baud_period_ns, units="ns")
    
    # Bit de parada (1)
    dut.ui_in.value = dut.ui_in.value | 0x01
    await Timer(baud_period_ns * 2, units="ns")

@cocotb.test()
async def test_uart(dut):
    # Configuración de baudios (115200 baudios)
    BAUD_RATE = 115200
    CLOCK_FREQ = 100_000_000  # 100 MHz
    BAUD16_PERIOD_NS = 1e9 / (BAUD_RATE * 16)
    BIT_PERIOD_NS = 1e9 / BAUD_RATE
    
    # Iniciar reloj (100 MHz)
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset inicial
    await reset_dut(dut)
    
    # Verificar estado inicial
    assert dut.uo_out.value == 0x01, f"Estado inicial incorrecto: 0x{dut.uo_out.value.integer:02x} != 0x01"
    
    # Configurar UART para 8N1 (8 bits, sin paridad, 1 stop bit)
    CTRL_WORD = 0b01011  # [stop=0, parity_disabled=1, data_bits=11(8-bits)]
    dut.ui_in.value = CTRL_WORD << 3  # Colocar en bits [7:3]
    await Timer(100, units="ns")
    
    # ===========================================
    # Prueba de transmisión
    # ===========================================
    test_data = random.randint(0, 255)
    dut.uio_in.value = test_data
    
    # Activar transmisión
    dut.ui_in.value = (CTRL_WORD << 3) | 0x02  # Activar tx_start (bit 1)
    await RisingEdge(dut.clk)
    dut.ui_in.value = CTRL_WORD << 3  # Desactivar tx_start
    
    # Esperar hasta que TX esté ocupado
    while dut.uo_out[1].value != 1:
        await RisingEdge(dut.clk)
    
    # Esperar hasta que TX termine
    while dut.uo_out[1].value == 1:
        await RisingEdge(dut.clk)
    
    # Verificar que TX volvió a estado inactivo
    assert dut.uo_out[0].value == 1, "TX no volvió a estado inactivo"
    
    # ===========================================
    # Prueba de recepción
    # ===========================================
    test_data = 0xAA
    await send_serial(dut, test_data, BAUD16_PERIOD_NS * 16)
    
    # Esperar dato recibido (pulso en rx_ready)
    timeout = 0
    while dut.uo_out[2].value != 1:
        await RisingEdge(dut.clk)
        timeout += 1
        if timeout > 5000:
            assert False, "Timeout esperando rx_ready"
    
    # Verificar dato recibido
    rx_data = dut.uart_inst.rx_data.value
    assert rx_data == test_data, f"Dato recibido incorrecto: 0x{rx_data.integer:02x} != 0x{test_data:02x}"
    
    # Verificar que no hay errores
    assert dut.uo_out[3].value == 0, f"Error detectado: frame={dut.uart_inst.frame_error.value}, parity={dut.uart_inst.parity_error.value}"
    
    # ===========================================
    # Prueba de detección de errores
    # ===========================================
    # Habilitar paridad impar
    CTRL_WORD_ERR = 0b00111  # [stop=0, parity_enabled=0, parity_odd=1, data_bits=11]
    dut.ui_in.value = CTRL_WORD_ERR << 3
    
    # Enviar byte con paridad incorrecta
    await send_serial(dut, 0x55, BAUD16_PERIOD_NS * 16)  # 0x55 tiene paridad par
    
    # Esperar dato recibido con error
    timeout = 0
    while dut.uo_out[2].value != 1:
        await RisingEdge(dut.clk)
        timeout += 1
        if timeout > 5000:
            assert False, "Timeout esperando rx_ready (prueba error)"
    
    # Verificar que se detectó error
    assert dut.uo_out[3].value == 1, "No se detectó error de paridad"
    
    dut._log.info("¡Todas las pruebas pasaron!")
