

module uart (
    input clk,             // Reloj del sistema
    input rst,             // Reset activo en alto
    // Configuración
    input [4:0] ctrl_word, // {NSB, NPB, POE, NDB2, NDB1}
    // Interfaz de transmisión
    input [7:0] tx_data,   // Datos a transmitir
    input tx_start,        // Iniciar transmisión (activo alto)
    output tx_busy,        // Transmisor ocupado
    output tx_out,         // Salida serie
    // Interfaz de recepción
    input rx_in,           // Entrada serie
    output [7:0] rx_data,  // Datos recibidos
    output rx_ready,       // Dato recibido disponible (pulso)
    output rx_error,       // Error (paridad/trama)
    // Control de baud rate
    input baud16_en        // Enable 16x baud rate (pulso)
);

// ================================================
// Parámetros y registros internos
// ================================================
// Estados del transmisor
localparam TX_IDLE     = 0;
localparam TX_START    = 1;
localparam TX_DATA     = 2;
localparam TX_PARITY   = 3;
localparam TX_STOP     = 4;

// Estados del receptor
localparam RX_IDLE     = 0;
localparam START_CHECK = 1;
localparam RX_DATA     = 2;
localparam RX_PARITY   = 3;
localparam RX_STOP     = 4;

// Registros del transmisor
reg [2:0] tx_state;
reg [4:0] tx_cycle_count;
reg [2:0] tx_bit_count;
reg [7:0] tx_shift_reg;
reg tx_parity_bit;
reg [4:0] tx_stop_duration;
reg tx_out_reg;

// Registros del receptor
reg [2:0] rx_state;
reg [4:0] rx_cycle_count;
reg [2:0] rx_bit_count;
reg [7:0] rx_shift_reg;
reg rx_in_prev;
reg frame_error;
reg parity_error;
reg [7:0] rx_data_reg;
reg rx_ready_reg;

