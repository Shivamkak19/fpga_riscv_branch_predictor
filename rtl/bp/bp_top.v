//=========================================================================
// bp_top.v - Selectable top-level branch predictor
//=========================================================================
// Wraps one of {static_nt, bht1, bht2, gshare} based on `BP_*` defines.
// All variants share the same predict / update interface so the core only
// instantiates this single module and switches by define at build time.
//
// Defines (mutually exclusive):
//   BP_STATIC_NT  -> always predict not-taken
//   BP_BHT1       -> 1-bit BHT
//   BP_BHT2       -> 2-bit BHT (default if none specified)
//   BP_GSHARE     -> GShare with 2-bit counters

`ifndef BP_TOP_V
`define BP_TOP_V

`include "bp_static_nt.v"
`include "bp_bht1.v"
`include "bp_bht2.v"
`include "bp_gshare.v"

module bp_top #(
  parameter PC_BITS    = 32,
  parameter INDEX_BITS = 8,
  parameter HIST_BITS  = 8
) (
  input                clk,
  input                reset,

  input  [PC_BITS-1:0] predict_pc,
  output               predict_taken,

  input                update_en,
  input  [PC_BITS-1:0] update_pc,
  input                update_taken,
  input                update_mispredict
);

`ifdef BP_STATIC_NT
  bp_static_nt #(.PC_BITS(PC_BITS)) u_bp (
    .clk              (clk),
    .reset            (reset),
    .predict_pc       (predict_pc),
    .predict_taken    (predict_taken),
    .update_en        (update_en),
    .update_pc        (update_pc),
    .update_taken     (update_taken),
    .update_mispredict(update_mispredict)
  );
`elsif BP_BHT1
  bp_bht1 #(.PC_BITS(PC_BITS), .INDEX_BITS(INDEX_BITS)) u_bp (
    .clk              (clk),
    .reset            (reset),
    .predict_pc       (predict_pc),
    .predict_taken    (predict_taken),
    .update_en        (update_en),
    .update_pc        (update_pc),
    .update_taken     (update_taken),
    .update_mispredict(update_mispredict)
  );
`elsif BP_GSHARE
  bp_gshare #(.PC_BITS(PC_BITS), .INDEX_BITS(INDEX_BITS), .HIST_BITS(HIST_BITS)) u_bp (
    .clk              (clk),
    .reset            (reset),
    .predict_pc       (predict_pc),
    .predict_taken    (predict_taken),
    .update_en        (update_en),
    .update_pc        (update_pc),
    .update_taken     (update_taken),
    .update_mispredict(update_mispredict)
  );
`else
  // Default: 2-bit BHT
  bp_bht2 #(.PC_BITS(PC_BITS), .INDEX_BITS(INDEX_BITS)) u_bp (
    .clk              (clk),
    .reset            (reset),
    .predict_pc       (predict_pc),
    .predict_taken    (predict_taken),
    .update_en        (update_en),
    .update_pc        (update_pc),
    .update_taken     (update_taken),
    .update_mispredict(update_mispredict)
  );
`endif

endmodule

`endif
