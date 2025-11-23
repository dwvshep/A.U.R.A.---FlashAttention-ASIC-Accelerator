# this is a global clock period variable used in the tcl script and referenced in testbenches
export CLOCK_PERIOD = 10

# the Verilog Compiler command and arguments
VCS =  vcs -sverilog -xprop=tmerge +vc -Mupdate -Mdir=build/csrc -line -full64 -kdb -lca -nc \
      -debug_access+all+reverse $(VCS_BAD_WARNINGS) +define+CLOCK_PERIOD=$(CLOCK_PERIOD) +incdir+verilog/ +incdir+include/
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

MODULES = AURA dot_product expmul expmul_stage int_division KSRAM max memory_controller OSRAM PE q_align_frac q_align_int q_convert q_saturate q_sign_extend QSRAM reduction_step tree_reduce vec_add vector_division

# TODO: update this if you add more header files
ALL_HEADERS = $(AURA_HEADERS)

# TODO: add extra source file dependencies below

DOT_PRODUCT_FILES = verilog/tree_reduce.sv verilog/reduction_step.sv verilog/q_sign_extend.sv verilog/q_saturate.sv verilog/q_align_frac.sv verilog/q_align_int.sv verilog/q_convert.sv
build/dot_product.simv: $(DOT_PRODUCT_FILES)
build/dot_product.cov: $(DOT_PRODUCT_FILES)
synth/dot_product.vg: $(DOT_PRODUCT_FILES)

Q_CONVERT_FILES = verilog/q_sign_extend.sv verilog/q_saturate.sv verilog/q_align_frac.sv verilog/q_align_int.sv
build/q_convert.simv: $(Q_CONVERT_FILES)
build/q_convert.cov: $(Q_CONVERT_FILES)
synth/q_convert.vg: $(Q_CONVERT_FILES)

DIVISION_FILES = verilog/int_division.sv verilog/q_convert.sv verilog/q_sign_extend.sv verilog/q_saturate.sv verilog/q_align_frac.sv verilog/q_align_int.sv
build/int_division.simv: $(DIVISION_FILES)
build/int_division.cov: $(DIVISION_FILES)
synth/int_division.vg: $(DIVISION_FILES)

EXPMUL_FILES = verilog/expmul.sv verilog/expmul_stage.sv verilog/q_convert.sv verilog/q_sign_extend.sv verilog/q_saturate.sv verilog/q_align_frac.sv verilog/q_align_int.sv
build/expmul.simv: $(EXPMUL_FILES)
build/expmul.cov: $(EXPMUL_FILES)
synth/expmul.vg: $(EXPMUL_FILES)

#################################
# ---- Main AURA Definition ---- #
#################################

# We also reuse this section to compile the cpu, but not to run it
# You should still run programs in the same way as project 3

AURA_HEADERS = include/sys_defs.svh

# tb/cpu_test.sv is implicit
AURA_TESTBENCH = test/mem.sv 

# verilog/cpu.sv is implicit
AURA_SOURCES = verilog/AURA.sv \
		       verilog/dot_product.sv \
			   verilog/expmul_stage.sv \
			   verilog/expmul.sv \
			   verilog/int_division.sv \
			   verilog/KSRAM.sv \
			   verilog/max.sv \
			   verilog/memory_controller.sv \
			   verilog/OSRAM.sv \
		       verilog/PE.sv \
			   verilog/q_sign_extend.sv \
			   verilog/q_saturate.sv \
			   verilog/q_align_frac.sv \
			   verilog/q_align_int.sv \
			   verilog/q_convert.sv \
			   verilog/QSRAM.sv \
			   verilog/reduction_step.sv \
		       verilog/tree_reduce.sv \
			   verilog/vec_add.sv \
			   verilog/vector_division.sv \
		       verilog/VSRAM.sv \
			  
build/AURA.simv: $(AURA_HEADERS) $(AURA_SOURCES) $(AURA_TESTBENCH)
synth/AURA.vg: $(AURA_HEADERS) $(AURA_SOURCES)
build/AURA.syn.simv: $(AURA_TESTBENCH)
# Don't need coverage for the CPU

# Connect the simv and syn_simv targets for the autograder
simv: build/AURA.simv ;
syn_simv: build/AURA.syn.simv ;


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


##############################
# ---- Coverage targets ---- #
##############################

# This section adds targets to run module testbenches with coverage output

# Additional VCS argument for both building and running with coverage output
VCS_COVG = -cm line+tgl+cond+branch

