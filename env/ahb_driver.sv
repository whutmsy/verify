class ahb_driver extends uvm_driver #(ahb_transaction);
  `uvm_component_utils(ahb_driver)
  virtual ahb_slave_if vif;
  ahb_transaction trans;
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual ahb_slave_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", {"virtual interface must be set for: ", get_full_name(), ".vif"});
  endfunction
  task run_phase(uvm_phase phase);
    ahb_transaction rsp;
    forever begin
      seq_item_port.get_next_item(trans);
      rsp = ahb_transaction::type_id::create("rsp");
      rsp.set_sequence_id(trans.get_sequence_id());
      rsp.set_transaction_id(trans.get_transaction_id());
      drive_ahb(trans, rsp);
      seq_item_port.item_done(rsp);
    end
  endtask
  // 总线复位到空闲状态
  task ahb_reset();
    `uvm_info(get_type_name(), "AHB reset", UVM_HIGH);
    vif.HSEL   <= 1'b0;
    vif.HADDR  <= 32'h0;
    vif.HTRANS <= 2'b00;
    vif.HWRITE <= 1'b0;
    vif.HSIZE  <= 3'b000;
    vif.HWDATA <= 32'h0;
  endtask
  // 写数据 lane 对齐（AHB 规范：数据放在与地址对应的 lane）
  function [31:0] align_wdata(bit [31:0] data, bit [2:0] size, bit [1:0] addr_low);
    case (size)
      3'b000: align_wdata = (data[7:0] << (8*addr_low));
      3'b001: align_wdata = addr_low[1] ? {data[15:0], 16'h0} : {16'h0, data[15:0]};
      default: align_wdata = data;
    endcase
  endfunction

  // AHB 事务驱动（规范主端时序）
  //   - 地址阶段：上升沿后驱动地址与控制信号
  //   - 数据阶段：下一上升沿驱动写数据（lane 对齐），地址阶段切换为 IDLE（流水线）
  //   - 等待 HREADY 拉高（数据阶段完成，期间从设备可插入 wait/ERROR）
  task drive_ahb(ahb_transaction trans, ahb_transaction rsp);
    `uvm_info(get_type_name(), $sformatf("Driving AHB transaction addr: %0h data: %0h hwrite: %0h hsize: %0h", trans.HADDR, trans.HWDATA, trans.HWRITE, trans.HSIZE), UVM_LOW);
    // 地址阶段
    @(posedge vif.HCLK iff (vif.HRESETn == 1'b1));
    vif.HSEL   <= 1'b1;
    vif.HADDR  <= trans.HADDR;
    vif.HTRANS <= trans.HTRANS;
    vif.HWRITE <= trans.HWRITE;
    vif.HSIZE  <= trans.HSIZE;
    // 数据阶段：驱动写数据（lane 对齐），地址阶段切换为 IDLE
    @(posedge vif.HCLK iff (vif.HRESETn == 1'b1));
    vif.HWDATA <= align_wdata(trans.HWDATA, trans.HSIZE, trans.HADDR[1:0]);
    vif.HSEL   <= 1'b0;
    vif.HTRANS <= 2'b00;
    // #1：越过沿后 delta，等待 HREADY 组合输出传播为数据阶段的值
    // （否则 wait 会读到地址阶段末的 HREADY=1 而提前结束）
    #1;
    // 等待数据阶段完成（HREADY 拉高，从设备可能插入 wait 拍）
    wait(vif.HREADY == 1'b1);
    // #1：等待 HRDATA/HRESP 组合输出传播稳定后再采样
    #1;
    // 采样读数据（完成拍 HRDATA 组合输出有效）
    if(!vif.HWRITE) begin
      rsp.HRDATA = vif.HRDATA;
      rsp.HRESP  = vif.HRESP;
      `uvm_info(get_type_name(), $sformatf("rsp.HRDATA: %0h HRESP: %0b", rsp.HRDATA, rsp.HRESP), UVM_HIGH)
    end
    else begin
      rsp.HRDATA = align_wdata(trans.HWDATA, trans.HSIZE, trans.HADDR[1:0]);
      rsp.HRESP  = vif.HRESP;
    end
    rsp.HADDR  = trans.HADDR;
    rsp.HWRITE = trans.HWRITE;
    rsp.HSIZE  = trans.HSIZE;
    rsp.HTRANS = trans.HTRANS;
    // 事务结束：总线回到空闲（下一事务重新开始地址阶段）
    @(posedge vif.HCLK iff (vif.HRESETn == 1'b1));
    ahb_reset();
  endtask
endclass