//=========================================================================
// bp_bht2.v - 2-bit saturating-counter Branch History Table
//=========================================================================
// Same indexing as bp_bht1, but each entry is a 2-bit saturating counter.
// State encoding:
//   00 = strongly not-taken
//   01 = weakly   not-taken
//   10 = weakly   taken
//   11 = strongly taken
// Predict taken when the high bit is 1. On update: increment toward taken
// if the actual outcome was taken, else decrement, saturating at 00 / 11.
// One-bit-of-hysteresis means a single mispredict in a streak doesn't flip
// the prediction.

`ifndef BP_BHT2_V
`define BP_BHT2_V

module bp_bht2 #(
  parameter INDEX_BITS = 8,
  parameter PC_BITS    = 32
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

  localparam ENTRIES = (1 << INDEX_BITS);

  reg [1:0] table_r [ENTRIES-1:0];

  wire [INDEX_BITS-1:0] read_idx  = predict_pc[INDEX_BITS+1:2];
  wire [INDEX_BITS-1:0] write_idx = update_pc [INDEX_BITS+1:2];

  assign predict_taken = table_r[read_idx][1];

  // Saturating increment / decrement
  wire [1:0] cur  = table_r[write_idx];
  wire [1:0] next = update_taken
                    ? ((cur == 2'b11) ? 2'b11 : cur + 2'b01)
                    : ((cur == 2'b00) ? 2'b00 : cur - 2'b01);

  integer i;
  always @(posedge clk) begin
    if (reset) begin
      // Init weakly not-taken (01) — gives the predictor a slight bias
      // away from taken on cold branches but only one mispredict to flip.
      for (i = 0; i < ENTRIES; i = i + 1) begin
        table_r[i] <= 2'b01;
      end
    end
    else if (update_en) begin
      table_r[write_idx] <= next;
    end
  end

  wire _unused = update_mispredict;

endmodule

`endif