$(MODULES:%=build/%.cov.simv): build/%.cov.simv: test/%_test.sv verilog/%.sv | build
	@$(call PRINT_COLOR, 5, compiling the coverage executable $@)
	@$(call PRINT_COLOR, 3, NOTE: if this is slow to startup: run '"module load vcs verdi synopsys-synth"')
	$(VCS) $(VCS_COVG) $(filter-out $(ALL_HEADERS),$^) -o $@
	@$(call PRINT_COLOR, 6, finished compiling $@)

# Run the testbench to produce a *.vdb directory with coverage info
$(MODULES:%=build/%.cov.simv.out): %.cov.simv.out: %.cov.simv | build
	@$(call PRINT_COLOR, 5, running $<)
	cd build && ./$(<F) $(VCS_COVG) | tee $(@F)
	@$(call PRINT_COLOR, 2, created coverage dir $<.vdb and saved output to $@)

# A layer of indirection for the coverage output dir
build/%.cov.simv.vdb: build/%.cov.simv.out ;

# Use urg to generate human-readable reports in text mode (alternative is html)
$(MODULES:%=cov_report_%): cov_report_%: build/%.cov.simv.vdb
	@$(call PRINT_COLOR, 5, outputting coverage report in $@)
	module load vcs && cd build && urg -format text -dir $*.cov.simv.vdb -report ../$@
	@$(call PRINT_COLOR, 2, coverage report is in $@)

# view the coverage hierarchy report
$(MODULES:=.cov): %.cov: cov_report_%
	@$(call PRINT_COLOR, 2, printing coverage hierarchy - open '$<' for more)
	cat $</hierarchy.txt

# open the coverage info in verdi
$(MODULES:=.cov.verdi): %.cov.verdi: build/%.cov.simv
	@$(call PRINT_COLOR, 5, running verdi for $* coverage)
	cd build && ./$(<F) $(RUN_VERDI) -cov -covdir $(<F).vdb
	./$< $(RUN_VERDI) -cov -covdir $<.vdb

.PHONY: %.cov %.cov.verdi


####################################
# ---- Executable Compilation ---- #
####################################

###############################
# ---- Program Execution ---- #
###############################

# PROGRAMS = $(ASSEMBLY:%.s=%) $(C_CODE:%.c=%)

# run one of the executables (simv/syn_simv) using the chosen test mem files
# e.g. 'make random_test.out' does the following from a clean directory:
#   1. compiles simv
#   2. Grabs mem/random_test/ random_test.Qmem random_test.Kmem and random_test.Vmem
#   3. runs ./simv +QMEMORY=random_test.Qmem +KMEMORY=random_test.Kmem +VMEMORY=random_test.Vmem +OUTPUT=output/random_test > output/random_test.out
#   4. which creates the random_test.out and random_test.log files in output/
# the same can be done for synthesis by doing 'make random_test.syn.out'
# which will also create random_test.syn.out and random_test.syn.log files in output/

# run a program and produce output files
output/%.out: mem/%/Q.mem mem/%/K.mem mem/%/V.mem build/AURA.simv | output
	@$(call PRINT_COLOR, 5, running simv on $*)
	./build/AURA.simv \
		+QMEMORY=$(word 1,$^) \
		+KMEMORY=$(word 2,$^) \
		+VMEMORY=$(word 3,$^) \
		+OUTPUT=output/$* \
		> output/$*.log
	@$(call PRINT_COLOR, 6, finished running simv on $*)
	@$(call PRINT_COLOR, 2, output is in output/$*.{out log})

# NOTE: this uses a 'static pattern rule' to match a list of known targets to a pattern
# and then generates the correct rule based on the pattern, where % and $* match
# so for the target 'output/sampler.out' the % matches 'sampler' and depends on programs/sampler.mem
# see: https://www.gnu.org/software/make/manual/html_node/Static-Usage.html
# $(@D) is an automatic variable for the directory of the target, in this case, 'output'

# this does the same as simv, but adds .syn to the output files and compiles syn_simv instead
# run synthesis with: 'make <my_test>.syn.out'
output/%.syn.out: mem/%/Q.mem mem/%/K.mem mem/%/V.mem build/AURA.syn.simv | output
	@$(call PRINT_COLOR, 5, running syn_simv on $<)
	@$(call PRINT_COLOR, 3, this might take a while...)
	./build/AURA.syn.simv \
		+QMEMORY=$(word 1,$^) \
		+KMEMORY=$(word 2,$^) \
		+VMEMORY=$(word 3,$^) \
		+OUTPUT=output/$*.syn \
		> output/$*.syn.log
	@$(call PRINT_COLOR, 6, finished running syn_simv on $<)
	@$(call PRINT_COLOR, 2, output is in output/$*.syn.{out cpi wb})

