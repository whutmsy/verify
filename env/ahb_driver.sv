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
  task ahb_reset();
    `uvm_info(get_type_name(), "AHB reset", UVM_HIGH);
    vif.HSEL <= 1'b0;
    vif.HADDR <= 32'h0;
    vif.HTRANS <= 2'b00;
    vif.HWRITE <= 1'b0;
    vif.HSIZE <= 2'b00;
    vif.HWDATA <= 32'h0;
  endtask
  task drive_ahb(ref ahb_transaction trans, ahb_transaction rsp);
    `uvm_info(get_type_name(), $sformatf("Driving AHB transaction addr: %0h data: %0h hwrite: %0h", trans.HADDR, trans.HWDATA, trans.HWRITE), UVM_LOW);
    @(posedge vif.HCLK iff (vif.HRESETn == 1'b1));
    vif.HSEL <= 1'b1;
    vif.HADDR <= trans.HADDR;
    vif.HTRANS <= trans.HTRANS;
    vif.HWRITE <= trans.HWRITE;
    vif.HSIZE <= trans.HSIZE;
    @(posedge vif.HCLK iff (vif.HRESETn == 1'b1));
    if(vif.HWRITE) vif.HWDATA <= trans.HWDATA;
    wait(vif.HREADY == 1'b1);
    if(!vif.HWRITE) begin
      repeat(1) @(posedge vif.HCLK iff (vif.HRESETn == 1'b1));
      rsp.HRDATA = vif.HRDATA;
      `uvm_info(get_type_name(), $sformatf("rsp.HRDATA: %0h", rsp.HRDATA), UVM_HIGH)
    end
    else begin
      rsp.HRDATA = trans.HWDATA;
      repeat(1) @(posedge vif.HCLK iff (vif.HRESETn == 1'b1));
    end
    rsp.HADDR = trans.HADDR;
    rsp.HWRITE = trans.HWRITE;
    rsp.HSIZE = trans.HSIZE;
    rsp.HTRANS = trans.HTRANS;
    ahb_reset();
  endtask
endclass