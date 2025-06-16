`timescale 1ns / 1ps

module tb_tt_um_uart();

reg clk;
reg rst_n;
reg [7:0] ui_in;
wire [7:0] uo_out;
reg [7:0] uio_in;
wire [7:0] uio_out;
wire [7:0] uio_oe;
reg ena;

// Instancia del módulo UART
tt_um_uart dut (
    .ui_in(ui_in),
    .uo_out(uo_out),
    .uio_in(uio_in),
    .uio_out(uio_out),
    .uio_oe(uio_oe),
    .ena(ena),
    .clk(clk),
    .rst_n(rst_n)
);

// Generación de reloj (100 MHz)
initial begin
    clk = 0;
    forever #5 clk = ~clk; // 10ns period
end

// Generación de habilitación de baudios (115200 baudios)
reg baud16_en;
real BAUD_RATE = 115200;
real BAUD16_PERIOD = (1/(BAUD_RATE*16))*1e9;
initial begin
    baud16_en = 0;
    forever #(BAUD16_PERIOD/2) baud16_en = ~baud16_en;
end

// Tarea para enviar un byte serial
task send_byte;
    input [7:0] data;
    integer i;
    begin
        // Bit de inicio
        ui_in[0] = 1'b0;
        #BAUD16_PERIOD;
        
        // Bits de datos (LSB first)
        for (i = 0; i < 8; i = i + 1) begin
            ui_in[0] = data[i];
            #BAUD16_PERIOD;
        end
        
        // Bit de parada
        ui_in[0] = 1'b1;
        #(BAUD16_PERIOD*2);
    end
endtask

// Procedimiento de prueba
initial begin
    // Inicialización
    rst_n = 0;
    ena = 1;
    ui_in = 8'h00;
    uio_in = 8'h00;
    #100;
    
    // Liberar reset
    rst_n = 1;
    #100;
    
    // Configurar formato 8N1 (8 bits, sin paridad, 1 stop bit)
    ui_in[7:3] = 5'b01011; // [stop=0, no parity=1, data=11(8bits)]
    ui_in[2] = baud16_en;  // Habilitación de baudios
    
    // Prueba de transmisión
    $display("Iniciando prueba de transmisión...");
    uio_in = 8'hA5;       // Dato a transmitir
    ui_in[1] = 1'b1;      // Activar inicio de transmisión
    #20;
    ui_in[1] = 1'b0;      // Desactivar señal de inicio
    
    // Monitorear señal serial
    $display("Señal TX: %b (esperado: 0)", uo_out[0]);
    #(BAUD16_PERIOD*16);
    
    // Prueba de recepción
    $display("\nIniciando prueba de recepción...");
    send_byte(8'h5A);     // Enviar byte 0x5A
    
    // Verificar recepción
    if (dut.uart_inst.rx_data == 8'h5A)
        $display("Recepción exitosa: 0x%h", dut.uart_inst.rx_data);
    else
        $display("ERROR: Se recibió 0x%h, esperado 0x5A", dut.uart_inst.rx_data);
    
    // Prueba de error de paridad
    $display("\nIniciando prueba de error de paridad...");
    ui_in[7:3] = 5'b00111; // Habilitar paridad impar (5 bits: stop=0, parity=0, type=1, data=11)
    send_byte(8'hAA);       // Enviar byte con paridad incorrecta
    
    // Verificar detección de error
    #(BAUD16_PERIOD*16);
    if (uo_out[3])
        $display("Error detectado correctamente");
    else
        $display("ERROR: No se detectó error de paridad");
    
    // Finalizar simulación
    #100;
    $finish;
end

// Monitoreo de señales
initial begin
    $monitor("Tiempo: %tns | TX: %b | Busy: %b | RX Ready: %b | Error: %b",
             $time, uo_out[0], uo_out[1], uo_out[2], uo_out[3]);
end

endmodule
