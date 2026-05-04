//=========================================================================
// Reorder Buffer for Out-of-Order RISC-V Processor
//=========================================================================

`ifndef RISCV_CORE_REORDERBUFFER_V
`define RISCV_CORE_REORDERBUFFER_V

module riscv_CoreReorderBuffer
(
  input         clk,
  input         reset,

  input         rob_alloc_req_val,
  output        rob_alloc_req_rdy,
  input  [ 4:0] rob_alloc_req_preg,

  output [ 3:0] rob_alloc_resp_slot,

  input         rob_fill_val,
  input  [ 3:0] rob_fill_slot,

  output        rob_commit_wen,
  output [ 3:0] rob_commit_slot,
  output [ 4:0] rob_commit_rf_waddr
);

  // ROB state arrays (16 entries)
  reg        valid   [15:0];
  reg        pending [15:0];
  reg  [4:0] preg    [15:0];

  // Head and tail pointers (4-bit, wrapping around 16 entries)
  reg [3:0] head;
  reg [3:0] tail;

  // Full/empty detection using an extra count or comparing head==tail with valid
  // ROB is full when tail has wrapped around and caught up to head
  // We track the number of valid entries
  reg [4:0] count; // 0..16

  wire rob_full  = (count == 5'd16);
  wire rob_empty = (count == 5'd0);

  // Allocation: ROB is ready if not full
  assign rob_alloc_req_rdy   = !rob_full;
  assign rob_alloc_resp_slot = tail;

  // Commit: head entry is valid and not pending (result has been written back)
  wire can_commit = !rob_empty && valid[head] && !pending[head];

  assign rob_commit_wen      = can_commit;
  assign rob_commit_slot     = head;
  assign rob_commit_rf_waddr = preg[head];

  // Determine if alloc and commit happen this cycle
  wire do_alloc  = rob_alloc_req_val && rob_alloc_req_rdy;
  wire do_commit = can_commit;

  integer i;

  always @(posedge clk) begin
    if (reset) begin
      head  <= 4'd0;
      tail  <= 4'd0;
      count <= 5'd0;
      for (i = 0; i < 16; i = i + 1) begin
        valid[i]   <= 1'b0;
        pending[i] <= 1'b0;
        preg[i]    <= 5'd0;
      end
    end else begin

      // Fill: clear pending bit when writeback data arrives
      if (rob_fill_val) begin
        pending[rob_fill_slot] <= 1'b0;
      end

      // Allocate: set up new entry at tail
      if (do_alloc) begin
        valid[tail]   <= 1'b1;
        pending[tail] <= 1'b1;
        preg[tail]    <= rob_alloc_req_preg;
        tail          <= tail + 4'd1;
      end

      // Commit: clear entry at head
      if (do_commit) begin
        valid[head] <= 1'b0;
        head        <= head + 4'd1;
      end

      // Update count
      if (do_alloc && !do_commit)
        count <= count + 5'd1;
      else if (!do_alloc && do_commit)
        count <= count - 5'd1;
      // else count stays the same (both or neither)
    end
  end

endmodule

`endif