# Allow us to type 'make <my_program>.out' instead of 'make output/<my_program>.out'
./%.out: output/%.out ;
.PHONY: ./%.out

.PRECIOUS: %.out

# run all programs in one command (use 'make -j' to run multithreaded)
# simulate_all: build/aura.simv compile_all $(PROGRAMS:programs/%=output/%.out)
# simulate_all_syn: build/aura.syn.simv compile_all $(PROGRAMS:programs/%=output/%.syn.out)
# .PHONY: simulate_all simulate_all_syn

################################
# ---- Output Directories ---- #
################################

# Directories for holding build files or run outputs
# Targets that need these directories should add them after a pipe.
# ex: "target: dep1 dep2 ... | build"
build synth output programs/mem:
	mkdir -p $@
# Don't leave any files in these, they will be deleted by clean commands

#####################
# ---- Cleanup ---- #
#####################

# You should only clean your directory if you think something has built incorrectly
# or you want to prepare a clean directory for e.g. git (first check your .gitignore).
# Please avoid cleaning before every build. The point of a makefile is to
# automatically determine which targets have dependencies that are modified,
# and to re-build only those as needed; avoiding re-building everything everytime.

# 'make clean' removes build/output files, 'make nuke' removes all generated files
# 'make clean' does not remove .mem or .dump files
# clean_* commands remove certain groups of files

clean: clean_exe clean_run_files
	@$(call PRINT_COLOR, 6, note: clean is split into multiple commands you can call separately: $^)

# removes all extra synthesis files and the entire output directory
# use cautiously, this can cause hours of recompiling in project 4
nuke: clean clean_output clean_synth clean_programs
	@$(call PRINT_COLOR, 6, note: nuke is split into multiple commands you can call separately: $^)

clean_exe:
	@$(call PRINT_COLOR, 3, removing compiled executable files)
	rm -rf build/                         # remove the entire 'build' folder
	rm -rf *simv *.daidir csrc *.key      # created by simv/syn_simv/vis_simv
	rm -rf vcdplus.vpd vc_hdrs.h          # created by simv/syn_simv/vis_simv
	rm -rf unifiedInference.log xprop.log # created by simv/syn_simv/vis_simv
	rm -rf *.cov cov_report_* cm.log      # coverage files
	rm -rf verdi* novas* *fsdb*           # verdi files
	rm -rf dve* inter.vpd DVEfiles        # old DVE debugger

clean_run_files:
	@$(call PRINT_COLOR, 3, removing per-run outputs)
	rm -rf output/*.out output/*.cpi output/*.wb output/*.log

clean_synth:
	@$(call PRINT_COLOR, 1, removing synthesis files)
	cd synth && rm -rf *.vg *_svsim.sv *.res *.rep *.ddc *.chk *.syn *.out *.db *.svf *.mr *.pvl command.log

clean_output:
	@$(call PRINT_COLOR, 1, removing entire output directory)
	rm -rf output/

clean_programs:
	@$(call PRINT_COLOR, 3, removing program memory files)
	rm -rf programs/*.mem
	@$(call PRINT_COLOR, 3, removing dump files)
	rm -rf programs/*.dump*

.PHONY: clean nuke clean_%

######################
# ---- Printing ---- #
######################

# this is a GNU Make function with two arguments: PRINT_COLOR(color: number, msg: string)
# it does all the color printing throughout the makefile
PRINT_COLOR = if [ -t 0 ]; then tput setaf $(1) ; fi; echo $(2); if [ -t 0 ]; then tput sgr0; fi
# colors: 0:black, 1:red, 2:green, 3:yellow, 4:blue, 5:magenta, 6:cyan, 7:white
# other numbers are valid, but aren't specified in the tput man page

# Make functions are called like this:
# $(call PRINT_COLOR,3,Hello World!)
# NOTE: adding '@' to the start of a line avoids printing the command itself, only the output


# CXX = g++
# CXXFLAGS = -O2 -Wall

# TARGET = gen_qkv_mem
# SRC = gen_qkv_mem.cpp

# MEM_FILES = Q.mem K.mem V.mem

# all: run

# $(TARGET): tb/$(SRC)
# 	$(CXX) $(CXXFLAGS) -o tb/$(TARGET) tb/$(SRC)

# run: $(TARGET)
# 	./$(TARGET)

# clean:
# 	rm -f tb/$(TARGET) output/$(MEM_FILES)


