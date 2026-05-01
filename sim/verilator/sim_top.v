//=========================================================================
// sim_top.v - Verilator testbench for riscvlong with branch-predictor stats
//=========================================================================
// Drives riscv_Core against a 1MB dual-port test memory. Loads program from
// $readmemh, detects PASS/FAIL via csr_status, tracks cycles, retired
// instructions, branches and (for predictor variants) mispredicts via
// hierarchical references into the core.
//
// Plusargs:
//   +exe=<path.vmh>    program image (required)
//   +max-cycles=N      simulation timeout (default 200000)
//   +stats=1           print stats summary at end
//   +verbose=1         print one-line per-retired-instruction trace
//   +vcd=1             dump VCD to <exe>.vcd
//
// Notes:
//   - reset_mem / reset_proc are initialized to 1 to avoid X propagation.
//   - Build with --x-initial 0 so uninitialized regs start at 0 (matches
//     the synthesizable behavior where ASIC/FPGA flops come up at 0 after
//     global reset).
//   - All sim control + termination lives in a single posedge-clk always
//     block (combinational always blocks with $finish/#delays caused the
//     timing scheduler to deadlock).

`include "riscvlong-Core.v"
`include "vc-TestDualPortRandDelayMem.v"

module sim_top;

  reg clk   = 1'b0;
  reg reset = 1'b1;

  always #5 clk = ~clk;

  wire [31:0] status;

  wire [`VC_MEM_REQ_MSG_SZ(32,32)-1:0] imemreq_msg;
  wire                                 imemreq_val;
  wire                                 imemreq_rdy;
  wire   [`VC_MEM_RESP_MSG_SZ(32)-1:0] imemresp_msg;
  wire                                 imemresp_val;

  wire [`VC_MEM_REQ_MSG_SZ(32,32)-1:0] dmemreq_msg;
  wire                                 dmemreq_val;
  wire                                 dmemreq_rdy;
  wire   [`VC_MEM_RESP_MSG_SZ(32)-1:0] dmemresp_msg;
  wire                                 dmemresp_val;

  // Reset retiming chain — explicitly initialized to 1.
  reg reset_mem  = 1'b1;
  reg reset_proc = 1'b1;
  always @(posedge clk) begin
    reset_mem  <= reset;
    reset_proc <= reset_mem;
  end

  riscv_Core proc (
    .clk          (clk),
    .reset        (reset_proc),
    .imemreq_msg  (imemreq_msg),
    .imemreq_val  (imemreq_val),
    .imemreq_rdy  (imemreq_rdy),
    .imemresp_msg (imemresp_msg),
    .imemresp_val (imemresp_val),
    .dmemreq_msg  (dmemreq_msg),
    .dmemreq_val  (dmemreq_val),
    .dmemreq_rdy  (dmemreq_rdy),
    .dmemresp_msg (dmemresp_msg),
    .dmemresp_val (dmemresp_val),
    .csr_status   (status)
  );

  vc_TestDualPortRandDelayMem
  #(
    .p_mem_sz    (1<<20),
    .p_addr_sz   (32),
    .p_data_sz   (32),
    .p_max_delay (0)
  )
  mem
  (
    .clk          (clk),
    .reset        (reset_mem),
    .memreq0_val  (imemreq_val),
    .memreq0_rdy  (imemreq_rdy),
    .memreq0_msg  (imemreq_msg),
    .memresp0_val (imemresp_val),
    .memresp0_rdy (1'b1),
    .memresp0_msg (imemresp_msg),
    .memreq1_val  (dmemreq_val),
    .memreq1_rdy  (dmemreq_rdy),
    .memreq1_msg  (dmemreq_msg),
    .memresp1_val (dmemresp_val),
    .memresp1_rdy (1'b1),
    .memresp1_msg (dmemresp_msg)
  );

  //----------------------------------------------------------------------
  // Plusargs and program load
  //----------------------------------------------------------------------

  reg [4095:0] exe_filename;
  reg [4095:0] vcd_filename;
  reg   [31:0] max_cycles;
  reg          verbose;
  reg          stats;
  reg          vcd;

  integer fh;

  initial begin
    if ( !$value$plusargs( "exe=%s", exe_filename ) ) begin
      $display("ERROR: no +exe=<path.vmh> supplied");
      $finish;
    end
    fh = $fopen( exe_filename, "r" );
    if ( !fh ) begin
      $display("ERROR: cannot open %0s", exe_filename);
      $finish;
    end
    $fclose(fh);
    $readmemh( exe_filename, mem.mem.m );

    if ( !$value$plusargs( "max-cycles=%d", max_cycles ) ) max_cycles = 32'd200000;
    if ( !$value$plusargs( "verbose=%d",    verbose    ) ) verbose    = 1'b0;
    if ( !$value$plusargs( "stats=%d",      stats      ) ) stats      = 1'b0;
    if ( !$value$plusargs( "vcd=%d",        vcd        ) ) vcd        = 1'b0;

    if ( vcd ) begin
      vcd_filename = { exe_filename[4095:32], ".vcd" };
      $dumpfile(vcd_filename);
      $dumpvars;
    end

    #1  reset = 1'b1;
    #50 reset = 1'b0;
  end

  //----------------------------------------------------------------------
  // Counters (testbench-driven; do not depend on csr_stats / stats_en
  // inside the dut, which we don't manipulate from outside)
  //----------------------------------------------------------------------

  integer total_cycles    = 0;
  integer retired_inst    = 0;
  integer total_branches  = 0;  // conditional branches resolved in X
  integer taken_branches  = 0;
  integer total_jumps     = 0;  // JAL/JALR redirected in D
  integer mispredicts     = 0;  // for predictor variants
  integer pred_branches   = 0;  // branches that the predictor weighed in on
  integer pred_correct    = 0;

  // Detect retirement: D-stage instruction that is valid and not stalled
  // counts as a retired (or about-to-retire) instruction. The lab's CSR
  // counter uses the same definition.
  always @(posedge clk) begin
    if (!reset_proc) begin
      total_cycles <= total_cycles + 1;

      if (proc.ctrl.inst_val_Dhl && !proc.ctrl.stall_Dhl)
        retired_inst <= retired_inst + 1;

      // Conditional branches resolve in X. br_sel_Xhl != br_none means
      // the X-stage instruction is a conditional branch. Use the raw
      // any_br_taken_Xhl signal (always reflects actual outcome) rather
      // than brj_taken_Xhl (which becomes mispredict-only when the
      // predictor is enabled).
      if (proc.ctrl.inst_val_Xhl && (proc.ctrl.br_sel_Xhl != 3'd0)) begin
        total_branches <= total_branches + 1;
        if (proc.ctrl.any_br_taken_Xhl) taken_branches <= taken_branches + 1;
      end

      // Unconditional jumps redirected in D (J_EN bit set).
      if (proc.ctrl.inst_val_Dhl && proc.ctrl.brj_taken_Dhl &&
          !proc.ctrl.stall_Dhl)
        total_jumps <= total_jumps + 1;

`ifdef BP_ENABLED
      if (proc.ctrl.bp_resolve_Xhl) begin
        pred_branches <= pred_branches + 1;
        if (proc.ctrl.bp_correct_Xhl) pred_correct <= pred_correct + 1;
        else                          mispredicts  <= mispredicts  + 1;
      end
`endif
    end
  end

  //----------------------------------------------------------------------
  // Verbose trace: print one line per instruction reaching W stage.
  //----------------------------------------------------------------------

  always @(posedge clk) begin
    if (!reset_proc && verbose && proc.ctrl.inst_val_Whl) begin
      $display("[trace] pc=%h inst=%h",
               proc.dpath.pc_Whl, proc.ctrl.ir_Whl);
    end
  end

  //----------------------------------------------------------------------
  // Termination: PASS/FAIL via csr_status, plus cycle-count timeout.
  //----------------------------------------------------------------------

  reg [31:0] cycle_count    = 32'd0;
  reg        finish_pending = 1'b0;
  real       ipc;

  always @(posedge clk) begin
    cycle_count <= cycle_count + 32'd1;

    if (!reset_proc && (status != 32'd0) && !finish_pending) begin
      finish_pending <= 1'b1;
      if (status == 32'd1) $display("*** PASSED ***");
      else                 $display("*** FAILED *** (status=%0d)", status);

      if (stats) begin
        ipc = (total_cycles == 0) ? 0.0 :
              ($itor(retired_inst) / $itor(total_cycles));
        $display("--------------------------------------------");
        $display(" STATS");
        $display("--------------------------------------------");
        $display(" status          = %0d", status);
        $display(" cycles          = %0d", total_cycles);
        $display(" retired_inst    = %0d", retired_inst);
        $display(" ipc             = %f",  ipc);
        $display(" branches        = %0d", total_branches);
        $display(" taken_branches  = %0d", taken_branches);
        $display(" jumps           = %0d", total_jumps);
`ifdef BP_ENABLED
        $display(" pred_branches   = %0d", pred_branches);
        $display(" pred_correct    = %0d", pred_correct);
        $display(" mispredicts     = %0d", mispredicts);
`endif
      end
      $finish;
    end

    if (cycle_count > max_cycles) begin
      $display("*** TIMEOUT *** at %0d cycles", cycle_count);
      if (stats) begin
        $display(" cycles=%0d retired=%0d branches=%0d taken=%0d jumps=%0d",
                 total_cycles, retired_inst,
                 total_branches, taken_branches, total_jumps);
      end
      $finish;
    end
  end

endmodule
