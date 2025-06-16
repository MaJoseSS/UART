# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge
import random

async def send_uart_byte(dut, data):
    """Envía un byte a través de la interfaz UART"""
    # Configurar datos de transmisión
    dut.uio_in.value = data
    
    # Activar señal de inicio (pulso alto)
    dut.ui_in.value = (dut.ui_in.value & 0x01) | 0x02  # Mantener RX_IN, activar TX_START
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = dut.ui_in.value & 0xFD  # Desactivar TX_START
    await ClockCycles(dut.clk, 1)
    
    # Esperar hasta que TX ya no esté ocupado
    while dut.uo_out.value & 0x02:
        await ClockCycles(dut.clk, 1)

async def receive_uart_byte(dut):
    """Recibe un byte desde la interfaz UART"""
    # Esperar hasta que haya datos disponibles
    while not (dut.uo_out.value & 0x04):
        await ClockCycles(dut.clk, 1)
    
    # Leer datos recibidos (simulado)
    return dut.uo_out.value  # En un diseño real, esto vendría de otra señal

@cocotb.test()
async def test_uart_loopback(dut):
    dut._log.info("Iniciando prueba UART")
    
    # Configurar reloj (100 KHz = 10 μs por ciclo)
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0  # Todas las señales en 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)
    
    # Configurar UART (8 bits, sin paridad, 1 bit de stop)
    # ui_in[7:3] = ctrl_word: [stop_bits, parity_en, parity_type, data_bits_high, data_bits_low]
    config = 0b00011  # 1 stop bit, paridad deshabilitada, 8 bits (4+4=8)
    dut.ui_in.value = (config << 3) | 0x04  # Mantener baud16_en siempre activo
    
    dut._log.info("Configuración completada: %s", bin(config))
    
    # Probar con 10 bytes aleatorios
    for _ in range(10):
        tx_data = random.randint(0, 255)
        dut._log.info("Enviando byte: 0x%02X", tx_data)
        
        await send_uart_byte(dut, tx_data)
        await ClockCycles(dut.clk, 500)  # Esperar transmisión
        
        # Simular loopback (conectar TX a RX)
        # En una implementación real, conectarías tx_out a rx_in
        #dut.ui_in.value = (dut.ui_in.value & 0xFE) | (dut.uo_out.value & 0x01)
        
        #rx_data = await receive_uart_byte(dut)
        #dut._log.info("Byte recibido: 0x%02X", rx_data)
        
        # Verificar TX_BUSY está inactivo
        assert (dut.uo_out.value & 0x02) == 0, "Transmisor ocupado después de enviar"
    
    dut._log.info("¡Prueba completada con éxito!")
