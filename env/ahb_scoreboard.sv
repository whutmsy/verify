class ahb_scoreboard extends uvm_scoreboard;

  uvm_analysis_imp #(ahb_transaction, ahb_scoreboard) sb_imp;

  bit [31:0] ref_ctrl0;
  bit [31:0] ref_ctrl1;

  int pass_count;
  int fail_count;

  `uvm_component_utils(ahb_scoreboard)

  function new(string name = "ahb_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sb_imp = new("sb_imp", this);
  endfunction

  function void reset_model();
    ref_ctrl0 = 32'b0;
    ref_ctrl1 = 32'b0;
  endfunction

  function void write(ahb_transaction tr);
    if(!tr.HWRITE) begin
      compare_read(tr);
    end else begin
      update_model(tr);
    end
  endfunction

  function void update_model(ahb_transaction tr);
    case (tr.HADDR[7:0])
      8'h00: ref_ctrl0 = tr.HWDATA;
      8'h04: ref_ctrl1 = tr.HWDATA;
      default: `uvm_info(get_type_name(), $sformatf("Write to unsupported addr: %0h", tr.HADDR), UVM_HIGH)
    endcase
    `uvm_info(get_type_name(), $sformatf("REF updated addr: %0h data: %0h ref_ctrl0: %0h ref_ctrl1: %0h", tr.HADDR, tr.HWDATA, ref_ctrl0, ref_ctrl1), UVM_MEDIUM);
  endfunction

  function void compare_read(ahb_transaction tr);
    bit [31:0] exp;
    case (tr.HADDR[7:0])
      8'h00: exp = ref_ctrl0;
      8'h04: exp = ref_ctrl1;
      default: exp = 32'b0;
    endcase
    if(tr.HRDATA == exp) begin
      pass_count++;
      `uvm_info(get_type_name(), $sformatf("PASS addr: %0h data: %0h", tr.HADDR, tr.HRDATA), UVM_LOW);
    end else begin
      fail_count++;
      `uvm_error(get_type_name(), $sformatf("FAIL addr: %0h got: %0h exp: %0h", tr.HADDR, tr.HRDATA, exp));
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf("SCOREBOARD SUMMARY: pass=%0d fail=%0d", pass_count, fail_count), UVM_LOW);
    if(fail_count > 0)
      `uvm_error(get_type_name(), $sformatf("TEST FAILED with %0d mismatches", fail_count));
  endfunction

endclass
