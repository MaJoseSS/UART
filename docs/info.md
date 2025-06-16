<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

Este módulo UART implementa un sistema de comunicación serie full-duplex configurable, con un transmisor que convierte datos paralelos en serie (5-8 bits con paridad opcional par/impar y 1/1.5/2 bits de parada) usando una máquina de estados finitos (FSM) de 5 estados (INACTIVO→INICIO→DATOS→PARIDAD→PARADA), y un receptor que utiliza sobremuestreo 16× para una temporización precisa de bits, detectando bits de inicio en flancos descendentes, muestreando datos a mitad de bit (en el conteo 8), y verificando errores de paridad/trama antes de entregar los datos con un pulso de "listo". Ambos bloques operan en un único dominio de reloj, controlados por una palabra de configuración de 5 bits (ctrl_word) que define longitud de datos, modo de paridad y bits de parada, mientras la temporización de baudios se gestiona mediante una señal externa baud16_en a 16× la velocidad objetivo.

## How to test

Para verificar el módulo: 
1) Inicialice con reset activo-bajo (rst_n=0). 
2) Configure el formato de trama mediante ui_in[7:3] (bits de datos/paridad/parada). 
3) Genere una señal baud16_en a 16× el baudio deseado.
4) Para transmisión: cargue datos en uio_in[7:0] y active ui_in[1] (tx_start), monitoreando uo_out[0] (salida serie) y uo_out[1] (busy). 
5) Para recepción: inyecte una señal serie en ui_in[0], validando uo_out[2] (dato listo), uo_out[3] (error) y el dato recibido. 
6) Inyecte errores (paridad o trama) para verificar detección.

## External hardware

List external hardware used in your project (e.g. PMOD, LED display, etc), if any
