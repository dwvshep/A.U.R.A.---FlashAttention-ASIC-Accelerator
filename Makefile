# this is a global clock period variable used in the tcl script and referenced in testbenches
export CLOCK_PERIOD = 7.85

# the Verilog Compiler command and arguments
VCS =  vcs -sverilog -xprop=tmerge +vc -Mupdate -Mdir=build/csrc -line -full64 -kdb -lca -nc \
      -debug_access+all+reverse $(VCS_BAD_WARNINGS) +define+CLOCK_PERIOD=$(CLOCK_PERIOD) +incdir+verilog/
# a SYNTH define is added when compiling for synthesis that can be used in testbenches

RUN_VERDI = -gui=verdi -verdi_opts "-ultra"

# remove certain warnings that generate MB of text but can be safely ignored
VCS_BAD_WARNINGS = +warn=noTFIPC +warn=noDEBUG_DEP +warn=noENUMASSIGN +warn=noLCA_FEATURES_ENABLED

# a reference library of standard structural cells that we link against when synthesizing
LIB = /afs/umich.edu/class/eecs470/lib/verilog/lec25dscc25.v

# the EECS 470 synthesis script
TCL_SCRIPT = synth/470synth.tcl

# Set the shell's pipefail option: causes return values through pipes to match the last non-zero value
# (useful for, i.e. piping to `tee`)
SHELL := $(SHELL) -o pipefail





MODULES = dot_product






CXX = g++
CXXFLAGS = -O2 -Wall

TARGET = gen_qkv_mem
SRC = gen_qkv_mem.cpp

MEM_FILES = Q.mem K.mem V.mem

all: run

$(TARGET): tb/$(SRC)
	$(CXX) $(CXXFLAGS) -o tb/$(TARGET) tb/$(SRC)

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f tb/$(TARGET) output/$(MEM_FILES)


