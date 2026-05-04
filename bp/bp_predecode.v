//=========================================================================
// bp_predecode.v - Pre-decode of fetched instruction for branch prediction
//=========================================================================
// Pure combinational. Takes a 32-bit instruction and its PC, and produces:
//   is_branch  : conditional branch (B-type, opcode 0x63)
//   is_jal     : unconditional direct jump (J-type, opcode 0x6F)
//   is_jalr    : indirect jump (I-type, opcode 0x67)
//   br_target  : pc + imm_sb       (valid when is_branch)
//   jal_target : pc + imm_uj       (valid when is_jal)
//
// JALR target depends on rs1, which isn't read until D — so we don't compute
// it here. The base predictor leaves JALR as not-taken (current behavior:
// resolves in D with brj_taken_Dhl). A return-address-stack module can
// override this externally if added later.

`ifndef BP_PREDECODE_V
`define BP_PREDECODE_V

module bp_predecode (
  input  [31:0] inst,
  input  [31:0] pc,
  output        is_branch,
  output        is_jal,
  output        is_jalr,
  output [31:0] br_target,
  output [31:0] jal_target,
  // Call / return classification for the Return Address Stack:
  //   is_call:   any instruction that should push pc+4 onto the RAS
  //              (JAL with rd==x1, JALR with rd==x1)
  //   is_return: any instruction that should pop the RAS for its target
  //              (JALR with rs1==x1 and rd != x1)
  output        is_call,
  output        is_return
);

  wire [6:0] opcode = inst[6:0];
  wire [4:0] rd     = inst[11:7];
  wire [4:0] rs1    = inst[19:15];

  assign is_branch = (opcode == 7'b1100011);
  assign is_jal    = (opcode == 7'b1101111);
  assign is_jalr   = (opcode == 7'b1100111);

  wire rd_is_link  = (rd  == 5'd1);
  wire rs1_is_link = (rs1 == 5'd1);

  assign is_call   = (is_jal && rd_is_link)
                  || (is_jalr && rd_is_link);
  assign is_return = (is_jalr && rs1_is_link && !rd_is_link);

  // B-type immediate: imm[12|10:5|4:1|11] = inst[31|30:25|11:8|7]
  wire [31:0] imm_sb = {
    {19{inst[31]}},
    inst[31],
    inst[7],
    inst[30:25],
    inst[11:8],
    1'b0
  };

  // J-type immediate: imm[20|10:1|11|19:12] = inst[31|30:21|20|19:12]
  wire [31:0] imm_uj = {
    {11{inst[31]}},
    inst[31],
    inst[19:12],
    inst[20],
    inst[30:21],
    1'b0
  };

  assign br_target  = pc + imm_sb;
  assign jal_target = pc + imm_uj;

endmodule

`endif
