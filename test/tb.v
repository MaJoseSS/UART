`default_nettype none
`timescale 1ns / 1ps

module tb ();

  // Dump the signals to a VCD file
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    #1;
  end

  // Wire up the inputs and outputs
  reg clk = 0;
  reg rst_n = 0;
  reg ena = 1;
  reg [7:0] ui_in = 0;
  reg [7:0] uio_in = 0;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

  // Instantiate the UART module
  tt_um_uart user_project (
      .ui_in  (ui_in),
      .uo_out (uo_out),
      .uio_in (uio_in),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (ena),
      .clk    (clk),
      .rst_n  (rst_n)
  );

  // Clock generation (100 MHz)
  always #5 clk = ~clk;

  // Baud rate generator (115200 baud)
  reg baud16_en = 0;
  real BAUD_RATE = 115200;
  real CLOCK_FREQ = 100_000_000; // 100 MHz
  real BAUD16_PERIOD = (1/(BAUD_RATE*16))*1e9;
  integer baud_counter = 0;
  integer baud_interval = CLOCK_FREQ/(BAUD_RATE*16);
  
  always @(posedge clk) begin
    if (baud_counter >= baud_interval - 1) begin
      baud_counter <= 0;
      baud16_en <= 1;
    end else begin
      baud_counter <= baud_counter + 1;
      baud16_en <= 0;
    end
  end

  // Test procedure
  initial begin
    // Initial reset
    rst_n = 0;
    ui_in = 0;
    uio_in = 0;
    #100;
    
    // Release reset
    rst_n = 1;
    #100;
    
    // Configure UART for 8N1: 
    // [stop=0 (1-bit), parity_disabled=1, parity_type=0, data_bits=11 (8-bits)]
    ui_in[7:3] = 5'b01011;
    
    // Connect baud16_en
    ui_in[2] = baud16_en;
    
    // Test 1: Basic transmission
    $display("Test 1: Basic transmission");
    uio_in = 8'hA5;       // Data to transmit
    ui_in[1] = 1'b1;      // Activate tx_start
    #10;
    ui_in[1] = 1'b0;      // Deactivate tx_start
    
    // Wait for transmission to complete
    while (uo_out[1] == 1'b1) #10;
    $display("Transmission complete");
    
    // Test 2: Reception
    $display("\nTest 2: Reception");
    fork
      begin
        // Send byte 0x5A serially
        // Start bit
        ui_in[0] = 1'b0;
        #(BAUD16_PERIOD*16);
        
        // Data bits (LSB first)
        ui_in[0] = 1'b0; // bit0
        #(BAUD16_PERIOD*16);
        ui_in[0] = 1'b1; // bit1
        #(BAUD16_PERIOD*16);
        ui_in[0] = 1'b0; // bit2
        #(BAUD16_PERIOD*16);
        ui_in[0] = 1'b1; // bit3
        #(BAUD16_PERIOD*16);
        ui_in[0] = 1'b1; // bit4
        #(BAUD16_PERIOD*16);
        ui_in[0] = 1'b0; // bit5
        #(BAUD16_PERIOD*16);
        ui_in[0] = 1'b1; // bit6
        #(BAUD16_PERIOD*16);
        ui_in[0] = 1'b0; // bit7
        #(BAUD16_PERIOD*16);
        
        // Stop bit
        ui_in[0] = 1'b1;
        #(BAUD16_PERIOD*32);
      end
    join_none
    
    // Wait for reception to complete
    while (uo_out[2] == 1'b0) #10;
    if (user_project.uart_inst.rx_data == 8'h5A) 
      $display("Reception successful: 0x%h", user_project.uart_inst.rx_data);
    else
      $display("ERROR: Received 0x%h, expected 0x5A", user_project.uart_inst.rx_data);
    
    // Test 3: Parity error detection
    $display("\nTest 3: Parity error detection");
    // Configure for parity checking: 
    // [stop=0, parity_disabled=0 (enabled), parity_type=1 (even), data_bits=11 (8-bits)]
    ui_in[7:3] = 5'b00111;
    
    fork
      begin
        // Send byte with incorrect parity
        // Start bit
        ui_in[0] = 1'b0;
        #(BAUD16_PERIOD*16);
        
        // Data bits (0xAA = 10101010 - even parity should be 1, but we send 0)
        for (integer i = 0; i < 8; i = i + 1) begin
          ui_in[0] = 1'b0; // All bits 0 (parity should be 1 for even)
          #(BAUD16_PERIOD*16);
        end
        
        // Incorrect parity bit (0 instead of 1)
        ui_in[0] = 1'b0;
        #(BAUD16_PERIOD*16);
        
        // Stop bit
        ui_in[0] = 1'b1;
        #(BAUD16_PERIOD*32);
      end
    join_none
    
    // Wait for reception to complete
    while (uo_out[2] == 1'b0) #10;
    if (uo_out[3] == 1'b1) 
      $display("Parity error detected successfully");
    else
      $display("ERROR: Parity error not detected");
    
    // Test 4: Frame error detection
    $display("\nTest 4: Frame error detection");
    // Configure for no parity: 
    ui_in[7:3] = 5'b01011;
    
    fork
      begin
        // Send byte with short stop bit
        // Start bit
        ui_in[0] = 1'b0;
        #(BAUD16_PERIOD*16);
        
        // Data bits (0x55)
        for (integer i = 0; i < 8; i = i + 1) begin
          ui_in[0] = ~(i % 2); // 01010101
          #(BAUD16_PERIOD*16);
        end
        
        // Short stop bit (only 8 baud cycles instead of 16)
        ui_in[0] = 1'b1;
        #(BAUD16_PERIOD*8);
        
        // Next start bit (violates stop bit timing)
        ui_in[0] = 1'b0;
        #(BAUD16_PERIOD*16);
      end
    join_none
    
    // Wait for reception to complete
    while (uo_out[2] == 1'b0) #10;
    if (uo_out[3] == 1'b1) 
      $display("Frame error detected successfully");
    else
      $display("ERROR: Frame error not detected");
    
    // Test 5: Busy signal during transmission
    $display("\nTest 5: Busy signal check");
    uio_in = 8'hFF;
    ui_in[1] = 1'b1;
    #10;
    ui_in[1] = 1'b0;
    
    if (uo_out[1] === 1'b1)
      $display("Busy signal active during transmission");
    else
      $display("ERROR: Busy signal not active");
    
    // Wait for transmission to complete
    while (uo_out[1] == 1'b1) #10;
    $display("Busy signal deactivated after transmission");
    
    $display("\nAll tests completed");
    #100;
    $finish;
  end

  // Monitor
  always @(posedge clk) begin
    $display("T=%0t: TX=%b, Busy=%b, RX_ready=%b, Error=%b, State_TX=%0d, State_RX=%0d",
      $time, uo_out[0], uo_out[1], uo_out[2], uo_out[3],
      user_project.uart_inst.tx_state,
      user_project.uart_inst.rx_state);
  end

endmodule
