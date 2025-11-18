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
TCL_SCRIPT = synth/AURAsynth.tcl

# Set the shell's pipefail option: causes return values through pipes to match the last non-zero value
# (useful for, i.e. piping to `tee`)
SHELL := $(SHELL) -o pipefail

################################
# ---- Module Testbenches ---- #
################################

# This section adds Make targets for running individual module testbenches
# It requires using the following naming convention:
# 1. the source file: 'verilog/rob.sv'
# 2. should declare a module: 'rob'
# 3. with a testbench file: 'test/rob_test.sv'
# 4. and added to the MODULES variable as: 'rob'
# 5. with extra sources specified for: 'build/rob.simv', 'build/rob.cov', and 'synth/rob.vg'


# This allows you to use the following make targets:

# Simulation
# make <module>.pass   <- greps for "@@@ Passed" or "@@@ Failed" in the output
# make <module>.out    <- run the testbench (via build/<module>.simv)
# make <module>.verdi  <- run in verdi (via <module>.simv)
# make build/<module>.simv  <- compile the testbench executable

# Synthesis
# make <module>.syn.pass   <- greps for "@@@ Passed" or "@@@ Failed" in the output
# make <module>.syn.out    <- run the synthesized module on the testbench
# make <module>.syn.verdi  <- run in verdi (via <module>.syn.simv)
# make synth/<module>.vg        <- synthesize the module
# make build/<module>.syn.simv  <- compile the synthesized module with the testbench

# We have also added targets for checking testbench coverage:

# make <module>.cov        <- print the coverage hierarchy report to the terminal
# make <module>.cov.verdi  <- open the coverage report in verdi
# make build/<module>.cov.simv  <- compiles a coverage executable for the testbench
# make build/<module>.cov.vdb   <- runs the executable and makes a coverage output dir
# make cov_report_<module>      <- run urg to create human readable coverage reports

# ---- Modules to Test ---- #

MODULES = dot_product

# TODO: update this if you add more header files
ALL_HEADERS = $(AURA_HEADERS)

# TODO: add extra source file dependencies below

DOT_PRODUCT_FILES = inc/sys_defs.svh verilog/tree_reduce.sv verilog/reduction_step.sv
build/dot_product.simv: $(DOT_PRODUCT_FILES)
build/dot_product.cov: $(DOT_PRODUCT_FILES)
synth/dot_product.vg: $(DOT_PRODUCT_FILES)

#################################
# ---- Main AURA Definition ---- #
#################################

# We also reuse this section to compile the cpu, but not to run it
# You should still run programs in the same way as project 3

AURA_HEADERS = inc/sys_defs.svh

# tb/cpu_test.sv is implicit
AURA_TESTBENCH = tb/mem.sv 

# verilog/cpu.sv is implicit
AURA_SOURCES = verilog/AURA.sv \
		       verilog/dot_product.sv \
			   verilog/expmul_stage.sv \
			   verilog/expmul.sv \
			   verilog/KSRAM.sv \
			   verilog/max.sv \
			   verilog/memory_controller.sv \
			   verilog/OSRAM.sv \
		       verilog/PE.sv \
			   verilog/QSRAM.sv \
			   verilog/reduction_step.sv \
		       verilog/tree_reduce.sv \
			   verilog/vec_add.sv \
			   verilog/vector_division.sv \
		       verilog/VSRAM.sv \
			  
build/aura.simv: $(AURA_SOURCES) $(AURA_HEADERS) $(AURA_TESTBENCH)
synth/aura.vg: $(AURA_SOURCES) $(AURA_HEADERS)
build/aura.syn.simv: $(AURA_TESTBENCH)
# Don't need coverage for the CPU

# Connect the simv and syn_simv targets for the autograder
simv: build/aura.simv ;
syn_simv: build/aura.syn.simv ;


#####################
# ---- Running ---- #
#####################

# The following Makefile targets heavily use pattern substitution and static pattern rules
# See these links if you want to hack on them and understand how they work:
# - https://www.gnu.org/software/make/manual/html_node/Text-Functions.html
# - https://www.gnu.org/software/make/manual/html_node/Static-Usage.html
# - https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html

# run compiled executables ('make %.out' is linked to 'make output/%.out' further below)
# using this syntax avoids overlapping with the 'make <my_program>.out' targets
$(MODULES:%=build/%.out) $(MODULES:%=build/%.syn.out): build/%.out: build/%.simv
	@$(call PRINT_COLOR, 5, running $<)
	cd build && ./$(<F) | tee $(@F)

# Connect 'make build/mod.out' to 'make mod.out'
$(MODULES:%=./%.out) $(MODULES:%=./%.syn.out): ./%.out: build/%.out
	@$(call PRINT_COLOR, 2, Finished $* testbench output is in: $<)

# Print in green or red the pass/fail status (must $display() "@@@ Passed" or "@@@ Failed")
%.pass: build/%.out
	@$(call PRINT_COLOR, 6, Grepping for pass/fail in $<:)
	@GREP_COLOR="01;31" $(GREP) -i '@@@ ?Failed' $< || \
	GREP_COLOR="01;32" $(GREP) -i '@@@ ?Passed' $<
.PHONY: %.pass

# run the module in verdi
./%.verdi: build/%.simv
	@$(call PRINT_COLOR, 5, running $< with verdi )
	cd build && ./$(<F) $(RUN_VERDI)
.PHONY: %.verdi


###############################
# ---- Compiling Verilog ---- #
###############################

# The normal simulation executable will run your testbench on simulated modules
$(MODULES:%=build/%.simv): build/%.simv: test/%_test.sv verilog/%.sv | build
	@$(call PRINT_COLOR, 5, compiling the simulation executable $@)
	$(VCS) $(filter-out $(ALL_HEADERS),$^) -o $@
	@$(call PRINT_COLOR, 6, finished compiling $@)

# This also generates many other files, see the tcl script's introduction for info on each of them
synth/%.vg: verilog/%.sv $(TCL_SCRIPT) | synth
	@$(call PRINT_COLOR, 5, synthesizing the $* module)
	@$(call PRINT_COLOR, 3, this might take a while...)
	cd synth && \
	MODULE=$* SOURCES="$(filter-out $(TCL_SCRIPT) $(ALL_HEADERS),$^)" \
	dc_shell-t -f $(notdir $(TCL_SCRIPT)) | tee $*_synth.out
	@$(call PRINT_COLOR, 6, finished synthesizing $@)

# A phony target to view the slack in all the *.rep synthesis reports
slack:
	$(GREP) "slack" synth/*.rep
.PHONY: slack

# The synthesis executable runs your testbench on the synthesized versions of your modules
$(MODULES:%=build/%.syn.simv): build/%.syn.simv: test/%_test.sv synth/%.vg | build
	@$(call PRINT_COLOR, 5, compiling the synthesis executable $@)
	$(VCS) +define+SYNTH $(filter-out $(ALL_HEADERS),$^) $(LIB) -o $@
	@$(call PRINT_COLOR, 6, finished compiling $@)


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


