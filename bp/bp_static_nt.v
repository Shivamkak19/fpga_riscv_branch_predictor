//=========================================================================
// bp_static_nt.v - Static "always not taken" branch direction predictor
//=========================================================================
// The simplest baseline predictor: every conditional branch is predicted
// not-taken. JAL is still predicted taken externally (target is decodable).
// Provides the same interface as the other predictors so the integration
// point in the core can be variant-agnostic.

`ifndef BP_STATIC_NT_V
`define BP_STATIC_NT_V

module bp_static_nt #(
  parameter PC_BITS = 32
) (
  input              clk,
  input              reset,

  // Predict port (combinational)
  input  [PC_BITS-1:0] predict_pc,
  output               predict_taken,

  // Update port (sequential, end of resolution stage)
  input                update_en,
  input  [PC_BITS-1:0] update_pc,
  input                update_taken,
  input                update_mispredict
);

  // No state. Always predict not-taken.
  wire _unused = |predict_pc | reset | update_en | (|update_pc) |
                 update_taken | update_mispredict;
  assign predict_taken = 1'b0;

endmodule

`endif
