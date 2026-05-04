#=========================================================================
# bp Subpackage — Branch predictor for ECE 475 term project (riscvooo)
#=========================================================================
# Pre-decoder + selectable direction predictors (BHT-1, BHT-2,
# two-level/PC⊕GHR, static_nt) + Return Address Stack. The header
# `bp_top.v` is what the riscvooo core instantiates; the rest are
# leaf modules selected by `BP_*` defines passed via the build/Makefile's
# BP_DEFINES variable.

bp_deps =

bp_srcs = \
  bp_predecode.v \
  bp_static_nt.v \
  bp_bht1.v \
  bp_bht2.v \
  bp_two_level.v \
  bp_ras.v \
  bp_top.v \

bp_test_srcs =

bp_prog_srcs =
