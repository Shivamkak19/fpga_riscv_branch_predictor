//=========================================================================
// bp_bht1.v - 1-bit Branch History Table
//=========================================================================
// A direct-mapped table of single-bit predictions, indexed by the low bits
// of the branch PC (above the 2-LSB byte-offset). Each bit holds the last
// observed direction for that index: 1 = taken, 0 = not-taken. Read is
// combinational; update is sequential at end of the resolution stage.

`ifndef BP_BHT1_V
`define BP_BHT1_V

module bp_bht1 #(
  parameter INDEX_BITS = 8,           // 2^INDEX_BITS entries
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

  reg [ENTRIES-1:0] table_r;

  wire [INDEX_BITS-1:0] read_idx  = predict_pc[INDEX_BITS+1:2];
  wire [INDEX_BITS-1:0] write_idx = update_pc [INDEX_BITS+1:2];

  // Combinational read
  assign predict_taken = table_r[read_idx];

  // Sequential update
  integer i;
  always @(posedge clk) begin
    if (reset) begin
      // Init all entries to not-taken (0). Cheap on FPGA: just clears the
      // distributed RAM via reset; on ASIC this would be a power-on default.
      for (i = 0; i < ENTRIES; i = i + 1) begin
        table_r[i] <= 1'b0;
      end
    end
    else if (update_en) begin
      table_r[write_idx] <= update_taken;
    end
  end

  wire _unused = update_mispredict;

endmodule

`endif
