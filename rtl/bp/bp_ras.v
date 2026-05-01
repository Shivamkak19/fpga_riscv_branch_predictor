//=========================================================================
// bp_ras.v - Return Address Stack
//=========================================================================
// Small LIFO of return target addresses, used to predict function-return
// JALR. On a function call (JAL or JALR with rd == x1) the F stage pushes
// pc+4 onto the stack; on a function return (JALR with rd != x1 and rs1
// == x1) the F stage pops the top and uses it as the predicted target.
//
// Push and pop happen combinationally w.r.t. the F-stage instruction —
// the actual write into the stack array is sequential (next clock edge).
// `top_addr` is the address that would be popped (= stack[top_ptr-1]) and
// is exposed combinationally so the F-stage redirect logic can use it
// without an extra cycle of latency.
//
// Speculation: pushes/pops happen on every valid F-stage call/return,
// even if the surrounding code is on a mispredicted path. A mispredict
// will squash F and D, but the RAS state may be corrupted (off by one or
// hold a stale entry). For workloads with rare mispredicts on calls /
// returns this is fine; a real production design would checkpoint and
// roll back. The depth (parameterized below) absorbs a few entries of
// pollution before correctness is meaningfully degraded.

`ifndef BP_RAS_V
`define BP_RAS_V

module bp_ras #(
  parameter DEPTH    = 8,
  parameter PC_BITS  = 32,
  parameter PTR_BITS = 3   // log2(DEPTH); set explicitly to avoid $clog2 issues
) (
  input                clk,
  input                reset,

  // F-stage events
  input                push_en,
  input  [PC_BITS-1:0] push_addr,
  input                pop_en,

  // Combinational read of top
  output [PC_BITS-1:0] top_addr,
  output               top_valid
);

  reg [PC_BITS-1:0] stack [DEPTH-1:0];
  reg [PTR_BITS-1:0] top_ptr;        // # of valid entries (pointer to next free)
  reg               nonempty;

  wire [PTR_BITS-1:0] top_idx_w = top_ptr - 1'b1;
  assign top_addr  = stack[top_idx_w];
  assign top_valid = nonempty;

  integer i;
  always @(posedge clk) begin
    if (reset) begin
      top_ptr  <= {PTR_BITS{1'b0}};
      nonempty <= 1'b0;
      for (i = 0; i < DEPTH; i = i + 1) stack[i] <= {PC_BITS{1'b0}};
    end
    else begin
      // Simultaneous push + pop = overwrite the current top.
      if (push_en && pop_en) begin
        if (nonempty) begin
          stack[top_idx_w] <= push_addr;
        end
        // counts unchanged
      end
      else if (push_en) begin
        stack[top_ptr] <= push_addr;
        top_ptr        <= top_ptr + 1'b1;
        nonempty       <= 1'b1;
      end
      else if (pop_en) begin
        if (top_ptr == {{(PTR_BITS-1){1'b0}}, 1'b1}) nonempty <= 1'b0;
        if (nonempty) top_ptr <= top_ptr - 1'b1;
      end
    end
  end

endmodule

`endif
