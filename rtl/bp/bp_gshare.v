//=========================================================================
// bp_gshare.v - GShare correlating branch direction predictor
//=========================================================================
// Index = PC[INDEX_BITS+1:2] XOR GHR. PHT entries are 2-bit saturating
// counters as in bp_bht2. Global history register (GHR) is HIST_BITS wide
// and shifts in the actual outcome on every resolved branch.
//
// Speculative-update warning: this design only updates the GHR on
// resolution (in X), NOT on prediction (in F). That keeps a single source
// of truth and avoids needing a checkpoint stack to roll back the GHR on
// a mispredict. The cost is that branches that fetched while older
// branches are still in flight see a slightly stale GHR. Adequate for the
// performance levels we are targeting; can be revisited if the report
// shows it as a meaningful loss vs ideal.

`ifndef BP_GSHARE_V
`define BP_GSHARE_V

module bp_gshare #(
  parameter INDEX_BITS = 8,           // PHT depth = 2^INDEX_BITS
  parameter HIST_BITS  = 8,           // global history width
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

  reg  [HIST_BITS-1:0] ghr_r;
  reg  [1:0]           pht_r [ENTRIES-1:0];

  // Index width-match for the XOR. Zero-extend the history to a fixed
  // 32-bit width, then truncate to INDEX_BITS — this keeps all bit-slice
  // expressions in-range regardless of whether HIST_BITS is larger or
  // smaller than INDEX_BITS.
  function [INDEX_BITS-1:0] mix;
    input [PC_BITS-1:0]   pc;
    input [HIST_BITS-1:0] hist;
    reg   [INDEX_BITS-1:0] pcbits;
    reg   [INDEX_BITS-1:0] hbits;
    reg   [31:0]           hist_pad;
    begin
      pcbits   = pc[INDEX_BITS+1:2];
      hist_pad = { {(32-HIST_BITS){1'b0}}, hist };
      hbits    = hist_pad[INDEX_BITS-1:0];
      mix      = pcbits ^ hbits;
    end
  endfunction

  wire [INDEX_BITS-1:0] read_idx  = mix(predict_pc, ghr_r);
  wire [INDEX_BITS-1:0] write_idx = mix(update_pc,  ghr_r);

  assign predict_taken = pht_r[read_idx][1];

  wire [1:0] cur  = pht_r[write_idx];
  wire [1:0] next = update_taken
                    ? ((cur == 2'b11) ? 2'b11 : cur + 2'b01)
                    : ((cur == 2'b00) ? 2'b00 : cur - 2'b01);

  integer i;
  always @(posedge clk) begin
    if (reset) begin
      ghr_r <= {HIST_BITS{1'b0}};
      for (i = 0; i < ENTRIES; i = i + 1) begin
        pht_r[i] <= 2'b01;
      end
    end
    else if (update_en) begin
      pht_r[write_idx] <= next;
      ghr_r <= { ghr_r[HIST_BITS-2:0], update_taken };
    end
  end

  wire _unused = update_mispredict;

endmodule

`endif
