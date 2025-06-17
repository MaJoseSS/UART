# Makefile
# Ver documentación oficial de cocotb: https://docs.cocotb.org/en/stable/quickstart.html

# Selección del simulador (por defecto: icarus)
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# Directorio fuente
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = uart.v

# Configuración según tipo de simulación
ifeq ($(GATES),yes)

# 🔧 Gate-level simulation
SIM_BUILD = sim_build/gl
COMPILE_ARGS += -DGL_TEST -DFUNCTIONAL -DSIM

# Verifica si el netlist existe
ifeq ("$(wildcard gate_level_netlist.v)","")
$(error gate_level_netlist.v no encontrado. Asegúrate de generarlo antes de ejecutar con GATES=yes)
endif

# Agrega librerías PDK y el netlist gate-level
VERILOG_SOURCES += \
	$(PDK_ROOT)/ihp-sg13g2/libs.ref/sg13g2_io/verilog/sg13g2_io.v \
	$(PDK_ROOT)/ihp-sg13g2/libs.ref/sg13g2_stdcell/verilog/sg13g2_stdcell.v \
	$(PWD)/gate_level_netlist.v

else

#RTL simulation
SIM_BUILD = sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

endif

# Incluir configuraciones del diseño
COMPILE_ARGS += -I$(SRC_DIR)

# Testbench
VERILOG_SOURCES += $(PWD)/tb.v
TOPLEVEL = tb
MODULE = test

# Incluir reglas de cocotb
include $(shell cocotb-config --makefiles)/Makefile.sim
