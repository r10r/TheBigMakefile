# FIXME exclude includes from libs /-isystem folder from formatting 
default: all

# [ settings ]
# ============
# Variables that might be overwritten by commandline or module.mk
BASE_DIR := $(realpath $(PWD))
MODULES := 
OS := $(shell uname -s)
ARCH :=$(shell uname -m)

# A macro that evaluates to the local directory path of an included Makefile.
LOCAL_DIR = $(realpath $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST)))))
SMAKE_DIR := $(LOCAL_DIR)

# Each module may append to the following variables
# All objects that should be generated
OBJS :=
# All sources used for object generation (sources / includes ...)
SRC :=
# Generated executables
PROGRAMS :=
# Generated test executables
TESTS :=


# include project makefile
-include $(BASE_DIR)/project.mk

$(info BASE_DIR: $(BASE_DIR))
$(info SMAKE_DIR: $(SMAKE_DIR))
$(info MODULES: $(MODULES))
$(info profile: $(profile))
OBJECT_DEPENDENCY_SCRIPT ?= $(SMAKE_DIR)/bin/depend.sh
$(info Using dependency script: $(OBJECT_DEPENDENCY_SCRIPT))
COVERAGE_TOOL ?= $(SMAKE_DIR)/bin/coverage.sh
$(info Using coverage script: $(COVERAGE_TOOL))
COVERAGE_REPORT_TOOL ?= $(SMAKE_DIR)/bin/decover.sh
$(info Using coverage report script: $(COVERAGE_REPORT_TOOL))
TEST_RUNNER ?= $(SMAKE_DIR)/bin/valgrind-testrunner.sh
$(info Using test runner script: $(TEST_RUNNER))
FORMATTER_TOOL ?= $(SMAKE_DIR)/bin/uncrustify.sh
$(info Using formatter script: $(FORMATTER_TOOL))

# Include module makefiles module.mk.
ifneq ($(MAKECMDGOALS),clean)
ifneq ($(MAKECMDGOALS),realclean)
   include $(patsubst %,%/module.mk,$(MODULES))
endif
endif

# look for include files in each of the modules
# use -isystem ?
#CFLAGS += $(patsubst %,-I%,$(MODULES))
CFLAGS += -I$(SMAKE_DIR) -I$(BASE_DIR)
INCLUDES := $(filter -I%,$(CFLAGS))

# [ os ]
# ======
# Set platform specific compiler/linker flags.
ifeq ($(DEBUG), true)
ifeq ($(OS),Darwin)
CFLAGS += -gdwarf-2 -g -O0 -fno-inline
endif
ifeq ($(OS),Linux)
CFLAGS += -g -O0 -fno-inline
endif
endif


# [ templates ]
# =============
# Templates for programs and tests.
# You can set objects,CFLAGS,LDFLAGS per program/test.
define PROGRAM_template
$(1): $$($(1)_OBJS) $(1).c
	$$(CC) $$(CFLAGS) $$(LDFLAGS) $$($(1)_FLAGS) \
	-o $(1) $$($(1)_OBJS) $$($(1)_LIBS)

OBJS += $$($(1)_OBJS)
endef

PROGRAMS += $(TESTS)
$(foreach prog,$(PROGRAMS),$(eval $(call PROGRAM_template,$(prog))))

# [ dependency tracking ]
# =======================
# Calculate dependencies for object.
# Regenerate dependency makefile when object is updated.
%.o.mk:
	$(OBJECT_DEPENDENCY_SCRIPT) $*.c $(INCLUDES) $*.c > $@
	
# Include a dependency file per object.
# The dependency file is created automatically by the rule above.
include $(OBJS:=.mk)

# after all module/dependency makefiles have been included
# it's time to remove duplicate objects/sources
OBJS := $(sort $(OBJS))
SRC := $(sort $(SRC))

all: format $(PROGRAMS) test decover;
build: $(PROGRAMS);

# make these available to shell scripts
export SMAKE_DIR
export BASE_DIR

# [ format ]
# ==========
# Keep your code nice and shiny ;)

# unconditionally format all sources
# e.g after changing the formatter configuration
.PHONY: reformat
reformat:
	$(FORMATTER_TOOL) $(SRC) && touch .formatted

# format modified sources.
.formatted: $(SRC)
	$(FORMATTER_TOOL) $? && touch .formatted

format: .formatted;

# [ tests ]
# =========
# Note: piping the test runner output into
# a file using tee will return the exit code of tee (0)
%.testresult: % 
	$(TEST_RUNNER) $*

test: $(TESTS:=.testresult);


# [ gcov ]
# ========
# Tests must execute to generate the GCOV files.
# All objects not linked to any test must be build 
# to include include them in the coverage report.
# TODO create textmate scheme for GCOV file format 

.PRECIOUS: %.gcno
%.gcno: $(OBJS) $(TESTS);

.PRECIOUS: %.cov
%.cov: %.gcno
	$(COVERAGE_TOOL) $*.o

# generate all coverage files
cov: $(OBJS:.o=.cov);

# generate a simple coverage report summary
decover: cov
	$(COVERAGE_REPORT_TOOL)


# [ clean ]
# =========
# Should remove all generated artifacts
BUILD_ARTIFACTS := $(PROGRAMS) \
	$(wildcard $(MODULES:=/*.o)) \
	$(wildcard $(MODULES:=/*.testresult)) \
	$(wildcard $(MODULES:=/*.gcda)) \
	$(wildcard $(MODULES:=/*.gcno)) \
	$(wildcard $(MODULES:=/*.cov)) \
	$(wildcard $(MODULES:=/*.unc-backup~)) \
	$(wildcard $(MODULES:=/*.unc-backup.md5~)) \

ARTIFACTS := $(wildcard .formatted) \
	$(wildcard $(MODULES:=/*.o.mk))

.PHONY: clean
clean:
	rm -f $(BUILD_ARTIFACTS)
	
realclean:
	rm -f $(BUILD_ARTIFACTS) $(ARTIFACTS)


# [ ragel ]
# ===========
# object generation rules
# sources generated with -G2 are large
# but compiler shrinks them massively 
# (if debugging/profiling is not enabled)
.PRECIOUS: %.c
%.c: %.rl
	ragel -L -G2 -o $@ $<	

%.dot: %.rl
	ragel -V -p -o $@ $<

%.png: %.dot
	dot -Tpng $< -o $@
	
	
# Optionally append new rules or overwrite existing ones.
-include Rules.mk

# Filter out unsupported CFLAGS per platform/compiler
CFLAGS := $(filter-out $(CFLAGS_UNSUPPORTED),$(CFLAGS))