// ================================================
// Lógica del transmisor
// ================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        tx_state <= TX_IDLE;
        tx_out_reg <= 1'b1;
        tx_cycle_count <= 0;
        tx_bit_count <= 0;
    end else begin
        case (tx_state)
            TX_IDLE: begin
                tx_out_reg <= 1'b1;  // Línea en reposo
                if (tx_start) begin
                    // Calcular parámetros
                    tx_stop_duration <= (ctrl_word[4]) ? 
                        ((ctrl_word[1:0] == 2'b11) ? 24 : 32) : 16;
                    
                    // Calcular paridad
                    if (~ctrl_word[3]) begin // NPB=0: paridad habilitada
                        if (ctrl_word[2]) // POE=1: paridad par
                            tx_parity_bit <= ^tx_data;
                        else // POE=0: paridad impar
                            tx_parity_bit <= ~^tx_data;
                    end
                    
                    tx_shift_reg <= tx_data;
                    tx_state <= TX_START;
                    tx_cycle_count <= 0;
                end
            end
            
            TX_START: begin
                tx_out_reg <= 1'b0;  // Bit de inicio
                if (baud16_en) begin
                    if (tx_cycle_count < 15)
                        tx_cycle_count <= tx_cycle_count + 1;
                    else begin
                        tx_cycle_count <= 0;
                        tx_state <= TX_DATA;
                        tx_bit_count <= 0;
                    end
                end
            end
            
            TX_DATA: begin
                tx_out_reg <= tx_shift_reg[0];  // Envía LSB primero
                if (baud16_en) begin
                    if (tx_cycle_count < 15) begin
                        tx_cycle_count <= tx_cycle_count + 1;
                    end else begin
                        tx_cycle_count <= 0;
                        tx_shift_reg <= tx_shift_reg >> 1; // Desplaza
                        tx_bit_count <= tx_bit_count + 1;
                        
                        // Verificar fin de datos
                        if (tx_bit_count == (ctrl_word[1:0] + 4)) begin
                            if (~ctrl_word[3]) // Si hay paridad
                                tx_state <= TX_PARITY;
                            else
                                tx_state <= TX_STOP;
                        end
                    end
                end
            end
            
            TX_PARITY: begin
                tx_out_reg <= tx_parity_bit;
                if (baud16_en) begin
                    if (tx_cycle_count < 15)
                        tx_cycle_count <= tx_cycle_count + 1;
                    else begin
                        tx_cycle_count <= 0;
                        tx_state <= TX_STOP;
                    end
                end
            end
            
            TX_STOP: begin
                tx_out_reg <= 1'b1;  // Bit de parada
                if (baud16_en) begin
                    if (tx_cycle_count < tx_stop_duration - 1)
                        tx_cycle_count <= tx_cycle_count + 1;
                    else begin
                        tx_cycle_count <= 0;
                        tx_state <= TX_IDLE;
                    end
                end
            end
        endcase
    end
end

assign tx_busy = (tx_state != TX_IDLE);
assign tx_out = tx_out_reg;

// ================================================
// Lógica del receptor
// ================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        rx_state <= RX_IDLE;
        rx_ready_reg <= 0;
        rx_cycle_count <= 0;
        rx_bit_count <= 0;
        rx_in_prev <= 1'b1;
        frame_error <= 0;
        parity_error <= 0;
    end else begin
        rx_ready_reg <= 0;  // Resetear pulso de dato listo
        rx_in_prev <= rx_in; // Almacenar valor previo
        
        case (rx_state)
            RX_IDLE: begin
                if (rx_in_prev && !rx_in) begin  // Detección flanco de bajada
                    rx_state <= START_CHECK;
                    rx_cycle_count <= 7;  // Muestrear en mitad del bit de inicio
                end
            end
            
            START_CHECK: begin
                if (baud16_en) begin
                    if (rx_cycle_count > 0) begin
                        rx_cycle_count <= rx_cycle_count - 1;
                    end else begin
                        if (!rx_in) begin  // Bit de inicio válido
                            rx_state <= RX_DATA;
                            rx_cycle_count <= 0;
                            rx_bit_count <= 0;
                        end else begin
                            rx_state <= RX_IDLE;
                        end
                    end
                end
            end
            
            RX_DATA: begin
                if (baud16_en) begin
                    rx_cycle_count <= rx_cycle_count + 1;
                    
                    // Muestrear en el centro del bit (ciclo 8)
                    if (rx_cycle_count == 8) begin
                        rx_shift_reg <= {rx_in, rx_shift_reg[7:1]}; // Shift right
                    end
                    
                    if (rx_cycle_count == 15) begin
                        rx_cycle_count <= 0;
                        rx_bit_count <= rx_bit_count + 1;
                        
                        // Verificar fin de datos
                        if (rx_bit_count == (ctrl_word[1:0] + 4)) begin
                            if (~ctrl_word[3]) // Si hay paridad
                                rx_state <= RX_PARITY;
                            else
                                rx_state <= RX_STOP;
                        end
                    end
                end
            end
            
            RX_PARITY: begin
                if (baud16_en) begin
                    rx_cycle_count <= rx_cycle_count + 1;
                    
                    if (rx_cycle_count == 8) begin
                        // Verificar paridad
                        if (ctrl_word[2]) begin // POE=1: Paridad par
                            if (^rx_shift_reg != rx_in) 
                                parity_error <= 1;
                        end else begin // POE=0: Paridad impar
                            if (~^rx_shift_reg != rx_in)
                                parity_error <= 1;
                        end
                    end
                    
                    if (rx_cycle_count == 15) begin
                        rx_cycle_count <= 0;
                        rx_state <= RX_STOP;
                    end
                end
            end
            
            RX_STOP: begin
                if (baud16_en) begin
                    rx_cycle_count <= rx_cycle_count + 1;
                    
                    if (rx_cycle_count == 8) begin
                        if (!rx_in)  // Bit de parada debe ser 1
                            frame_error <= 1;
                    end
                    
                    if (rx_cycle_count == 15) begin
                        rx_data_reg <= rx_shift_reg;
                        rx_ready_reg <= 1'b1;
                        rx_state <= RX_IDLE;
                        // Reset errores para siguiente byte
                        frame_error <= 0;
                        parity_error <= 0;
                    end
                end
            end
        endcase
    end
end

assign rx_data = rx_data_reg;
assign rx_ready = rx_ready_reg;
assign rx_error = frame_error | parity_error;

endmodule
