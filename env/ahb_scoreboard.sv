class ahb_scoreboard extends uvm_scoreboard;

  uvm_analysis_imp #(ahb_transaction, ahb_scoreboard) sb_imp;

  // 参考模型：寄存器区
  bit [31:0] ref_ctrl0;
  bit [31:0] ref_ctrl1;
  bit [31:0] ref_ctrl2;
  bit [31:0] ref_ctrl3;
  // 参考模型：SRAM 区（256 word）
  bit [31:0] ref_mem [0:255];

  int pass_count;
  int fail_count;
  int err_count;    // ERROR 响应事务计数

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
    ref_ctrl2 = 32'b0;
    ref_ctrl3 = 32'b0;
    foreach (ref_mem[i]) ref_mem[i] = 32'b0;
  endfunction

  // 主入口：根据事务属性分发到更新/比较
  function void write(ahb_transaction tr);
    if (tr.HRESP) begin
      err_count++;
      `uvm_info(get_type_name(), $sformatf("ERROR response captured: addr: %0h write: %0b", tr.HADDR, tr.HWRITE), UVM_MEDIUM);
      return;
    end
    if (!tr.HWRITE) begin
      compare_read(tr);
    end else begin
      update_model(tr);
    end
  endfunction

  // 参考模型更新（写事务）
  function void update_model(ahb_transaction tr);
    bit [31:0] new_val;
    // 寄存器区（0x00 - 0x0F）
    if (tr.HADDR[15:0] <= 16'h000F) begin
      case (tr.HADDR[4:2])
        3'd0: begin new_val = merge_write(ref_ctrl0, tr); ref_ctrl0 = new_val; end
        3'd1: begin new_val = merge_write(ref_ctrl1, tr); ref_ctrl1 = new_val; end
        3'd2: begin new_val = merge_write(ref_ctrl2, tr); ref_ctrl2 = new_val; end
        3'd3: begin new_val = merge_write(ref_ctrl3, tr); ref_ctrl3 = new_val; end
        default: `uvm_info(get_type_name(), $sformatf("Write to reserved reg addr: %0h (ignored)", tr.HADDR), UVM_HIGH)
      endcase
    end
    // SRAM 区（0x0020 - 0x041F）
    else if (tr.HADDR[15:0] >= 16'h0020 && tr.HADDR[15:0] <= 16'h041F) begin
      ref_mem[tr.HADDR[9:2] - 8'd8] = merge_write(ref_mem[tr.HADDR[9:2] - 8'd8], tr);
    end
    else begin
      `uvm_info(get_type_name(), $sformatf("Write to unsupported addr: %0h (should be ERROR)", tr.HADDR), UVM_HIGH)
    end
    `uvm_info(get_type_name(), $sformatf("REF updated addr: %0h data: %0h hsize: %0h", tr.HADDR, tr.HWDATA, tr.HSIZE), UVM_MEDIUM);
  endfunction

  // 字节合并写：按 HSIZE/HADDR 将总线 HWDATA（lane 对齐）合并进原值
  //   （与 DUT 写行为一致：写入 lane k 的数据 = HWDATA[8k+7:8k]）
  function bit [31:0] merge_write(bit [31:0] old, ahb_transaction tr);
    case (tr.HSIZE)
      3'b000: begin
        case (tr.HADDR[1:0])
          2'd0: merge_write = {old[31:8],  tr.HWDATA[7:0]};
          2'd1: merge_write = {old[31:16], tr.HWDATA[15:8], old[7:0]};
          2'd2: merge_write = {old[31:24], tr.HWDATA[23:16], old[15:0]};
          2'd3: merge_write = {tr.HWDATA[31:24], old[23:0]};
        endcase
      end
      3'b001: begin
        if (tr.HADDR[1])
          merge_write = {tr.HWDATA[31:16], old[15:0]};
        else
          merge_write = {old[31:16], tr.HWDATA[15:0]};
      end
      default: merge_write = tr.HWDATA;   // word 写
    endcase
  endfunction

  // 读比较
  function void compare_read(ahb_transaction tr);
    bit [31:0] exp_raw;
    bit [31:0] exp;
    // 计算期望原始值
    if (tr.HADDR[15:0] <= 16'h000F) begin
      case (tr.HADDR[4:2])
        3'd0: exp_raw = ref_ctrl0;
        3'd1: exp_raw = ref_ctrl1;
        3'd2: exp_raw = ref_ctrl2;
        3'd3: exp_raw = ref_ctrl3;
        default: exp_raw = 32'b0;
      endcase
    end
    else if (tr.HADDR[15:0] >= 16'h0020 && tr.HADDR[15:0] <= 16'h041F) begin
      exp_raw = ref_mem[tr.HADDR[9:2] - 8'd8];
    end
    else begin
      exp_raw = 32'b0;
    end
    // lane 对齐（与 DUT 读通路一致）
    case (tr.HSIZE)
      3'b000: exp = exp_raw[8*tr.HADDR[1:0] +: 8] << (8*tr.HADDR[1:0]);
      3'b001: exp = tr.HADDR[1] ? {exp_raw[15:0], 16'h0} : {16'h0, exp_raw[15:0]};
      default: exp = exp_raw;
    endcase
    // 比较
    if (tr.HRDATA == exp) begin
      pass_count++;
      `uvm_info(get_type_name(), $sformatf("PASS addr: %0h data: %0h", tr.HADDR, tr.HRDATA), UVM_LOW);
    end else begin
      fail_count++;
      `uvm_error(get_type_name(), $sformatf("FAIL addr: %0h got: %0h exp: %0h", tr.HADDR, tr.HRDATA, exp));
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf("SCOREBOARD SUMMARY: pass=%0d fail=%0d err_resp=%0d", pass_count, fail_count, err_count), UVM_LOW);
    if (fail_count > 0)
      `uvm_error(get_type_name(), $sformatf("TEST FAILED with %0d mismatches", fail_count));
  endfunction

endclass